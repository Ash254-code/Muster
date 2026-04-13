import SwiftUI

@main
struct MusteringApp: App {

    @UIApplicationDelegateAdaptor(HomeScreenQuickActionDelegate.self) private var quickActionDelegate
    @StateObject private var app = AppState()
    @StateObject private var ble = BLERadioDebugger.shared
    @AppStorage("appearance_mode") private var appearanceMode: String = "system"
    @Environment(\.scenePhase) private var scenePhase

    init() {
        UISwitch.appearance().onTintColor = .systemBlue
    }

    private var preferredScheme: ColorScheme? {
        switch appearanceMode {
        case "light":
            return .light
        case "dark":
            return .dark
        default:
            return nil   // follows system
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(app)
                .environmentObject(ble)
                .preferredColorScheme(preferredScheme)
                .task { await app.bootstrapIfNeeded() }
                .onReceive(NotificationCenter.default.publisher(for: .homeScreenQuickActionTriggered)) { notification in
                    guard let rawValue = notification.userInfo?["action"] as? String,
                          let action = HomeScreenQuickAction(rawValue: rawValue) else { return }
                    app.queueQuickAction(action)
                }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            switch newPhase {
            case .background, .inactive:
                app.muster.flushPendingSaves()
                app.xrs.save()
                app.endRadioAudioDuckIfNeeded()
            default:
                break
            }
        }
    }
}
