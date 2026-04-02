import SwiftUI

@main
struct RecodingTest01App: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
            // ダークモードの設定
                .preferredColorScheme(.dark)
        }
    }
}
