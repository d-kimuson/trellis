import AppKit
import GhosttyKit

/// Notification posted when a ghostty surface title changes.
/// userInfo contains "title" (String).
extension Notification.Name {
    public static let ghosttyTitleChanged = Notification.Name("ghosttyTitleChanged")
    /// Toggle sidebar visibility.
    public static let toggleSidebar = Notification.Name("toggleSidebar")
}

/// Wrapper around the libghostty app instance.
/// Manages the global ghostty state and provides surface creation.
public final class GhosttyAppWrapper {
    /// Singleton reference for C callback access (C function pointers can't capture context).
    static weak var current: GhosttyAppWrapper?

    private(set) var app: ghostty_app_t?
    private var tickTimer: Timer?
    /// The most recently focused terminal surface, used for clipboard operations.
    var focusedSurface: ghostty_surface_t?

    /// Called synchronously on the main thread when OSC 9/777 desktop notification arrives.
    /// Parameters: (title, body)
    public var onDesktopNotification: ((String, String) -> Void)?

    public init() {
        GhosttyAppWrapper.current = self

        // Initialize ghostty global state
        guard ghostty_init(0, nil) == GHOSTTY_SUCCESS else {
            fatalError("Failed to initialize ghostty")
        }

        // Create and configure config
        let config = ghostty_config_new()!
        ghostty_config_load_default_files(config)
        ghostty_config_finalize(config)

        // Set up runtime callbacks
        var runtimeConfig = ghostty_runtime_config_s()
        runtimeConfig.userdata = Unmanaged.passUnretained(self).toOpaque()
        runtimeConfig.supports_selection_clipboard = false
        runtimeConfig.wakeup_cb = { userdata in
            guard let userdata else { return }
            let wrapper = Unmanaged<GhosttyAppWrapper>.fromOpaque(userdata).takeUnretainedValue()
            DispatchQueue.main.async {
                wrapper.tick()
            }
        }
        runtimeConfig.action_cb = { app, target, action in
            guard let app else { return false }
            return GhosttyAppWrapper.handleAction(app: app, target: target, action: action)
        }
        runtimeConfig.read_clipboard_cb = { userdata, location, state in
            GhosttyAppWrapper.readClipboard(userdata: userdata, location: location, state: state)
        }
        runtimeConfig.confirm_read_clipboard_cb = { userdata, content, state, _ in
            // Auto-confirm all clipboard reads
            guard let userdata, let state else { return }
            let wrapper = Unmanaged<GhosttyAppWrapper>.fromOpaque(userdata).takeUnretainedValue()
            guard let surface = wrapper.focusedSurface else { return }
            ghostty_surface_complete_clipboard_request(surface, content, state, true)
        }
        runtimeConfig.write_clipboard_cb = { userdata, str, location, confirm in
            GhosttyAppWrapper.writeClipboard(userdata: userdata, string: str, location: location, confirm: confirm)
        }
        runtimeConfig.close_surface_cb = { _, _ in
            // Handled via GHOSTTY_ACTION_CLOSE_TAB / SHOW_CHILD_EXITED in action_cb
        }

        app = ghostty_app_new(&runtimeConfig, config)
        ghostty_config_free(config)

        guard app != nil else {
            fatalError("Failed to create ghostty app")
        }

        // Start tick timer for the event loop.
        // Must run in .common mode so it fires during event tracking / modal panels,
        // otherwise ghostty_app_tick() stalls and IO (including OSC notifications) is delayed.
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        tickTimer = timer
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func createSurface(
        for view: NSView,
        userdata: UnsafeMutableRawPointer? = nil,
        workingDirectory: String? = nil
    ) -> ghostty_surface_t? {
        guard let app else { return nil }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()
        config.userdata = userdata

        if let workingDirectory {
            // working_directory must remain valid until ghostty_surface_new returns.
            return workingDirectory.withCString { cstr in
                config.working_directory = cstr
                return ghostty_surface_new(app, &config)
            }
        }

        return ghostty_surface_new(app, &config)
    }

    public func shutdown() {
        tickTimer?.invalidate()
        tickTimer = nil
        if let app {
            ghostty_app_free(app)
        }
        app = nil
    }

    // MARK: - Static Callbacks

    private static func handleAction(
        app: ghostty_app_t,
        target: ghostty_target_s,
        action: ghostty_action_s
    ) -> Bool {
        switch action.tag {
        case GHOSTTY_ACTION_SET_TITLE:
            let setTitle = action.action.set_title
            if let titlePtr = setTitle.title {
                let title = String(cString: titlePtr)
                DispatchQueue.main.async {
                    NotificationCenter.default.post(
                        name: .ghosttyTitleChanged,
                        object: nil,
                        userInfo: ["title": title]
                    )
                }
            }
        case GHOSTTY_ACTION_DESKTOP_NOTIFICATION:
            let notif = action.action.desktop_notification
            let title = notif.title.map { String(cString: $0) } ?? "Notification"
            let body = notif.body.map { String(cString: $0) } ?? ""
            // Call directly — no DispatchQueue.main.async to avoid Metal render delays
            current?.onDesktopNotification?(title, body)
        case GHOSTTY_ACTION_PWD:
            let pwdAction = action.action.pwd
            if let pwdPtr = pwdAction.pwd {
                let pwd = String(cString: pwdPtr)
                if target.tag == GHOSTTY_TARGET_SURFACE {
                    let surface = target.target.surface
                    if let userdata = ghostty_surface_userdata(surface) {
                        let session = Unmanaged<TerminalSession>.fromOpaque(userdata).takeUnretainedValue()
                        DispatchQueue.main.async {
                            session.pwd = pwd
                        }
                    }
                }
            }
        case GHOSTTY_ACTION_CLOSE_TAB:
            notifySessionClose(target: target)
        case GHOSTTY_ACTION_SHOW_CHILD_EXITED:
            notifySessionClose(target: target)
        case GHOSTTY_ACTION_RENDER:
            break
        case GHOSTTY_ACTION_CELL_SIZE:
            break
        default:
            break
        }
        return true
    }

    /// Extract the TerminalSession from a surface target and notify it to close.
    private static func notifySessionClose(target: ghostty_target_s) {
        guard target.tag == GHOSTTY_TARGET_SURFACE else { return }
        let surface = target.target.surface
        guard let userdata = ghostty_surface_userdata(surface) else { return }
        let session = Unmanaged<TerminalSession>.fromOpaque(userdata).takeUnretainedValue()
        DispatchQueue.main.async {
            session.onProcessExited?()
        }
    }

    private static func readClipboard(
        userdata: UnsafeMutableRawPointer?,
        location: ghostty_clipboard_e,
        state: UnsafeMutableRawPointer?
    ) {
        guard let userdata, let state else { return }
        let wrapper = Unmanaged<GhosttyAppWrapper>.fromOpaque(userdata).takeUnretainedValue()
        guard let surface = wrapper.focusedSurface else { return }

        let pasteboard = NSPasteboard.general
        guard let content = pasteboard.string(forType: .string) else { return }

        content.withCString { cstr in
            ghostty_surface_complete_clipboard_request(surface, cstr, state, true)
        }
    }

    private static func writeClipboard(
        userdata: UnsafeMutableRawPointer?,
        string: UnsafePointer<CChar>?,
        location: ghostty_clipboard_e,
        confirm: Bool
    ) {
        guard let string else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(String(cString: string), forType: .string)
    }

    deinit {
        shutdown()
    }
}
