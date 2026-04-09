import SwiftUI
import UIKit

struct RootTabView: View {
    private var isCarPlay: Bool {
        UIDevice.current.userInterfaceIdiom == .carPlay
    }

    var body: some View {
        NavigationStack {
            Group {
                if isCarPlay {
                    CarPlayDashboardView()
                } else {
                    MapMainView()
                }
            }
            .navigationBarHidden(true)
        }
    }
}
