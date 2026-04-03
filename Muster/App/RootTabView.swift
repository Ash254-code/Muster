import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "leaf") }

            MusterView()
                .tabItem { Label("Muster", systemImage: "map") }

            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
        }
    }
}
