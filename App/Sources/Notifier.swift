import Foundation
import UserNotifications

/// Mac notifications for things that finish while the window is in the background.
@MainActor
enum Notifier {
    static func post(title: String, body: String) {
        guard !Snapshot.usesFixtures, Snapshot.directory == nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }
}
