import AVFoundation
import Foundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct PlayerView_Previews: PreviewProvider {
  static var previews: some View {
    PlayerView(
      audioURL: URL(fileURLWithPath: "/tmp/preview.wav"),
      recordingFileStore: RecordingFileStore.shared,
      userDefaults: .standard
    )
  }
}

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
    do {
      try playbackSession.setCategory(.playback, mode: .default)
      try playbackSession.setActive(true)

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

// MARK: - 2. CSVRecord
struct CSVRecord {
  let time: Double
  let speed: String
}

// MARK: - 3. PlayerView (メイン画面)
struct PlayerView: View {
  let initialURL: URL
  private let userDefaults: UserDefaults

  @State private var currentURL: URL
  @State private var audioPlayer: AudioPlaybackController
  @Environment(\.dismiss) private var dismiss
  @Environment(\.verticalSizeClass) var verticalSizeClass

  @State private var showingDeleteAlert = false

  // 保存済みのデータ
  @State private var fileNote: String = ""
  @State private var fileExperimenter: String = ""
  @State private var fileWeather: String = ""
  @State private var fileTemperature: String = ""
  @State private var fileHumidity: String = ""
  @State private var fileScene: String = ""

  @State private var sheetDetent: PresentationDetent = .height(180)
  // 編集用のデータ
  @State private var isEditing = false
  @State private var editFileName = ""
  @State private var editNote = ""
  @State private var editExperimenter = ""
  @State private var editWeather = ""
  @State private var editTemperature = ""
  @State private var editHumidity = ""
  @State private var editScene = ""

  @State private var csvRecords: [CSVRecord] = []
  @State private var currentSpeed: String = "--"

  init(
    audioURL: URL,
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults
  ) {
    self.initialURL = audioURL
    self.userDefaults = userDefaults
    self._currentURL = State(initialValue: audioURL)
    self._audioPlayer = State(
      initialValue: AudioPlaybackController(
        recordingFileStore: recordingFileStore,
        userDefaults: userDefaults
      )
    )
  }

  var body: some View {

    ZStack {
      // 背景色
      Color(UIColor.systemGroupedBackground).ignoresSafeArea()

      // 横画面レイアウト
      if verticalSizeClass == .compact {
        HStack(spacing: 0) {
          // 左:プレイヤーセクション
          VStack(spacing: 10) {
            timeDisplay
            playPauseButton
            slider
          }
          .frame(maxWidth: 240)

          // 中央:ステレオメーター
          VStack(spacing: 10) {
            horizontalstereoMeters
          }
          .padding(.horizontal, 10)

          // 右:編集セクション
          VStack(spacing: 10) {
            EditSheetView(
              isPresented: $isEditing,
              sheetDetent: Binding(get: { .large }, set: { _ in }),
              editFileName: $editFileName,
              editExperimenter: $editExperimenter,
              editScene: $editScene,
              editWeather: $editWeather,
              editTemperature: $editTemperature,
              editHumidity: $editHumidity,
              editNote: $editNote,
              csvURL: currentURL.deletingPathExtension().appendingPathExtension("csv"),
              onSave: saveChanges
            )
          }
          .frame(maxWidth: 310)
        }
        .padding(.top, 10)
      } else {
        // 縦画面レイアウト
        VStack(spacing: 10) {
          Spacer().frame(height: 20)
          timeDisplay
          Spacer().frame(height: 20)
          playPauseButton
          slider
          verticalstereoMeters
          Spacer()
        }
        .padding(.bottom, 20)
      }
    }
    // MARK: - SwiftUIネイティブのボトムシート実装
    // 縦画面の時のみシートとして表示
    .sheet(
      isPresented: Binding(
        get: { isEditing && verticalSizeClass != .compact },
        set: { isEditing = $0 }
      )
    ) {
      NavigationStack {
        EditSheetView(
          isPresented: $isEditing,
          sheetDetent: $sheetDetent,
          editFileName: $editFileName,
          editExperimenter: $editExperimenter,
          editScene: $editScene,
          editWeather: $editWeather,
          editTemperature: $editTemperature,
          editHumidity: $editHumidity,
          editNote: $editNote,
          csvURL: currentURL.deletingPathExtension().appendingPathExtension("csv"),
          onSave: saveChanges
        )
      }
      // シートの高さを指定（最初はファイル名のみが見える低さ、中、全画面）
      .presentationDetents([.height(180), .medium, .large], selection: $sheetDetent)
      // 上部のドラッグインジケーター（つまみ）を表示
      .presentationDragIndicator(.visible)
      // スワイプでシートが閉じないようにする
      .interactiveDismissDisabled()
    }
    .navigationTitle(currentURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
        if verticalSizeClass != .compact {
          Button(action: {
            startEditing()
            sheetDetent = .medium
            isEditing = true
          }) {
            Image(systemName: "pencil")
          }
        }
        Button(action: { shareAudio(url: currentURL) }) {
          Image(systemName: "square.and.arrow.up")
        }
        Button(action: { showingDeleteAlert = true }) {
          Image(systemName: "trash")
        }
      }
    }
    .alert("Delete Recording?", isPresented: $showingDeleteAlert) {
      Button("Delete", role: .destructive) {
        audioPlayer.deleteAudio(audio: currentURL)
        dismiss()
      }
      Button("Cancel", role: .cancel) {}
    } message: {
      Text(
        "Are you sure you want to delete '\(currentURL.lastPathComponent)'? This action cannot be undone."
      )
    }
    .onAppear {
      audioPlayer.prepareAudio(audio: currentURL)
      loadSavedData(for: currentURL.lastPathComponent)
      startEditing()
      loadCSVData()
    }
    .onDisappear {
      audioPlayer.stopPlayback()
    }
    // プレイヤー画面ではタブバーを非表示にして、ボトムシートとの被りを防ぐ
    .toolbar(.hidden, for: .tabBar)
  }

  // MARK: - 4.Components (編集用の部品)
  private func loadSavedData(for fileName: String) {
    fileNote =
      userDefaults.string(forKey: "\(fileName)_note") ?? userDefaults.string(
        forKey: fileName) ?? ""
    fileExperimenter = userDefaults.string(forKey: "\(fileName)_experimenter") ?? ""
    fileWeather = userDefaults.string(forKey: "\(fileName)_weather") ?? ""
    fileTemperature = userDefaults.string(forKey: "\(fileName)_temperature") ?? ""
    fileHumidity = userDefaults.string(forKey: "\(fileName)_humidity") ?? ""
    fileScene = userDefaults.string(forKey: "\(fileName)_scene") ?? ""
  }

  private func startEditing() {
    editFileName = currentURL.deletingPathExtension().lastPathComponent
    editNote = fileNote
    editExperimenter = fileExperimenter
    editWeather = fileWeather
    editTemperature = fileTemperature
    editHumidity = fileHumidity
    editScene = fileScene
  }

  private func saveChanges() {
    fileNote = editNote
    fileExperimenter = editExperimenter
    fileWeather = editWeather
    fileTemperature = editTemperature
    fileHumidity = editHumidity
    fileScene = editScene

    let oldFileName = currentURL.lastPathComponent
    var newURL = currentURL

    let oldNameWithoutExtension = currentURL.deletingPathExtension().lastPathComponent
    if editFileName != oldNameWithoutExtension && !editFileName.isEmpty {
      audioPlayer.stopPlayback()

      let fileManager = FileManager.default
      let folderURL = currentURL.deletingLastPathComponent()
      let extensionString = currentURL.pathExtension
      let destinationURL = folderURL.appendingPathComponent("\(editFileName).\(extensionString)")

      let oldCSVURL = currentURL.deletingPathExtension().appendingPathExtension("csv")
      let newCSVURL = folderURL.appendingPathComponent("\(editFileName).csv")
      let oldDevCSVURL = folderURL.appendingPathComponent("Dev_\(oldNameWithoutExtension).csv")
      let newDevCSVURL = folderURL.appendingPathComponent("Dev_\(editFileName).csv")

      do {
        try fileManager.moveItem(at: currentURL, to: destinationURL)
        if fileManager.fileExists(atPath: oldCSVURL.path) {
          try fileManager.moveItem(at: oldCSVURL, to: newCSVURL)
        }
        if fileManager.fileExists(atPath: oldDevCSVURL.path) {
          try fileManager.moveItem(at: oldDevCSVURL, to: newDevCSVURL)
        }
        newURL = destinationURL
        currentURL = destinationURL
        loadCSVData()
      } catch {
        AppLogger.storage.error("録音名の変更に失敗しました: \(error.localizedDescription)")
      }
    }

    let newFileName = newURL.lastPathComponent

    if oldFileName != newFileName {
      userDefaults.removeObject(forKey: "\(oldFileName)_note")
      userDefaults.removeObject(forKey: oldFileName)
      userDefaults.removeObject(forKey: "\(oldFileName)_experimenter")
      userDefaults.removeObject(forKey: "\(oldFileName)_weather")
      userDefaults.removeObject(forKey: "\(oldFileName)_temperature")
      userDefaults.removeObject(forKey: "\(oldFileName)_humidity")
      userDefaults.removeObject(forKey: "\(oldFileName)_scene")
    }

    userDefaults.set(fileNote, forKey: "\(newFileName)_note")
    userDefaults.set(fileExperimenter, forKey: "\(newFileName)_experimenter")
    userDefaults.set(fileWeather, forKey: "\(newFileName)_weather")
    userDefaults.set(fileTemperature, forKey: "\(newFileName)_temperature")
    userDefaults.set(fileHumidity, forKey: "\(newFileName)_humidity")
    userDefaults.set(fileScene, forKey: "\(newFileName)_scene")
  }

  private func shareAudio(url: URL) {
    let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
      let window = windowScene.windows.first(where: { $0.isKeyWindow }),
      let rootVC = window.rootViewController
    {

      var topVC = rootVC
      while let presentedVC = topVC.presentedViewController {
        topVC = presentedVC
      }

      if let popover = activityVC.popoverPresentationController {
        popover.sourceView = topVC.view
        popover.sourceRect = CGRect(
          x: topVC.view.bounds.midX, y: topVC.view.bounds.midY, width: 0, height: 0)
        popover.permittedArrowDirections = []
      }

      topVC.present(activityVC, animated: true)
    }
  }

  private func formatTime(_ time: TimeInterval) -> String {
    let minutes = Int(time) / 60
    let seconds = Int(time) % 60
    return String(format: "%02d:%02d", minutes, seconds)
  }

  private func loadCSVData() {
    let csvURL = currentURL.deletingPathExtension().appendingPathExtension("csv")
    do {
      let csvString = try String(contentsOf: csvURL, encoding: .utf8)
      let lines = csvString.components(separatedBy: .newlines)
      var records: [CSVRecord] = []
      for line in lines.dropFirst() {
        let columns = line.components(separatedBy: ",")
        if columns.count >= 2, let time = Double(columns[0]) {
          records.append(CSVRecord(time: time, speed: columns[1]))
        }
      }
      self.csvRecords = records
      updateSpeed(for: 0.0)
    } catch {
      AppLogger.storage.notice("対応する速度CSVを読み込めませんでした")
      self.currentSpeed = ""
    }
  }

  private func updateSpeed(for time: TimeInterval) {
    guard !csvRecords.isEmpty else { return }
    if let closestRecord = csvRecords.min(by: { abs($0.time - time) < abs($1.time - time) }) {
      self.currentSpeed = closestRecord.speed
    }
  }

  // MARK: - Components (UIパーツ)
  // 時間表示
  private var timeDisplay: some View {
    Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
      .font(.system(size: 40, weight: .thin))
      .monospacedDigit()
      .onChange(of: audioPlayer.currentTime) { oldTime, newTime in
        updateSpeed(for: newTime)
      }
  }

  // 再生/一時停止ボタン
  private var playPauseButton: some View {
    Button {
      if audioPlayer.isPlaying {
        audioPlayer.pausePlayback()
      } else {
        audioPlayer.startPlayback()
      }
    } label: {
      ZStack {
        Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 64))
          .foregroundColor(.red)
        Circle()
          .strokeBorder(Color.primary.opacity(0.2), lineWidth: 4)
          .frame(width: 74, height: 74)
      }

    }
  }

  // シークバー
  private var slider: some View {
    Slider(
      value: Binding(
        get: { audioPlayer.currentTime },
        set: { newValue in
          audioPlayer.seek(to: newValue)
        }
      ), in: 0...(audioPlayer.duration > 0 ? audioPlayer.duration : 1.0)
    )
    .accentColor(.red)
    .padding(.horizontal, verticalSizeClass == .compact ? 10 : 30)
  }

  // ステレオメーター部分(縦画面用)
  private var verticalstereoMeters: some View {
    HStack(spacing: 50) {
      VStack {
        VerticaldBMeter(level: audioPlayer.leftLevel, label: "L", font: .system(.caption))
        Text("\(Int(audioPlayer.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(level: audioPlayer.rightLevel, label: "R", font: .system(.caption))
        Text("\(Int(audioPlayer.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }
  // ステレオメーター部分(横画面用)
  private var horizontalstereoMeters: some View {
    HStack(spacing: 10) {
      VStack {
        VerticaldBMeter(
          level: audioPlayer.leftLevel, label: "L", font: .system(.caption), width: 40)
        Text("\(Int(audioPlayer.leftDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
      VStack {
        VerticaldBMeter(
          level: audioPlayer.rightLevel, label: "R", font: .system(.caption), width: 40)
        Text("\(Int(audioPlayer.rightDecibel)) dB")
          .font(.system(.title3))
          .monospacedDigit()
          .frame(width: 80)
      }
    }
  }
}

// MARK: ボトムシート用コンポーネント
struct EditSheetView: View {
  @Binding var isPresented: Bool
  @Binding var sheetDetent: PresentationDetent
  @Binding var editFileName: String
  @Binding var editExperimenter: String
  @Binding var editScene: String
  @Binding var editWeather: String
  @Binding var editTemperature: String
  @Binding var editHumidity: String
  @Binding var editNote: String

  var csvURL: URL
  var onSave: () -> Void

  // シートが引き上げられているか（.height(180) 以外か）を判定
  var isEditingMode: Bool {
    sheetDetent != .height(180)
  }

  var body: some View {
    VStack(spacing: 0) {
      // 引き上げられている時（編集モード）だけヘッダーを表示
      if isEditingMode {
        HStack {
          Spacer()

          Button("保存") {
            onSave()
            isPresented = false
            sheetDetent = .height(180)  // 保存後に元の高さに閉じる
          }
          .bold()
          .foregroundColor(.blue)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
      }

      // リスト形式の入力フォーム
      List {
        Section {
          TextField("ファイル名 (例: DRTF_Angle045_Take1)", text: $editFileName)
            .font(.title3)
            .bold()
            .padding(.vertical, 4)
            .disabled(!isEditingMode)  // 引き上げていない時は編集不可
        } header: {
          Text("File Name")
        }

        // 引き上げられている時だけ他の項目も表示
        if isEditingMode {
          Section(header: Text("Details")) {
            HStack {
              Text("Experimenter")
              Spacer()
              TextField("Name", text: $editExperimenter).multilineTextAlignment(.trailing)
            }
            HStack {
              Text("Scene")
              Spacer()
              TextField("Pattern", text: $editScene).multilineTextAlignment(.trailing)
            }
          }

          Section(header: Text("Environment")) {
            HStack {
              Text("Weather")
              Spacer()
              TextField("Weather", text: $editWeather).multilineTextAlignment(.trailing)
            }
            HStack {
              Text("Temperature")
              Spacer()
              TextField("Temp", text: $editTemperature)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
              Text("°C").foregroundColor(.secondary)
            }
            HStack {
              Text("Humidity")
              Spacer()
              TextField("Humid", text: $editHumidity)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
              Text("%").foregroundColor(.secondary)
            }
          }

          Section(header: Text("Note")) {
            TextEditor(text: $editNote)
              .frame(minHeight: 80)
          }

          // CSVデータの共有と遷移
          Section(
            header: HStack {
              Text("Speed Data (CSV)")
              Spacer()
              ShareLink(item: csvURL) {
                Label("Share", systemImage: "square.and.arrow.up")
                  .textCase(.none)
                  .font(.body)
                  .foregroundColor(.blue)
              }
            }
          ) {
            NavigationLink(destination: CSVPreviewView(csvURL: csvURL)) {
              Label(csvURL.lastPathComponent, systemImage: "doc.text.fill")
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
  }
}
