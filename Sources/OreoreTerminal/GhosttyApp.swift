import AppKit
import GhosttyKit

/// Notification posted when a ghostty surface title changes.
/// userInfo contains "title" (String).
extension Notification.Name {
    public static let ghosttyTitleChanged = Notification.Name("ghosttyTitleChanged")
    /// Posted when ghostty receives an OSC 9/777 desktop notification request.
    /// userInfo contains "title" (String) and "body" (String).
    public static let ghosttyDesktopNotification = Notification.Name("ghosttyDesktopNotification")
    /// Toggle sidebar visibility.
    public static let toggleSidebar = Notification.Name("toggleSidebar")
}

/// Wrapper around the libghostty app instance.
/// Manages the global ghostty state and provides surface creation.
public final class GhosttyAppWrapper {
    private(set) var app: ghostty_app_t?
    private var tickTimer: Timer?
    /// The most recently focused terminal surface, used for clipboard operations.
    var focusedSurface: ghostty_surface_t?

    public init() {
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
        runtimeConfig.close_surface_cb = { userdata, processAlive in
            // Surface close requested - handle in UI layer
        }

        app = ghostty_app_new(&runtimeConfig, config)
        ghostty_config_free(config)

        guard app != nil else {
            fatalError("Failed to create ghostty app")
        }

        // Start tick timer for the event loop
        tickTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    func tick() {
        guard let app else { return }
        ghostty_app_tick(app)
    }

    func createSurface(for view: NSView) -> ghostty_surface_t? {
        guard let app else { return nil }

        var config = ghostty_surface_config_new()
        config.platform_tag = GHOSTTY_PLATFORM_MACOS
        config.platform.macos.nsview = Unmanaged.passUnretained(view).toOpaque()

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
            DispatchQueue.main.async {
                NotificationCenter.default.post(
                    name: .ghosttyDesktopNotification,
                    object: nil,
                    userInfo: ["title": title, "body": body]
                )
            }
        case GHOSTTY_ACTION_RENDER:
            break
        case GHOSTTY_ACTION_CELL_SIZE:
            break
        default:
            break
        }
        return true
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
