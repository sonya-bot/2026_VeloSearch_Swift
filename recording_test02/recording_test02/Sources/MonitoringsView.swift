import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct MonitoringsView_Previews: PreviewProvider {
  static var previews: some View {
    MonitoringsView()
  }
}

// MARK: - 1. AudioMonitor (モニタリングロジック)
@Observable
class AudioMonitor {
  var audioRecorder: AVAudioRecorder?
  private var audioPlayer: AVAudioPlayer?  // 音源再生用

  var isRecording = false
  var elapsedTime: TimeInterval = 0.0
  var measurementStatus: String = "待機中"

  // L/Rそれぞれの音量データ (RecordingsViewと共通)
  var leftDecibel: Float = 0.0
  var rightDecibel: Float = 0.0
  var leftLevel: CGFloat = 0.0
  var rightLevel: CGFloat = 0.0

  private var timer: Timer?
  private var levelTimer: Timer?
  private var startTime: Date?
  private var measurementTask: Task<Void, Never>?

  func startRecording(orientation: String, micSource: String, prefix: String = "Monitoring") {
    // 録音ロジックは RecordingsView.swift を継承
    let audioSession = AVAudioSession.sharedInstance()
    let fileManager = FileManager.default
    let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

    // 命名規則の維持
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let dateString = formatter.string(from: Date())
    let nextNumber = getNextSequenceNumber(dateString: dateString, prefix: prefix, in: documentPath)
    let baseFileName = "\(prefix)_\(dateString)_\(String(format: "%02d", nextNumber))"
    let audioFilename = documentPath.appendingPathComponent("\(baseFileName).wav")

    // 設定から音源を取得
    let soundRawValue =
      UserDefaults.standard.string(forKey: "selectedMonitoringSound")
      ?? MonitoringSoundSource.sweep.rawValue
    let soundSource = MonitoringSoundSource(rawValue: soundRawValue) ?? .sweep

    do {
      try audioSession.setCategory(
        .playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])

      try audioSession.setActive(true)

      if let soundUrl = Bundle.main.url(forResource: soundSource.fileName, withExtension: "wav") {
        audioPlayer = try? AVAudioPlayer(contentsOf: soundUrl)
        audioPlayer?.prepareToPlay()  // 事前にメモリに読み込み、ルートを確定させる
      }

      if audioSession.maximumInputNumberOfChannels >= 2 {
        try audioSession.setPreferredInputNumberOfChannels(2)
      }

      // 録音マイク（前面/背面）とステレオ設定
      if let availableInputs = audioSession.availableInputs,
        let builtInMic = availableInputs.first(where: { $0.portType == .builtInMic })
      {
        if let dataSources = builtInMic.dataSources {
          let targetOrientation: AVAudioSession.Orientation = (micSource == "背面") ? .back : .front
          if let selectedDataSource = dataSources.first(where: {
            $0.orientation == targetOrientation
          }) {

            // 対象のマイク(前面/背面)をハードウェアにセット
            try builtInMic.setPreferredDataSource(selectedDataSource)

            // マイクのステレオ指向性をセット
            if let supportedPatterns = selectedDataSource.supportedPolarPatterns,
              supportedPatterns.contains(.stereo)
            {
              try selectedDataSource.setPreferredPolarPattern(.stereo)
              print("ステレオ入力を適用しました")
            } else {
              print("このマイクはステレオ入力をサポートしていません")
            }

            // デバイス全体にこのマイク入力を適用
            try audioSession.setPreferredInput(builtInMic)
            print("マイク設定: \(micSource) を選択")
          }
        }
      }

      // 端末の向き設定を反映（必ずマイク設定の「後」に行う）
      if orientation == "縦" {
        try audioSession.setPreferredInputOrientation(.portrait)
      } else {
        try audioSession.setPreferredInputOrientation(.landscapeRight)
      }

      // 録音設定
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
      audioRecorder?.isMeteringEnabled = true

      // --- 自動測定シーケンスの開始 ---
      isRecording = true
      elapsedTime = 0.0
      startTime = Date()

      // 時間計測タイマー
      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        guard let self = self, let startTime = self.startTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)
      }

      startMonitoring()

      // シーケンス制御: 録音開始 -> 1s待機 -> 再生 -> 終了待機 -> 1s待機 -> 停止
      measurementTask = Task {
        // 1. 録音開始
        audioRecorder?.record()
        await MainActor.run { self.measurementStatus = "録音中 (前余白)" }

        // 2. 前余白 1秒待機
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        if Task.isCancelled { return }

        // 3. 音源再生
        // await MainActor.run { self.measurementStatus = "テスト音再生中" }
        // if let soundUrl = Bundle.main.url(forResource: soundSource.fileName, withExtension: "wav") {
        //   audioPlayer = try? AVAudioPlayer(contentsOf: soundUrl)
        //   let duration = audioPlayer?.duration ?? 0
        //   audioPlayer?.play()

        //   // 4. 音源の長さ分待機
        //   try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
        // }
        await MainActor.run { self.measurementStatus = "テスト音再生中" }
        // ここでは既に準備済みのプレイヤーを再生するだけにする
        let duration = audioPlayer?.duration ?? 0
        audioPlayer?.play()

        // 4. 音源の長さ分待機
        try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))

        if Task.isCancelled { return }

        // 5. 後余白 1秒待機
        await MainActor.run { self.measurementStatus = "録音中 (後余白)" }
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        // 6. 自動停止
        await MainActor.run {
          self.stopRecording()
        }
      }

    } catch {
      print("録音エラー: \(error.localizedDescription)")
    }
  }

  func stopRecording() {
    measurementTask?.cancel()
    audioRecorder?.stop()
    audioPlayer?.stop()
    isRecording = false
    timer?.invalidate()
    levelTimer?.invalidate()
    leftLevel = 0.0
    rightLevel = 0.0
    measurementStatus = "待機中"
    elapsedTime = 0.0
    leftDecibel = 0.0
    rightDecibel = 0.0
  }

  private func startMonitoring() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.audioRecorder else { return }
      recorder.updateMeters()
      self.leftDecibel = recorder.averagePower(forChannel: 0)
      self.rightDecibel = recorder.averagePower(forChannel: 1)
      self.leftLevel = self.normalizeSoundLevel(level: self.leftDecibel)
      self.rightLevel = self.normalizeSoundLevel(level: self.rightDecibel)
    }
  }

  private func normalizeSoundLevel(level: Float) -> CGFloat {
    let minDb: Float = -60.0
    if level < minDb { return 0.01 }
    if level >= 0.0 { return 1.0 }
    return CGFloat((level - minDb) / abs(minDb))
  }

  private func getNextSequenceNumber(dateString: String, prefix: String, in directory: URL) -> Int {
    let fileManager = FileManager.default
    do {
      let files = try fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      let dailyFiles = files.filter {
        $0.lastPathComponent.hasPrefix("\(prefix)_\(dateString)") && $0.pathExtension == "wav"
      }
      return dailyFiles.count + 1
    } catch { return 1 }
  }
}

