import Foundation
import UserNotifications

/// Manages macOS desktop notifications via UNUserNotificationCenter.
public final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    /// Callback invoked when a notification is clicked.
    /// Parameters: workspaceIndex, areaId
    public var onNotificationClicked: ((Int, UUID) -> Void)?

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

    /// Send a desktop notification with workspace/area context embedded in userInfo.
    public func sendNotification(
        title: String,
        body: String,
        workspaceIndex: Int,
        areaId: UUID
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.userInfo = [
            "workspaceIndex": workspaceIndex,
            "areaId": areaId.uuidString
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

        if let workspaceIndex = userInfo["workspaceIndex"] as? Int,
           let areaIdString = userInfo["areaId"] as? String,
           let areaId = UUID(uuidString: areaIdString) {
            DispatchQueue.main.async { [weak self] in
                self?.onNotificationClicked?(workspaceIndex, areaId)
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
        // Don't show notifications when app is foreground (they only fire when inactive)
        completionHandler([])
    }
}
