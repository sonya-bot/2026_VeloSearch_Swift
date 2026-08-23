import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 1. AudioPlaybackController (動作の定義)
@Observable
final class AudioPlaybackController {
  private let recordingFileStore: RecordingFileStoring
  private let userDefaults: UserDefaults

  init(recordingFileStore: RecordingFileStoring, userDefaults: UserDefaults) {
    self.recordingFileStore = recordingFileStore
    self.userDefaults = userDefaults
  }

  var audioPlayer: AVAudioPlayer?

  var isPlaying = false
  var currentTime: TimeInterval = 0.0
  var duration: TimeInterval = 0.0

  // メーター用のレベル変数 (0.0 〜 1.0)
  var leftLevel: CGFloat = 0.0
  var rightLevel: CGFloat = 0.0
  var leftDecibel: Float = 0.0
  var rightDecibel: Float = 0.0

  private var timer: Timer?

  func prepareAudio(audio: URL) {
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: audio)
      audioPlayer?.isMeteringEnabled = true
      audioPlayer?.prepareToPlay()
      duration = audioPlayer?.duration ?? 0.0
      currentTime = 0.0
    } catch {
      AppLogger.audio.error("音声の準備に失敗しました: \(error.localizedDescription)")
    }
  }

  func startPlayback() {
    let playbackSession = AVAudioSession.sharedInstance()
    let outputRawValue =
      userDefaults.string(forKey: "selectedOutputDevice")
      ?? OutputDeviceOption.speaker.rawValue
    let outputDevice = OutputDeviceOption(rawValue: outputRawValue) ?? .speaker
    do {
      let options: AVAudioSession.CategoryOptions =
        outputDevice == .speaker ? [.defaultToSpeaker] : [.allowBluetoothA2DP]
      try playbackSession.setCategory(.playAndRecord, mode: .default, options: options)
      try playbackSession.setActive(true)
      try playbackSession.overrideOutputAudioPort(outputDevice == .speaker ? .speaker : .none)

      audioPlayer?.play()
      isPlaying = true

      timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
        guard let self = self, let player = self.audioPlayer else { return }
        if player.isPlaying {
          self.currentTime = player.currentTime

          // メーターの更新とレベル計算
          player.updateMeters()
          let minDb: Float = -60.0
          let leftPower = player.averagePower(forChannel: 0)
          let rightPower =
            player.numberOfChannels > 1 ? player.averagePower(forChannel: 1) : leftPower

          self.leftDecibel = leftPower
          self.rightDecibel = rightPower
          self.leftLevel = CGFloat(max(0.0, min(1.0, (leftPower - minDb) / abs(minDb))))
          self.rightLevel = CGFloat(max(0.0, min(1.0, (rightPower - minDb) / abs(minDb))))

        } else {
          self.stopPlayback()
        }
      }
    } catch {
      AppLogger.audio.error("再生に失敗しました: \(error.localizedDescription)")
    }
  }

  func pausePlayback() {
    audioPlayer?.pause()
    isPlaying = false
  }

  func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
    timer?.invalidate()
    timer = nil
    leftLevel = 0.0
    rightLevel = 0.0
    leftDecibel = 0.0
    rightDecibel = 0.0
  }

  func seek(to time: TimeInterval) {
    audioPlayer?.currentTime = time
    self.currentTime = time
  }

  func deleteAudio(audio: URL) {
    self.stopPlayback()
    do {
      // WAVと対応する通常CSV・Dev CSVを一組として削除する。
      try recordingFileStore.deleteRecording(at: audio)
      userDefaults.removeObject(forKey: audio.lastPathComponent)
    } catch {
      AppLogger.storage.error("録音の削除に失敗しました: \(error.localizedDescription)")
    }
  }
}
