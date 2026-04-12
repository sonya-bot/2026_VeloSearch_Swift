import SwiftUI

struct ContentView: View {
    var body: some View {
        // iOS 18+ 向けの最新TabView API
        TabView {
            Tab("Detectings", systemImage: "waveform") {
                DetectingsView()
            }
            
            Tab("Recordings", systemImage: "mic.fill") {
                RecordingsView()
            }
            
            Tab("Collections", systemImage: "square.stack.fill") {
                CollectionsView()
            }
            
            Tab("Settings", systemImage: "gearshape") {
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