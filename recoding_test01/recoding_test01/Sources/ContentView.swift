import SwiftUI

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}

struct ContentView: View {
    
    @State private var selectedTab = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black
                .ignoresSafeArea()

            Group {
                switch selectedTab {
                case 0:
                    RecordingsView()
                case 1:
                    CollectionView()
                case 2:
                    SettingsView()
                default:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea(edges: .bottom)

            // カスタムタブバーエリア
            CustomTabBar(selectedTab: $selectedTab)

        }
        .preferredColorScheme(.dark)
    }
}