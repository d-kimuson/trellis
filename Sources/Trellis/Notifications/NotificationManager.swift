import Foundation
import UserNotifications

/// Manages macOS desktop notifications via UNUserNotificationCenter.
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    /// Callback invoked when a notification is clicked.
    /// Parameter: sessionId of the panel that generated the notification.
    public var onNotificationClicked: ((UUID) -> Void)?

    override public init() {
        super.init()
        let center = UNUserNotificationCenter.current()
        center.delegate = self
    }

    // MARK: - Authorization

    /// Request notification permissions from the user.
    public func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .badge]) { granted, error in
            if let error {
                print("Notification authorization error: \(error.localizedDescription)")
            }
            if !granted {
                print("Notification permission not granted")
            }
        }
    }

    // MARK: - Send Notification

    /// Send a desktop notification with the source session ID embedded in userInfo.
    public func sendNotification(
        title: String,
        body: String,
        sessionId: UUID
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [
            "sessionId": sessionId.uuidString
        ]

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Failed to send notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Called when the user taps a notification.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo

        if let sessionIdString = userInfo["sessionId"] as? String,
           let sessionId = UUID(uuidString: sessionIdString) {
            DispatchQueue.main.async { [weak self] in
                self?.onNotificationClicked?(sessionId)
            }
        }

        completionHandler()
    }

    /// Allow notifications to display even when the app is in the foreground.
    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
