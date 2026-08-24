import Foundation
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

// MARK: - 3. PlayerView (メイン画面)
struct PlayerView: View {
  private let recordingFileStore: RecordingFileStoring
  private let recordingDetailsController: PlayerRecordingDetailsController

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
  @State private var companionCSVURL: URL?
  @State private var currentSpeed: String = "--"

  init(
    audioURL: URL,
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults
  ) {
    self.recordingFileStore = recordingFileStore
    self.recordingDetailsController = PlayerRecordingDetailsController(
      recordingFileStore: recordingFileStore,
      userDefaults: userDefaults
    )
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
            playerTimeDisplay
            playerPlaybackButton
            playerSeekSlider
          }
          .frame(maxWidth: 240)

          // 中央:ステレオメーター
          VStack(spacing: 10) {
            horizontalStereoMeters
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
              csvURL: companionCSVURL,
              showsCSVSection: false,
              recordingFileStore: recordingFileStore,
              onSave: saveChanges
            )
            csvAccessRow
          }
          .padding(.bottom, 8)
          .frame(maxWidth: 310)
        }
        .padding(.top, 10)
      } else {
        // 縦画面レイアウト
        VStack(spacing: 10) {
          Spacer().frame(height: 20)
          playerTimeDisplay
          Spacer().frame(height: 20)
          playerPlaybackButton
          playerSeekSlider
          verticalStereoMeters
          Spacer()
          csvAccessRow
            .padding(.horizontal, 20)
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
          csvURL: companionCSVURL,
          showsCSVSection: true,
          recordingFileStore: recordingFileStore,
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
        ShareLink(item: currentURL) {
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
      loadSavedData()
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
  private func loadSavedData() {
    let details = recordingDetailsController.details(for: currentURL)
    fileNote = details.note
    fileExperimenter = details.experimenter
    fileWeather = details.weather
    fileTemperature = details.temperature
    fileHumidity = details.humidity
    fileScene = details.scene
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

    let oldNameWithoutExtension = currentURL.deletingPathExtension().lastPathComponent
    if editFileName != oldNameWithoutExtension && !editFileName.isEmpty {
      audioPlayer.stopPlayback()
    }
    let details = RecordingDetails(
      note: fileNote,
      experimenter: fileExperimenter,
      weather: fileWeather,
      temperature: fileTemperature,
      humidity: fileHumidity,
      scene: fileScene
    )
    let previousURL = currentURL
    currentURL = recordingDetailsController.save(
      details: details,
      for: currentURL,
      renamedTo: editFileName
    )
    if currentURL != previousURL {
      loadCSVData()
    }
  }

  private func loadCSVData() {
    companionCSVURL = recordingDetailsController.companionCSV(for: currentURL)
    csvRecords = recordingDetailsController.speedRecords(for: currentURL)
    if csvRecords.isEmpty {
      currentSpeed = ""
    } else {
      updateSpeed(for: 0.0)
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
  private var playerTimeDisplay: some View {
    PlayerTimeDisplay(
      currentTime: audioPlayer.currentTime,
      duration: audioPlayer.duration,
      onTimeChanged: updateSpeed
    )
  }

  // 再生/一時停止ボタン
  private var playerPlaybackButton: some View {
    PlayerPlaybackButton(isPlaying: audioPlayer.isPlaying) {
      if audioPlayer.isPlaying {
        audioPlayer.pausePlayback()
      } else {
        audioPlayer.startPlayback()
      }
    }
  }

  // シークバー
  private var playerSeekSlider: some View {
    PlayerSeekSlider(
      currentTime: audioPlayer.currentTime,
      duration: audioPlayer.duration,
      horizontalPadding: verticalSizeClass == .compact ? 10 : 30,
      onSeek: audioPlayer.seek
    )
  }

  // ステレオメーター部分(縦画面用)
  private var verticalStereoMeters: some View {
    PlayerStereoMeters(
      leftLevel: audioPlayer.leftLevel,
      rightLevel: audioPlayer.rightLevel,
      leftDecibel: audioPlayer.leftDecibel,
      rightDecibel: audioPlayer.rightDecibel,
      spacing: 50,
      meterWidth: nil
    )
  }
  // ステレオメーター部分(横画面用)
  private var horizontalStereoMeters: some View {
    PlayerStereoMeters(
      leftLevel: audioPlayer.leftLevel,
      rightLevel: audioPlayer.rightLevel,
      leftDecibel: audioPlayer.leftDecibel,
      rightDecibel: audioPlayer.rightDecibel,
      spacing: 10,
      meterWidth: 40
    )
  }

  private var csvAccessRow: some View {
    CompanionCSVAccessLink(
      csvURL: companionCSVURL,
      recordingFileStore: recordingFileStore,
      style: .card
    )
  }
}
