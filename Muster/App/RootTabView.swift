import SwiftUI

struct RootTabView: View {
    var body: some View {
        NavigationStack {
            MapMainView()
                .navigationBarHidden(true)
        }
    }
}
