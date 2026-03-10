import Foundation

/// A pattern that triggers a desktop notification when matched against terminal title.
public struct NotificationPattern: Identifiable {
    public let id: UUID
    public let name: String
    public let regex: String
    public let notificationTitle: String

    public init(
        id: UUID = UUID(),
        name: String,
        regex: String,
        notificationTitle: String
    ) {
        self.id = id
        self.name = name
        self.regex = regex
        self.notificationTitle = notificationTitle
    }
}

/// Information for building a desktop notification.
public struct NotificationInfo {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}

/// Monitors terminal title changes and determines whether to fire notifications.
/// Pure logic — no dependency on UNUserNotificationCenter or NSApplication.
public struct TerminalOutputMonitor {
    public private(set) var patterns: [NotificationPattern]

    /// Tracks the previous title to detect transitions (command running → prompt return).
    public var previousTitle: String?

    /// Minimum interval between notifications (seconds) to avoid spam.
    public var cooldownInterval: TimeInterval = 3.0

    /// Last notification timestamp.
    public var lastNotificationTime: Date?

    public init() {
        self.patterns = Self.defaultPatterns
    }

    // MARK: - Default Patterns

    private static var defaultPatterns: [NotificationPattern] {
        [
            // Shell prompt return — indicates a command finished.
            // Matches common formats: "user@host:~/dir", "~/dir", "bash", "zsh"
            NotificationPattern(
                name: "Shell Prompt",
                regex: #"([\w.-]+@[\w.-]+:|~|/|bash|zsh)"#,
                notificationTitle: "Command Completed"
            )
        ]
    }

    // MARK: - Pattern Management

    public mutating func addPattern(_ pattern: NotificationPattern) {
        patterns.append(pattern)
    }

    public mutating func removePattern(id: UUID) {
        patterns.removeAll { $0.id == id }
    }

    // MARK: - Matching

    /// Returns the first matching pattern for the given terminal title, or nil.
    public func matchingPattern(for title: String) -> NotificationPattern? {
        patterns.first { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern.regex) else {
                return false
            }
            let range = NSRange(title.startIndex..., in: title)
            return regex.firstMatch(in: title, range: range) != nil
        }
    }

    /// Determines whether a notification should be sent.
    /// Fires when: app is inactive, title changed from previous, pattern matches,
    /// and cooldown has elapsed.
    public func shouldNotify(title: String, isAppActive: Bool) -> Bool {
        guard !isAppActive else { return false }
        guard title != previousTitle else { return false }
        if let lastTime = lastNotificationTime,
           Date().timeIntervalSince(lastTime) < cooldownInterval {
            return false
        }
        return matchingPattern(for: title) != nil
    }

    /// Builds notification info from a terminal title if a pattern matches.
    public func buildNotificationInfo(for title: String) -> NotificationInfo? {
        guard let pattern = matchingPattern(for: title) else { return nil }
        return NotificationInfo(
            title: pattern.notificationTitle,
            body: title
        )
    }

    /// Record that a title was observed (call after processing).
    public mutating func recordTitle(_ title: String) {
        previousTitle = title
    }

    /// Record that a notification was sent.
    public mutating func recordNotificationSent() {
        lastNotificationTime = Date()
    }
}
