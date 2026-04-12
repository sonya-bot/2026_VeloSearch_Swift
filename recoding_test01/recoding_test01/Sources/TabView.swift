import SwiftUI

struct ContentView: View {
  // アプリ起動時に最初に表示したいタブの番号を指定（例: 1 = Recordings）
  @State private var selectedTab = 1

  var body: some View {

    TabView(selection: $selectedTab) {
      Tab("Detectings", systemImage: "waveform", value: 0) {
        DetectingsView()
      }

      Tab("Recordings", systemImage: "mic.fill", value: 1) {
        RecordingsView()
      }

      Tab("Collections", systemImage: "square.stack.fill", value: 2) {
        CollectionsView()
      }

      Tab("Settings", systemImage: "gearshape", value: 3) {
        SettingsView()
      }
    }
    // iPadや横向きの時は自動でサイドバーになり、iPhoneでは下部のタブバーになります
    .tabViewStyle(.sidebarAdaptable)

    // （お好みで）スクロール時にタブバーを自動で隠す機能
    // リストなどをスクロールする画面がある場合に有効です
    // .tabBarMinimizeBehavior(.onScrollDown)
  }
}
