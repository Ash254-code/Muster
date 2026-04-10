import UIKit

@MainActor
enum HomeScreenQuickAction: String {
    case startNewTrack = "com.muster.quickaction.startNewTrack"
    case importFiles = "com.muster.quickaction.import"
}

extension Notification.Name {
    static let homeScreenQuickActionTriggered = Notification.Name("homeScreenQuickActionTriggered")
}

final class HomeScreenQuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        if let shortcutItem = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem {
            _ = handle(shortcutItem)
            return false
        }

        return true
    }

    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(handle(shortcutItem))
    }

    private func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        guard let action = HomeScreenQuickAction(rawValue: shortcutItem.type) else {
            return false
        }

        NotificationCenter.default.post(
            name: .homeScreenQuickActionTriggered,
            object: nil,
            userInfo: ["action": action.rawValue]
        )
        return true
    }
}
