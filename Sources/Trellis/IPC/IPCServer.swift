import Foundation
import GhosttyKit

/// Unix Domain Socket server for external CLI control.
/// Listens at ~/.trellis/control.sock and handles newline-delimited JSON commands.
/// All operations run on the main queue to safely access WorkspaceStore and ghostty APIs.
@MainActor
public final class IPCServer {
    public static let socketPath: String = {
        "\(NSHomeDirectory())/.trellis/control.sock"
    }()

    private weak var store: WorkspaceStore?
    private weak var ghosttyApp: (any GhosttyAppProviding)?

    private var serverFd: Int32 = -1
    private var serverSource: DispatchSourceRead?
    private var clientSources: [Int32: DispatchSourceRead] = [:]
    private var clientBuffers: [Int32: Data] = [:]
    private var clientWriteBuffers: [Int32: Data] = [:]
    private var clientWriteSources: [Int32: DispatchSourceWrite] = [:]
    private var isRunning = false

    /// Maximum write buffer size per client before disconnecting (256 KB)
    private static let maxWriteBufferSize = 256 * 1024

    public init(store: WorkspaceStore, ghosttyApp: any GhosttyAppProviding) {
        self.store = store
        self.ghosttyApp = ghosttyApp
    }

    public func start() throws {
        guard !isRunning else { return }

        let dir = (IPCServer.socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        // Remove stale socket from a previous crash
        unlink(IPCServer.socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else { throw IPCError.socketCreationFailed(errno) }

        var addr = sockaddr_un()
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        addr.sun_family = sa_family_t(AF_UNIX)
        IPCServer.socketPath.withCString { src in
            withUnsafeMutableBytes(of: &addr.sun_path) { dest in
                _ = strncpy(
                    dest.baseAddress!.assumingMemoryBound(to: CChar.self),
                    src,
                    dest.count - 1
                )
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(serverFd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            close(serverFd)
            throw IPCError.bindFailed(errno)
        }

        guard listen(serverFd, 10) == 0 else {
            close(serverFd)
            throw IPCError.listenFailed(errno)
        }

        let source = DispatchSource.makeReadSource(fileDescriptor: serverFd, queue: .main)
        source.setEventHandler { [weak self] in self?.acceptClient() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.serverFd, fd >= 0 { close(fd) }
        }
        source.resume()
        serverSource = source
        isRunning = true
    }

    public func stop() {
        guard isRunning else { return }
        serverSource?.cancel()
        serverSource = nil
        clientWriteSources.values.forEach { $0.cancel() }
        clientWriteSources.removeAll()
        clientWriteBuffers.removeAll()
        clientSources.values.forEach { $0.cancel() }
        clientSources.removeAll()
        clientBuffers.removeAll()
        unlink(IPCServer.socketPath)
        isRunning = false
    }

    // MARK: - Connection Handling

    private func acceptClient() {
        var clientAddr = sockaddr_un()
        var addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let clientFd = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                accept(serverFd, $0, &addrLen)
            }
        }
        guard clientFd >= 0 else { return }

        // Set non-blocking mode so writes never block the main queue
        let flags = fcntl(clientFd, F_GETFL)
        if flags >= 0 {
            _ = fcntl(clientFd, F_SETFL, flags | O_NONBLOCK)
        }

        clientBuffers[clientFd] = Data()

        let source = DispatchSource.makeReadSource(fileDescriptor: clientFd, queue: .main)
        source.setEventHandler { [weak self] in self?.readClient(fd: clientFd) }
        source.setCancelHandler { close(clientFd) }
        source.resume()
        clientSources[clientFd] = source
    }

    private func readClient(fd: Int32) {
        var buf = [UInt8](repeating: 0, count: 4096)
        let n = read(fd, &buf, buf.count)

        guard n > 0 else {
            removeClient(fd: fd)
            return
        }

        clientBuffers[fd, default: Data()].append(contentsOf: buf[0..<n])

        while let newlineIdx = clientBuffers[fd]?.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = Data(clientBuffers[fd]!.prefix(upTo: newlineIdx))
            clientBuffers[fd] = Data(clientBuffers[fd]!.suffix(from: clientBuffers[fd]!.index(after: newlineIdx)))

            let response = handleRequest(data: lineData)
            writeResponse(fd: fd, data: response)
        }
    }

    private func removeClient(fd: Int32) {
        clientWriteSources[fd]?.cancel()
        clientWriteSources.removeValue(forKey: fd)
        clientWriteBuffers.removeValue(forKey: fd)
        clientSources[fd]?.cancel()
        clientSources.removeValue(forKey: fd)
        clientBuffers.removeValue(forKey: fd)
    }

    private func writeResponse(fd: Int32, data: Data) {
        var out = data
        out.append(UInt8(ascii: "\n"))

        clientWriteBuffers[fd, default: Data()].append(out)

        if clientWriteBuffers[fd, default: Data()].count > Self.maxWriteBufferSize {
            removeClient(fd: fd)
            return
        }

        ensureWriteSource(fd: fd)
    }

    private func ensureWriteSource(fd: Int32) {
        guard clientWriteSources[fd] == nil else { return }

        let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.drainWriteBuffer(fd: fd) }
        source.setCancelHandler { /* fd is closed by removeClient's read source cancel */ }
        source.resume()
        clientWriteSources[fd] = source
    }

