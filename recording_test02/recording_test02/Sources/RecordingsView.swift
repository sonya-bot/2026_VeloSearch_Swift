import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct RecordingsView_Previews: PreviewProvider {
  static var previews: some View {
    RecordingsView()
  }
}

// MARK: - 1. AudioRecorder (録音ロジック)
@Observable
class AudioRecorder {
  var audioRecorder: AVAudioRecorder?

  var isRecording = false
  var elapsedTime: TimeInterval = 0.0

  // L/Rそれぞれの音量データ
  var leftDecibel: Float = 0.0
  var rightDecibel: Float = 0.0
  var leftLevel: CGFloat = 0.01
  var rightLevel: CGFloat = 0.01

  private var timer: Timer?
  private var levelTimer: Timer?
  private var startTime: Date?
  private var currentBaseFileName: String = ""

  func startRecording() {
    let audioSession = AVAudioSession.sharedInstance()
    let fileManager = FileManager.default
    let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    let dateString = formatter.string(from: Date())
    let nextNumber = getNextSequenceNumber(dateString: dateString, in: documentPath)
    self.currentBaseFileName = "Recording_\(dateString)_\(String(format: "%02d", nextNumber))"  // 録音ファイルの接頭辞は "Recording_"
    let audioFilename = documentPath.appendingPathComponent("\(self.currentBaseFileName).wav")

    do {
      // オーディオセッションの設定
      try audioSession.setCategory(.playAndRecord, mode: .default)

      // // ★向きをLandscapeRight（Lightningが右）に固定し、L/Rの割り当てを安定させる
      // try audioSession.setPreferredInputOrientation(.landscapeRight)

      // ★背面マイク（Back）を優先的に使用する設定
      if let availableInputs = audioSession.availableInputs {
        for input in availableInputs {
          if let dataSources = input.dataSources {
            for source in dataSources {
              if source.dataSourceName == "Back" {
                try audioSession.setInputDataSource(source)
                print("マイク設定: を選択")
              }
            }
          }
        }
      }
      try audioSession.setActive(true)

      // 録音フォーマット設定（ステレオ 44.1kHz 16bit PCM）
      let settings: [String: Any] = [
        AVFormatIDKey: Int(kAudioFormatLinearPCM),
        AVSampleRateKey: 44100.0,
        AVNumberOfChannelsKey: 2,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
      ]

      // 録音開始
      print("録音開始: \(audioFilename.lastPathComponent)")
      audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
      audioRecorder?.isMeteringEnabled = true
      audioRecorder?.record()

      isRecording = true
      elapsedTime = 0.0
      startTime = Date()

      // 時間計測タイマー
      timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
        guard let self = self, let startTime = self.startTime else { return }
        self.elapsedTime = Date().timeIntervalSince(startTime)
      }

      startMonitoring()

    } catch {
      print("エラー: \(error.localizedDescription)")
    }
  }

  private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
    let fileManager = FileManager.default
    do {
      let files = try fileManager.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
      let dailyFiles = files.filter {
        $0.lastPathComponent.hasPrefix("Recording_\(dateString)") && $0.pathExtension == "wav"
      }
      return dailyFiles.count + 1
    } catch {
      return 1
    }
  }

  func stopRecording() {
    audioRecorder?.stop()
    isRecording = false
    timer?.invalidate()
    levelTimer?.invalidate()
    elapsedTime = 0.0
    leftLevel = 0.01
    rightLevel = 0.01
  }

  private func startMonitoring() {
    levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
      guard let self = self, let recorder = self.audioRecorder else { return }
      recorder.updateMeters()

      // L(0) と R(1) のパワーを取得
      self.leftDecibel = recorder.averagePower(forChannel: 0)
      self.rightDecibel = recorder.averagePower(forChannel: 1)

      // 表示用に 0.0~1.0 に正規化
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
}

// MARK: - 2. RecordingsView (UI)
struct RecordingsView: View {
  @State private var audioRecorder = AudioRecorder()
  @Environment(\.verticalSizeClass) var verticalSizeClass

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
                Spacer()
                recordButton
                  .padding(.bottom, 100)
                Spacer()
              }
              .frame(width: (geometry.size.width - 30) / 3)

              VStack(spacing: 10) {
                micAssignmentLabels
                  .padding(.top, -20)
                  .padding(.bottom, 20)
                horizontalStereoMeters
                Spacer()
              }
              .padding(.bottom, 120)
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
            micAssignmentLabels
            // Spacer()
            stereoMeters
            // Spacer()
            recordButton
              .padding(.bottom, 100)
          }
          .padding(.bottom, 40)
        }
      }
      .navigationTitle("Recordings")
    }
  }

  // MARK: - 4. Component
  // 時間表示
  private var timeDisplay: some View {
    Text(formatElapsedTime(audioRecorder.elapsedTime))
      .font(.system(size: 48, weight: .thin))
      .monospacedDigit()
  }

  // マイクの割り当て表示
  private var micAssignmentLabels: some View {
    List {
      Section(header: Text("Mic Assignment")) {
        // ここには設定画面で指定したマイクを表示できるようにする、現在はデコイで実装
        HStack {
          Spacer()
          Text("Back")
          Spacer()

          Divider()
            .overlay(Color.gray)

          Spacer()
          Text("Bottom")
          Spacer()
        }
      }
    }
    .listStyle(.insetGrouped)
    .frame(height: 90)
    .scrollDisabled(true)  //
    .scrollContentBackground(.hidden)
  }

  // ステレオメーター部分
  private var stereoMeters: some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioRecorder.leftLevel, label: "L", font: .system(.caption))
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(
          level: audioRecorder.rightLevel, label: "R", font: .system(.caption))
        Text("\(Int(audioRecorder.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }

  // 横画面用のステレオメーター部分
  private var horizontalStereoMeters: some View {
    VStack(spacing: 20) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioRecorder.leftLevel, label: "L", font: .system(.caption))
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80, alignment: .leading)
      }
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioRecorder.rightLevel, label: "R", font: .system(.caption))
        Text("\(Int(audioRecorder.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80, alignment: .leading)
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    Button(action: {
      if audioRecorder.isRecording {
        audioRecorder.stopRecording()
      } else {
        audioRecorder.startRecording()
      }
    }) {
      ZStack {
        Circle()
          .strokeBorder(Color.primary.opacity(0.2), lineWidth: 4)
          .frame(width: 70, height: 70)
        if audioRecorder.isRecording {
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

// 垂直メーターのコンポーネント
struct VerticaldBMeter: View {
  var level: CGFloat
  var label: String
  var font: Font = .headline

  var body: some View {
    VStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .bottom) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.black.opacity(0.1))
          .frame(width: 80, height: 200)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.red, .white]), startPoint: .top,
              endPoint: .bottom)
          )
          .frame(width: 80, height: 200 * level)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}

// 水平メーターのコンポーネント
struct HorizontaldBMeter: View {
  var level: CGFloat
  var label: String
  var font: Font = .headline

  var body: some View {
    HStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .leading) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.black.opacity(0.1))
          .frame(width: 300, height: 40)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.white, .red]), startPoint: .leading,
              endPoint: .trailing)
          )
          .frame(width: 300 * level, height: 40)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}
