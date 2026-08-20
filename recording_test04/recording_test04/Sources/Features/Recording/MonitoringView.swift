import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct MonitoringView_Previews: PreviewProvider {
  static var previews: some View {
    MonitoringView(recordingFileStore: RecordingFileStore.shared, userDefaults: .standard)
  }
}

// MARK: - 1. AudioMonitoringController (録音ロジック)
// Monitoring画面もRecordings画面と同じ録音クラスを使う。
typealias AudioMonitoringController = AudioRecordingController

// MARK: - 2. MonitoringView (UI)
struct MonitoringView: View {
  private let recordingFileStore: RecordingFileStoring
  @State private var audioMonitor: AudioMonitoringController
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @AppStorage("deviceOrientation") private var selectedOrientation: String = "横"
  @AppStorage("micSource") private var selectedMicSource: String = "背面"
  @AppStorage(RecordingFileStore.selectedSceneKey) private var selectedScene = RecordingFileStore
    .defaultSceneName
  @State private var availableScenes: [String] = []

  init(recordingFileStore: RecordingFileStoring, userDefaults: UserDefaults) {
    self.recordingFileStore = recordingFileStore
    _audioMonitor = State(
      initialValue: AudioMonitoringController(
        recordingFileStore: recordingFileStore,
        userDefaults: userDefaults
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
          GeometryReader { geometry in
            let bottomPadding = geometry.safeAreaInsets.bottom + 16
            let meterWidth = min(220, max(160, geometry.size.width * 0.28))

            HStack(spacing: 30) {
              VStack(spacing: 10) {
                timeDisplay
                monitoringStatus
                Spacer()
                recordButton
                  .padding(.bottom, bottomPadding)
                Spacer()
              }
              .frame(width: (geometry.size.width - 30) / 3)

              VStack(spacing: 10) {
                micAssignmentLabels
                  .padding(.top, -12)
                sceneDestinationPicker
                horizontalStereoMeters(width: meterWidth, height: 24)
                // Spacer()
              }
              .padding(.bottom, bottomPadding)
              .frame(width: (geometry.size.width - 30) * 2 / 3)
            }
            .frame(maxHeight: .infinity)
          }
          .padding()
        } else {
          // 【縦画面レイアウト】
          GeometryReader { geometry in
            // 固定余白を削り、余った縦方向の領域をステレオメーターの高さに回す。
            let meterHeight = min(220, max(180, geometry.size.height * 0.25))

            VStack(spacing: 10) {
              timeDisplay
              monitoringStatus
              micAssignmentLabels
              sceneDestinationPicker
              verticalStereoMeters(height: meterHeight)
              Spacer(minLength: 4)
              recordButton
            }
            .padding(.top, 4)
            .padding(.horizontal)
            .padding(.bottom, 72)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
          }
        }
      }
      .navigationTitle("Monitorings")
      .navigationBarTitleDisplayMode(.inline)
      .onAppear { refreshScenes() }
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

  // 保存先は高さを抑えた1行表示とし、既存レイアウトをスクロール前提にしない。
  private var sceneDestinationPicker: some View {
    Menu {
      Picker("保存先", selection: $selectedScene) {
        Text(RecordingFileStore.defaultSceneName).tag(RecordingFileStore.defaultSceneName)
        ForEach(availableScenes, id: \.self) { scene in
          Text(scene).tag(scene)
        }
      }
    } label: {
      HStack {
        Text("保存先")
          .foregroundStyle(.black)
        Spacer()
        Text(selectedScene)
          .foregroundStyle(.black)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.caption)
          .foregroundStyle(.black.opacity(0.55))
      }
      .padding(.horizontal, 16)
      .frame(height: 44)
      .background(Color(UIColor.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .padding(.horizontal)
  }

  private func refreshScenes() {
    do {
      try recordingFileStore.prepareStorage()
      availableScenes = recordingFileStore.sceneDirectories().map(\.lastPathComponent)
      if selectedScene != RecordingFileStore.defaultSceneName
        && !availableScenes.contains(selectedScene)
      {
        selectedScene = RecordingFileStore.defaultSceneName
      }
    } catch {
      selectedScene = RecordingFileStore.defaultSceneName
      availableScenes = []
    }
  }

  // ステレオメーター部分(縦画面)
  private func verticalStereoMeters(height: CGFloat) -> some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(
          level: audioMonitor.leftLevel, label: "L", font: .system(.caption), height: height)
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(
          level: audioMonitor.rightLevel, label: "R", font: .system(.caption), height: height)
        Text("\(Int(audioMonitor.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }

  // ステレオメーター部分(横画面)
  private func horizontalStereoMeters(width: CGFloat, height: CGFloat) -> some View {
    VStack(spacing: 12) {
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioMonitor.leftLevel,
          label: "L",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioMonitor.leftDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
      HStack(spacing: 15) {
        HorizontaldBMeter(
          level: audioMonitor.rightLevel,
          label: "R",
          width: width,
          height: height,
          font: .system(.caption)
        )
        Text("\(Int(audioMonitor.rightDecibel)) dB")
          .font(.system(.subheadline))
          .monospacedDigit()
          .frame(width: 64, alignment: .leading)
      }
    }
  }

  // 録音ボタン
  private var recordButton: some View {
    Button {
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
    } label: {
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
