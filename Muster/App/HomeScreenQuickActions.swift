import UIKit

@MainActor
enum HomeScreenQuickAction: String {
    case startNewTrack = "com.muster.quickaction.startNewTrack"
    case importFiles = "com.muster.quickaction.import"
}

extension Notification.Name {
    static let homeScreenQuickActionTriggered = Notification.Name("homeScreenQuickActionTriggered")
}

@MainActor
private enum HomeScreenQuickActionDispatcher {
    static func dispatch(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
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

final class HomeScreenQuickActionDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        config.delegateClass = HomeScreenQuickActionSceneDelegate.self
        return config
    }
}

final class HomeScreenQuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let shortcutItem = connectionOptions.shortcutItem {
            _ = HomeScreenQuickActionDispatcher.dispatch(shortcutItem)
        }
    }

    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(HomeScreenQuickActionDispatcher.dispatch(shortcutItem))
    }
}
