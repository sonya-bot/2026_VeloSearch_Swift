import SwiftUI

@main
struct RecordingTest04App: App {
  private let dependencies = AppDependencies.live

  init() {
    // 既存データとの互換性を保つため、起動時に保存領域を準備する。
    do {
      try dependencies.recordingFileStore.prepareStorage()
    } catch {
      // recording_test03と同様に、移行に失敗してもアプリの起動は継続する。
      AppLogger.storage.error("保存領域の準備に失敗しました: \(error.localizedDescription)")
    }
  }

  var body: some Scene {
    WindowGroup {
      ContentView(dependencies: dependencies)
    }
  }
}
