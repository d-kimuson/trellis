import Foundation

// MARK: - CLI Mode Entry

/// Called when the binary is invoked with CLI subcommand arguments.
/// Connects to the running Trellis IPC server, sends the command, and exits.
/// This function always terminates the process via exit().
func runCLIMode(args: [String]) {
    let subcommand = args[0]

    switch subcommand {
    case "--help", "-h":
        printCLIUsage()
        exit(0)

    case "--version":
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        print("trellis \(version)")
        exit(0)

    case "list-panels":
        let response = sendIPCRequest(["command": "list-panels"])
        printPrettyJSON(response)
        exit(0)

    case "send-keys":
        let remaining = Array(args.dropFirst())
        let (target, text) = parseSendKeysArgs(remaining)
        guard !text.isEmpty else {
            fputs("error: send-keys requires <keys>\n", stderr)
            printCLIUsage()
            exit(1)
        }
        let keys = text

        if let target {
            // Send to existing panel
            let response = sendIPCRequest(["command": "send-keys", "target": target, "keys": keys])
            handleErrorResponse(response)
        } else {
            // No target: create new panel, wait for surface, then send
            let id = createPanelAndSend(keys: keys)
            print(id)  // print id so caller can reuse it
        }
        exit(0)

    default:
        fputs("error: unknown subcommand '\(subcommand)'\n", stderr)
        printCLIUsage()
        exit(1)
    }
}

// MARK: - New Panel + Send

/// Creates a new panel and sends keys to it once the surface is ready.
/// Returns the panel id. Exits on failure.
private func createPanelAndSend(keys: String) -> String {
    let newPanelResponse = sendIPCRequest(["command": "new-panel"])
    guard let panelId = extractId(from: newPanelResponse) else {
        handleErrorResponse(newPanelResponse)
        exit(1)
    }

    // Retry until the surface is ready (SwiftUI needs a render cycle after new-panel).
    // Poll up to 3 seconds in 100ms increments.
    for _ in 0..<30 {
        Thread.sleep(forTimeInterval: 0.1)
        let response = sendIPCRequest(["command": "send-keys", "target": panelId, "keys": keys])
        if let data = response.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ok = json["ok"] as? Bool {
            if ok { return panelId }
            // Surface not ready yet — keep retrying
            if let err = json["error"] as? String, !err.contains("surface not ready") {
                fputs("error: \(err)\n", stderr)
                exit(1)
            }
        }
    }
    fputs("error: surface not ready after timeout\n", stderr)
    exit(1)
}

// MARK: - Argument Parsing

/// Parse `[--panel|-p <id>] <text...> [Enter]` for send-keys.
/// `Enter` is a special keyword that appends a newline without a preceding space.
private func parseSendKeysArgs(_ args: [String]) -> (target: String?, text: String) {
    var target: String?
    var textParts: [String] = []
    var i = 0
    while i < args.count {
        if (args[i] == "--panel" || args[i] == "-p") && i + 1 < args.count {
            target = args[i + 1]
            i += 2
        } else {
            textParts.append(args[i])
            i += 1
        }
    }

    // Build text: join with spaces, but replace "Enter" tokens with "\n" (no surrounding spaces)
    var result = ""
    for (idx, part) in textParts.enumerated() {
        if part == "Enter" {
            result += "\n"
        } else {
            if idx > 0 && textParts[idx - 1] != "Enter" {
                result += " "
            }
            result += part
        }
    }
    return (target, result)
}

// MARK: - IPC Socket Client

private let cliSocketPath = "\(NSHomeDirectory())/.trellis/control.sock"

private func sendIPCRequest(_ request: [String: String]) -> String {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
        fputs("error: failed to create socket\n", stderr)
        exit(1)
    }
    defer { close(fd) }

    var addr = sockaddr_un()
    addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    addr.sun_family = sa_family_t(AF_UNIX)
    cliSocketPath.withCString { src in
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            _ = strncpy(dest.baseAddress!.assumingMemoryBound(to: CChar.self), src, dest.count - 1)
        }
    }

    let connected = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
    guard connected == 0 else {
        fputs("error: cannot connect to Trellis IPC server at \(cliSocketPath)\n", stderr)
        fputs("       Is Trellis running with 'External CLI control' enabled in Settings?\n", stderr)
        exit(1)
    }

    guard let data = try? JSONEncoder().encode(request),
          var line = String(data: data, encoding: .utf8) else {
        fputs("error: failed to encode request\n", stderr)
        exit(1)
    }
    line.append("\n")
    line.withCString { _ = write(fd, $0, strlen($0)) }

    var result = ""
    var buf = [UInt8](repeating: 0, count: 4096)
    while true {
        let n = read(fd, &buf, buf.count)
        guard n > 0 else { break }
        result += String(bytes: buf[0..<n], encoding: .utf8) ?? ""
        if result.contains("\n") { break }
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Response Helpers

private func extractId(from response: String) -> String? {
    guard let data = response.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = json["id"] as? String else { return nil }
    return id
}

private func printPrettyJSON(_ response: String) {
    if let data = response.data(using: .utf8),
       let json = try? JSONSerialization.jsonObject(with: data),
       let pretty = try? JSONSerialization.data(withJSONObject: json, options: .prettyPrinted),
       let prettyStr = String(data: pretty, encoding: .utf8) {
        print(prettyStr)
    } else {
        print(response)
    }
}

/// If response indicates error, print to stderr and exit(1). Otherwise does nothing.
private func handleErrorResponse(_ response: String) {
    guard let data = response.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ok = json["ok"] as? Bool, !ok
    else { return }
    let errMsg = json["error"] as? String ?? "unknown error"
    fputs("error: \(errMsg)\n", stderr)
    exit(1)
}

// MARK: - Help

private func printCLIUsage() {
    print("""
    Usage:
      trellis list-panels
      trellis send-keys [--panel, -p <id>] <keys> [Enter]

    Examples:
      trellis list-panels
      trellis send-keys 'codex .' Enter                 # new panel, run codex (prints panel id)
      trellis send-keys --panel s:<UUID> 'LGTM!' Enter  # existing panel

    Notes:
      --panel, -p <id>  Target panel id (from list-panels). If omitted,
                        a new panel is created and its id is printed to stdout.
      Enter             Append a newline to execute the command.
                        Trellis must be running with 'External CLI control' enabled in Settings.
    """)
}
