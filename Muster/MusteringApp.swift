import SwiftUI

@main
struct MusteringApp: App {

    @StateObject private var app = AppState()
    @StateObject private var ble = BLERadioDebugger.shared
    @AppStorage("appearance_mode") private var appearanceMode: String = "system"
    @Environment(\.scenePhase) private var scenePhase

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