// MARK: - 2. MonitoringsView (UI)
struct MonitoringsView: View {
  @State private var audioMonitor = AudioMonitor()
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          GeometryReader { geometry in
            HStack(spacing: 30) {
              VStack(spacing: 10) {
                timeDisplay
                monitoringStatus
                Spacer()
                recordButton
                  .padding(.bottom, 100)
                Spacer()
              }
              .frame(width: (geometry.size.width - 30) / 3)

              VStack(spacing: 10) {
                micAssignmentLabels
                  .padding(.top, -20)
                // .padding(.bottom, 10)
                horizontalStereoMeters
                // Spacer()
              }
              .padding(.bottom, 160)
              .frame(width: (geometry.size.width - 30) * 2 / 3)
            }
            .frame(maxHeight: .infinity)
          }
          .padding()
        } else {
          // 【縦画面レイアウト】
          VStack(spacing: 20) {
            Spacer().frame(height: 80)
            timeDisplay
              .padding(.top, 30)
            monitoringStatus
            micAssignmentLabels
            // Spacer()
            verticalStereoMeters
            // Spacer()
            recordButton
              .padding(.bottom, 100)
          }
          .padding(.bottom, 40)
        }
      }
      .navigationTitle("Monitorings")
    }
  }

  // MARK: - 4. Component
  // 時間表示
  private var timeDisplay: some View {
    Text(formatElapsedTime(audioMonitor.elapsedTime))
      .font(.system(size: 48, weight: .thin))
      .monospacedDigit()
  }

  // 録音状態の表示
  private var monitoringStatus: some View {
    Text(audioMonitor.measurementStatus)
      .font(.headline)
      .foregroundColor(audioMonitor.isRecording ? .red : .secondary)
      .padding(.vertical, 6)
      .padding(.horizontal, 16)
      .background(Capsule().fill(Color.primary.opacity(0.1)))
  }

  // マイクの割り当て表示
  private var micAssignmentLabels: some View {
    List {
      Section(header: Text("Mic Assignment")) {
        HStack {
          // 1. 左側: マイク設定
          VStack(spacing: 6) {
            Text(selectedMicSource == "背面" ? "Back" : "Front")
            Divider()
              .overlay(Color.gray)
              .padding(.horizontal, 10)
            Text("Bottom")
          }
          .frame(maxWidth: .infinity)
          Spacer()

          Divider()
            .overlay(Color.gray)

          // 3. 右側: 端末の向き
          VStack(spacing: 6) {
            Image(systemName: selectedOrientation == "縦" ? "iphone" : "iphone.landscape")
              .font(.title2)
            Text(selectedOrientation == "縦" ? "Portrait" : "Landscape")
              .font(.caption)
          }
          .frame(maxWidth: .infinity)
        }
        // .padding(.vertical, 4)
      }
    }
    .listStyle(.insetGrouped)
    .frame(height: 125)
    .scrollDisabled(true)  // スクロールを無効化
    .scrollContentBackground(.hidden)
  }

  // ステレオメーター部分(縦画面)
  private var verticalStereoMeters: some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioMonitor.leftLevel, label: "L", font: .system(.caption))
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(
          level: audioMonitor.rightLevel, label: "R", font: .system(.caption))
        Text("\(Int(audioMonitor.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }

  // ステレオメーター部分(横画面)
  private var horizontalStereoMeters: some View {
    VStack(spacing: 20) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioMonitor.leftLevel, label: "L", font: .system(.caption))
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80, alignment: .leading)
      }
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioMonitor.rightLevel, label: "R", font: .system(.caption))
        Text("\(Int(audioMonitor.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80, alignment: .leading)
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    Button(action: {
      if audioMonitor.isRecording {
        audioMonitor.stopRecording()
      } else {
        // @AppStorage で読み込んだ設定値を渡して録音を開始
        audioMonitor.startRecording(
          orientation: selectedOrientation,
          micSource: selectedMicSource,
          prefix: "Monitoring"  //モニタリングファイルの接頭辞は "Monitoring" に固定
        )
      }
    }) {
      ZStack {
        Circle()
          .strokeBorder(Color.primary.opacity(0.2), lineWidth: 4)
          .frame(width: 70, height: 70)
        if audioMonitor.isRecording {
          RoundedRectangle(cornerRadius: 8)
            .fill(Color.red)
            .frame(width: 30, height: 30)
        } else {
          Circle()
            .fill(Color.red)
            .frame(width: 60, height: 60)
        }
      }
    }
  }

  private func formatElapsedTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    let ms = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
    return String(format: "%02d:%02d.%02d", minutes, seconds, ms)
  }
}
