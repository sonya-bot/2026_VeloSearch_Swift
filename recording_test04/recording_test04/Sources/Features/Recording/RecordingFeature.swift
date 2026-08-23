import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct RecordingView_Previews: PreviewProvider {
  static var previews: some View {
    RecordingView(
      recordingFileStore: RecordingFileStore.shared,
      userDefaults: .standard,
      audioIOController: AudioIOController()
    )
  }
}

// MARK: - 2. RecordingView (UI)
struct RecordingView: View {
  private let recordingFileStore: RecordingFileStoring
  @ObservedObject private var audioIOController: AudioIOController
  @State private var audioRecorder: AudioRecordingController
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName

  init(
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    audioIOController: AudioIOController
  ) {
    self.recordingFileStore = recordingFileStore
    self.audioIOController = audioIOController
    _audioRecorder = State(
      initialValue: AudioRecordingController(
        recordingFileStore: recordingFileStore,
        userDefaults: userDefaults,
        audioIOController: audioIOController
      )
    )
  }

  var body: some View {
    NavigationStack {
      ZStack {
        // 背景色
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()

        if verticalSizeClass == .compact {
          // 【横画面レイアウト】
          MeasurementLandscapeLayout { _ in
            VStack(spacing: 10) {
              timeDisplay
              recordingStatus
              Spacer(minLength: 0)
              recordButton
              Spacer(minLength: 0)
            }
          } trailingContent: { availableSize in
            let meterWidth = min(340, max(150, availableSize.width * 0.36))
            VStack(spacing: 8) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              MeasurementDestinationPicker(
                recordingFileStore: recordingFileStore,
                selection: $selectedScene,
                isDisabled: audioRecorder.isRecording
              )
              horizontalStereoMeters(width: meterWidth, height: 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
          }
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // MonitoringViewと同じ配置にし、
            // 余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(210, max(120, geometry.size.height * 0.24))

            VStack(spacing: 10) {
              AudioRouteStatusButton(audioIOController: audioIOController)
              MeasurementDestinationPicker(
                recordingFileStore: recordingFileStore,
                selection: $selectedScene,
                isDisabled: audioRecorder.isRecording
              )
              VStack(spacing: 8) {
                timeDisplay
                recordingStatus
                verticalStereoMeters(height: meterHeight)
              }
              .frame(maxWidth: .infinity, maxHeight: .infinity)
              .background(Color(uiColor: .secondarySystemGroupedBackground))
              .clipShape(RoundedRectangle(cornerRadius: 16))
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Recordings")
      .navigationBarTitleDisplayMode(.inline)
    }
  }

  // MARK: - 4. Component
  // 時間表示
  private var timeDisplay: some View {
    Text(formatElapsedTime(audioRecorder.elapsedTime))
      .font(.system(size: 48, weight: .thin))
      .monospacedDigit()
  }

  // 録音状態の表示
  private var recordingStatus: some View {
    Text(audioRecorder.isRecording ? "録音中" : "待機中")
      .font(.headline)
      .foregroundColor(audioRecorder.isRecording ? .red : .secondary)
      .padding(.vertical, 6)
      .padding(.horizontal, 16)
      .background(Capsule().fill(Color.primary.opacity(0.1)))
  }

  private var audioConfigurationIssue: String? {
    audioIOController.configurationIssue()
  }

  // ステレオメーター部分(縦画面)
  private func verticalStereoMeters(height: CGFloat) -> some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioRecorder.leftLevel, label: "L", font: .system(.caption), height: height)
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      if audioRecorder.activeInputChannelCount >= 2 {
        VStack {
          VerticaldBMeter(
            level: audioRecorder.rightLevel, label: "R", font: .system(.caption), height: height)
          Text("\(Int(audioRecorder.rightDecibel)) dB")
            .font(.system(.title3))
            .monospacedDigit()
            .frame(width: 80)
        }
      }
    }
  }

  // ステレオメーター部分(横画面)
  private func horizontalStereoMeters(width: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioRecorder.leftLevel,
          label: "L",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioRecorder.leftDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
      if audioRecorder.activeInputChannelCount >= 2 {
        HStack(spacing: 15) {
          HorizontaldBMeter(
            level: audioRecorder.rightLevel,
            label: "R",
            width: width,
            height: height,
            font: .system(.caption)
          )
          Text("\(Int(audioRecorder.rightDecibel)) dB")
            .font(.system(.subheadline))
            .monospacedDigit()
            .frame(width: 64, alignment: .leading)
        }
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    MeasurementControlButton(
      idleTitle: "Record",
      activeTitle: "Stop",
      isActive: audioRecorder.isRecording,
      tint: .red,
      isDisabled: !audioRecorder.isRecording && audioConfigurationIssue != nil
    ) {
      if audioRecorder.isRecording {
        audioRecorder.stopRecording()
      } else {
        audioRecorder.startRecording(
          orientation: selectedOrientation,
          micSource: selectedMicSource,
          prefix: "Recording"
        )
      }
    }
    .overlay(alignment: .top) {
      if !audioRecorder.isRecording, let audioConfigurationIssue {
        Text(audioConfigurationIssue)
          .font(.caption2)
          .foregroundStyle(.red)
          .fixedSize(horizontal: false, vertical: true)
          .frame(width: 220)
          .offset(y: -32)
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
  var width: CGFloat = 56  // 主要画面で圧迫しない幅に抑える
  var height: CGFloat = 150  // 画面構成に応じて高さだけ調整可能にする

  var body: some View {
    VStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .bottom) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(0.1))
          .frame(width: width, height: height)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.red, .white]), startPoint: .top,
              endPoint: .bottom)
          )
          .frame(width: width, height: height * level)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}

// 水平メーターのコンポーネント
struct HorizontaldBMeter: View {
  var level: CGFloat
  var label: String
  var width: CGFloat = 240  // 横画面でも操作ボタンや設定欄を圧迫しない幅に抑える
  var height: CGFloat = 32
  var font: Font = .headline

  var body: some View {
    HStack(spacing: 8) {
      Text(label).font(font).foregroundColor(.secondary)
      ZStack(alignment: .leading) {
        // 背景の溝
        RoundedRectangle(cornerRadius: 6)
          .fill(Color.primary.opacity(0.1))
          .frame(width: width, height: height)

        // 音量レベル（グラデーション）
        RoundedRectangle(cornerRadius: 6)
          .fill(
            LinearGradient(
              gradient: Gradient(colors: [.white, .red]), startPoint: .leading,
              endPoint: .trailing)
          )
          .frame(width: width * level, height: height)
          .animation(.spring(response: 0.15, dampingFraction: 0.8), value: level)
      }
    }
  }
}
