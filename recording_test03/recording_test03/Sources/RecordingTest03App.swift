import SwiftUI

@main
struct RecordingTest03App: App {
    init() {
        // 初回起動時のDefault作成と、旧Documents直下ファイルの移行を実行する。
        try? RecordingFileStore.shared.prepareStorage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