    private func drainWriteBuffer(fd: Int32) {
        guard var buffer = clientWriteBuffers[fd], !buffer.isEmpty else {
            // Nothing left to write; suspend the write source
            clientWriteSources[fd]?.cancel()
            clientWriteSources.removeValue(forKey: fd)
            return
        }

        let written = buffer.withUnsafeBytes { ptr -> Int in
            guard let base = ptr.baseAddress else { return 0 }
            return write(fd, base, ptr.count)
        }

        if written > 0 {
            buffer.removeFirst(written)
            clientWriteBuffers[fd] = buffer

            if buffer.isEmpty {
                clientWriteSources[fd]?.cancel()
                clientWriteSources.removeValue(forKey: fd)
            }
        } else if written < 0 && errno != EAGAIN && errno != EWOULDBLOCK {
            // Write error (broken pipe, etc.) — disconnect
            removeClient(fd: fd)
        }
        // written == 0 or EAGAIN: wait for next writable event
    }

    // MARK: - Command Dispatch

    private struct Request: Decodable {
        let command: String
        let target: String?
        let keys: String?
    }

    private func handleRequest(data: Data) -> Data {
        guard !data.isEmpty,
              let request = try? JSONDecoder().decode(Request.self, from: data)
        else {
            return errorResponse("invalid JSON")
        }

        switch request.command {
        case "list-panels":
            return listPanels()
        case "new-panel":
            return newPanel()
        case "send-keys":
            guard let keys = request.keys else {
                return errorResponse("send-keys requires 'keys'")
            }
            return sendKeys(target: request.target, keys: keys)
        default:
            return errorResponse("unknown command: \(request.command)")
        }
    }

    // MARK: - Commands

    private struct PanelInfo: Encodable {
        let id: String
        let title: String
        let pwd: String?
        let gitBranch: String?
        let workspaceName: String
    }

    private struct ListPanelsResponse: Encodable {
        let panels: [PanelInfo]
    }

    // MARK: - new-panel (internal: used by CLI send-keys without -p)

    private struct NewPanelResponse: Encodable {
        let id: String
    }

    private func newPanel() -> Data {
        guard let store else { return errorResponse("store unavailable") }
        guard let workspace = store.activeWorkspace,
              let areaId = workspace.activeAreaId
        else {
            return errorResponse("no active area")
        }

        let before = Set(store.allSessions.map { $0.id })
        store.addTerminalTab(to: areaId)

        guard let newSession = store.allSessions.first(where: { !before.contains($0.id) }) else {
            return errorResponse("failed to create panel")
        }
        let response = NewPanelResponse(id: "s:\(newSession.id)")
        return (try? JSONEncoder().encode(response)) ?? errorResponse("encoding failed")
    }

    // MARK: - list-panels

    private func listPanels() -> Data {
        guard let store else { return errorResponse("store unavailable") }
        var panels: [PanelInfo] = []
        for workspace in store.workspaces {
            for area in workspace.allAreas {
                for tab in area.tabs {
                    if case .terminal(let session) = tab.content {
                        panels.append(PanelInfo(
                            id: "s:\(session.id)",
                            title: session.title,
                            pwd: session.pwd,
                            gitBranch: session.gitBranch,
                            workspaceName: workspace.name
                        ))
                    }
                }
            }
        }
        let response = ListPanelsResponse(panels: panels)
        return (try? JSONEncoder().encode(response)) ?? errorResponse("encoding failed")
    }

    private func sendKeys(target: String?, keys: String) -> Data {
        let surface: ghostty_surface_t

        if let target {
            guard let store else { return errorResponse("store unavailable") }
            guard target.hasPrefix("s:"),
                  let uuid = UUID(uuidString: String(target.dropFirst(2))),
                  let session = store.allSessions.first(where: { $0.id == uuid })
            else {
                return errorResponse("session not found: \(target)")
            }
            guard let app = ghosttyApp, let s = app.surface(for: session) else {
                return errorResponse("surface not ready for: \(target)")
            }
            surface = s
        } else {
            guard let ghosttyApp else { return errorResponse("app unavailable") }
            guard let s = ghosttyApp.focusedSurface else {
                return errorResponse("no focused panel")
            }
            surface = s
        }

        keys.withCString { ghostty_surface_text(surface, $0, UInt(keys.utf8.count)) }
        return okResponse()
    }

    // MARK: - Response Helpers

    private struct OkResponse: Encodable {
        let ok: Bool
        let error: String?
    }

    private func okResponse() -> Data {
        (try? JSONEncoder().encode(OkResponse(ok: true, error: nil))) ?? Data()
    }

    private func errorResponse(_ message: String) -> Data {
        (try? JSONEncoder().encode(OkResponse(ok: false, error: message))) ?? Data()
    }
}

enum IPCError: Error {
    case socketCreationFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
}
