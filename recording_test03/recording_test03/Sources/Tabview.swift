import SwiftUI

struct ContentView: View {
  // アプリ起動時に最初に表示したいタブの番号を指定（例: 1 = Recordings）
  @State private var selectedTab = 0
  // 設定画面のモニタリング機能のON/OFF状態を管理する変数
  @AppStorage("isMonitoringEnabled") var isMonitoringEnabled: Bool = false

  var body: some View {

    TabView(selection: $selectedTab) {

      Tab("Detectings", systemImage: "waveform", value: 0) {
        DetectingsView()
      }

      Tab(
        isMonitoringEnabled ? "Monitorings" : "Recordings",
        systemImage: isMonitoringEnabled ? "headphones" : "mic.fill",
        value: 1
      ) {
        if isMonitoringEnabled {
          MonitoringsView()
        } else {
          RecordingsView()
        }
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
