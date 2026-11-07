import AppKit
import Foundation
import UserNotifications

/// The kinds of notification, each with its own switch in Settings → Notifications. Saved in
/// UserDefaults as the kinds that are turned off, so a kind added later starts on.
enum NotificationKind: String, CaseIterable, Identifiable {
    case appUpdates, installsFinished, gameQueued, gamesSent, savesBackedUp, consoleHot

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appUpdates: return "App Updates"
        case .installsFinished: return "Installs Finished"
        case .gameQueued: return "New Game in a Watched Folder"
        case .gamesSent: return "Games Sent"
        case .savesBackedUp: return "Weekly Save Backup"
        case .consoleHot: return "PS3 Running Hot"
        }
    }

    var detail: String {
        switch self {
        case .appUpdates: return "A new version of an installed app is out."
        case .installsFinished: return "The install queue is done, with the apps that failed."
        case .gameQueued: return "A game in a watched folder has joined the queue."
        case .gamesSent: return "The queue has sent its games to the PS3."
        case .savesBackedUp: return "The weekly backup copied saves that had changed."
        case .consoleHot: return "CPU or RSX reaches Hot, at most once every half hour."
        }
    }

    static let mutedKey = "mutedNotifications"

    static var muted: Set<NotificationKind> {
        get { Set((UserDefaults.standard.stringArray(forKey: mutedKey) ?? []).compactMap(NotificationKind.init(rawValue:))) }
        set { UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: mutedKey) }
    }
}

/// Mac notifications for things that finish while the window is in the background.
@MainActor
enum Notifier {
    /// What macOS allows, as Settings shows it.
    enum Permission {
        case notAsked, allowed, denied
    }

    static func post(_ kind: NotificationKind, title: String, body: String) {
        guard !Snapshot.usesFixtures, Snapshot.directory == nil, !NotificationKind.muted.contains(kind) else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
        }
    }

    static func permission() async -> Permission {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<UNAuthorizationStatus, Never>) in
            UNUserNotificationCenter.current().getNotificationSettings { continuation.resume(returning: $0.authorizationStatus) }
        }
        switch status {
        case .notDetermined: return .notAsked
        case .denied: return .denied
        default: return .allowed
        }
    }

    /// Asks macOS once; after a no, only System Settings can turn them on.
    static func requestPermission() async -> Permission {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        return await permission()
    }

    /// Opens PS3 Center's page under Notifications in System Settings (it only opens the page).
    static func openSystemSettings() {
        let id = Bundle.main.bundleIdentifier ?? "local.ps3center.app"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }
}
