import AVFoundation
import Foundation

@MainActor
final class AudioPreviewController {
  private var audioPlayer: AVAudioPlayer?

  func play(fileName: String) {
    stop()

    guard let url = Bundle.main.url(forResource: fileName, withExtension: "wav") else {
      AppLogger.audio.error("プレビュー音源が見つかりません: \(fileName).wav")
      return
    }

    do {
      audioPlayer = try AVAudioPlayer(contentsOf: url)
      audioPlayer?.numberOfLoops = 0
      audioPlayer?.play()
    } catch {
      AppLogger.audio.error("音源のプレビュー再生に失敗しました: \(error.localizedDescription)")
    }
  }

  func stop() {
    audioPlayer?.stop()
    audioPlayer = nil
  }
}
