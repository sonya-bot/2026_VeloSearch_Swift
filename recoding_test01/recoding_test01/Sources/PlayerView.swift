import AVFoundation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct PlayerView_Previews: PreviewProvider {
  static var previews: some View {
    PlayerView(audioURL: URL(string: "https://example.com/audio.m4a")!)
  }
}

// MARK: - 1. AudioPlayer(再生/停止/削除)
class AudioPlayer: ObservableObject {
  var audioPlayer: AVAudioPlayer?

  @Published var isPlaying = false
  @Published var currentTime: TimeInterval = 0.0
  @Published var duration: TimeInterval = 0.0

  private var timer: Timer?

  func startPlayback(audio: URL) {
    let playbackSession = AVAudioSession.sharedInstance()
    do {
      try playbackSession.setCategory(.playback, mode: .default)
      try playbackSession.setActive(true)

      audioPlayer = try AVAudioPlayer(contentsOf: audio)
      audioPlayer?.prepareToPlay()
      audioPlayer?.play()

      isPlaying = true
      duration = audioPlayer?.duration ?? 0.0

      timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
        guard let self = self, let player = self.audioPlayer else { return }
        if player.isPlaying {
          self.currentTime = player.currentTime
        } else {
          self.stopPlayback()
        }
      }
    } catch {
      print("再生に失敗しました: \(error.localizedDescription)")
    }
  }

  func pausePlayback() {
    audioPlayer?.pause()
    isPlaying = false
  }

  func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
    currentTime = 0.0
    timer?.invalidate()
    timer = nil
  }

  func deleteAudio(audio: URL) {
    self.stopPlayback()
    let fileManager = FileManager.default
    do {
      try fileManager.removeItem(at: audio)
      UserDefaults.standard.removeObject(forKey: audio.lastPathComponent)
    } catch {
      print("ファイルの削除に失敗しました: \(error.localizedDescription)")
    }
  }
}

// MARK: - 2. AudioDetailView(画面UI)
struct PlayerView: View {
    let initialURL: URL
    @State private var currentURL: URL

    @StateObject private var audioPlayer = AudioPlayer()
    @Environment(\.presentationMode) var presentationMode

    @State private var showingDeleteAlert = false
    
    // ★ 追加: 通常モードで表示するための保存用変数
    @State private var fileNote: String = ""
    @State private var fileExperimenter: String = ""
    @State private var fileWeather: String = "天気: "
    @State private var fileTemperature: String = ""
    @State private var fileHumidity: String = ""
    @State private var fileScene: String = ""

    // 直接編集（インライン編集）を管理する変数
    @State private var isEditing = false
    
    // 編集モードで入力中の文字を保持する変数
    @State private var editFileName = ""
    @State private var editNote = ""
    @State private var editExperimenter = ""
    @State private var editWeather = ""
    @State private var editTemperature = ""
    @State private var editHumidity = ""
    @State private var editScene = ""

    init(audioURL: URL) {
        self.initialURL = audioURL
        self._currentURL = State(initialValue: audioURL)
    }

    var body: some View {
        VStack(spacing: 40) {
            Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
                .font(.system(size: 24, weight: .thin, design: .monospaced))

            HStack(spacing: 50) {
                Button(action: {
                    if audioPlayer.isPlaying {
                        audioPlayer.pausePlayback()
                    } else {
                        audioPlayer.startPlayback(audio: currentURL)
                    }
                }) {
                    Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 70))
                        .foregroundColor(.white)
                }
            }


            // ファイル情報のリスト
            List {
                Section(
                    header: HStack {
                        Text("File Information")
                        Spacer()
                        // Edit と Save を切り替えるボタン
                        Button(action: {
                            withAnimation {
                                if isEditing {
                                    saveChanges()  // 保存処理を実行
                                } else {
                                    startEditing()  // 編集モードに切り替え
                                }
                            }
                        }) {
                            Text(isEditing ? "Save" : "Edit")
                                .textCase(.none)
                                .font(.body)
                                .bold(isEditing)
                                .foregroundColor(.blue)
                        }
                    }
                ) {
                    if isEditing {
                        // ーーーー 編集画面のUI ーーーー
                        VStack(alignment: .leading, spacing: 12) { // 余白を少し広げて見やすく調整
                            
                            Group {
                                Text("File Name").font(.caption).foregroundColor(.gray)
                                TextField("Enter file name", text: $editFileName) // .constant から変数をバインディング
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Text("Experimenter").font(.caption).foregroundColor(.gray)
                                TextField("Enter experimenter name", text: $editExperimenter)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                            }

                            Group {
                                Text("Environment").font(.caption).foregroundColor(.gray)
                                
                                Text("Weather").font(.caption).foregroundColor(.gray)
                                TextField("Enter weather", text: $editWeather)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                HStack {
                                    Text("Temperature").font(.caption).foregroundColor(.gray)
                                    Spacer()
                                    TextField("Temp", text: $editTemperature)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(maxWidth: 60)
                                        .keyboardType(.numbersAndPunctuation) // マイナスも打てるキーボードに変更
                                    Text("°C").font(.caption).foregroundColor(.gray)
                                    
                                    Spacer()
                                    
                                    Text("Humidity").font(.caption).foregroundColor(.gray)
                                    Spacer()
                                    TextField("Hum", text: $editHumidity)
                                        .textFieldStyle(RoundedBorderTextFieldStyle())
                                        .frame(maxWidth: 60)
                                        .keyboardType(.numberPad)
                                    Text("%").font(.caption).foregroundColor(.gray)
                                }
                            }
                            
                            Group {
                                Text("Scene").font(.caption).foregroundColor(.gray)
                                TextField("Enter pattern details", text: $editScene)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                Text("Note").font(.caption).foregroundColor(.gray)
                                TextEditor(text: $editNote) // .constant から変更
                                    .frame(minHeight: 80)
                                    .padding(4)
                                    .background(Color(UIColor.secondarySystemBackground)) // TextEditor専用の背景スタイル
                                    .cornerRadius(8)
                            }
                        }
                        .padding(.vertical, 4)

                    } else {
                        // ーーーー 通常（閲覧）モードのUI ーーーー
                        VStack(alignment: .leading, spacing: 8) {
                            if !fileExperimenter.isEmpty {
                                HStack { Text("Experimenter:").foregroundColor(.gray); Text(fileExperimenter) }
                            }
                            if !fileWeather.isEmpty || !fileTemperature.isEmpty || !fileHumidity.isEmpty {
                                HStack {
                                    Text("Environment:").foregroundColor(.gray)
                                    Text("\(fileWeather) \(fileTemperature.isEmpty ? "" : "\(fileTemperature)°C") \(fileHumidity.isEmpty ? "" : "\(fileHumidity)%")")
                                }
                            }
                            if !fileScene.isEmpty {
                                HStack { Text("Scene:").foregroundColor(.gray); Text(fileScene) }
                            }
                            if !fileNote.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Note:").foregroundColor(.gray)
                                    Text(fileNote)
                                }
                            }
                        }
                        .font(.body)
                        
                        Text("FilePath: \(currentURL.path)")
                            .font(.caption)
                            .foregroundColor(.gray)
                            .padding(.top, 4)
                    }
                }
            }
        }
        .padding()
        .navigationTitle(currentURL.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingDeleteAlert = true }) {
                    Image(systemName: "trash").foregroundColor(.white)
                }
            }
        }
        .alert(isPresented: $showingDeleteAlert) {
            Alert(
                title: Text("Delete Recording?"),
                message: Text("Are you sure you want to delete '\(currentURL.lastPathComponent)'? This action cannot be undone."),
                primaryButton: .destructive(Text("Delete")) {
                    audioPlayer.deleteAudio(audio: currentURL)
                    self.presentationMode.wrappedValue.dismiss()
                },
                secondaryButton: .cancel()
            )
        }
        .onAppear {
            loadSavedData(for: currentURL.lastPathComponent)
        }
        .onDisappear {
            audioPlayer.stopPlayback()
        }
    }

    // MARK: - 編集機能のメソッド群

    // ファイル名に応じたデータを読み込む
    private func loadSavedData(for fileName: String) {
        fileNote = UserDefaults.standard.string(forKey: "\(fileName)_note") ?? UserDefaults.standard.string(forKey: fileName) ?? ""
        fileExperimenter = UserDefaults.standard.string(forKey: "\(fileName)_experimenter") ?? ""
        fileWeather = UserDefaults.standard.string(forKey: "\(fileName)_weather") ?? ""
        fileTemperature = UserDefaults.standard.string(forKey: "\(fileName)_temperature") ?? ""
        fileHumidity = UserDefaults.standard.string(forKey: "\(fileName)_humidity") ?? ""
        fileScene = UserDefaults.standard.string(forKey: "\(fileName)_scene") ?? ""
    }

    // 編集を開始する時の準備
    private func startEditing() {
        editFileName = currentURL.deletingPathExtension().lastPathComponent
        editNote = fileNote
        editExperimenter = fileExperimenter
        editWeather = fileWeather
        editTemperature = fileTemperature
        editHumidity = fileHumidity
        editScene = fileScene
        isEditing = true
    }

    // 保存ボタンを押した時の処理
    private func saveChanges() {
        // 入力された文字を閲覧用の変数に反映
        fileNote = editNote
        fileExperimenter = editExperimenter
        fileWeather = editWeather
        fileTemperature = editTemperature
        fileHumidity = editHumidity
        fileScene = editScene

        let oldFileName = currentURL.lastPathComponent
        var newURL = currentURL

        // ファイル名が変更されていればリネーム処理
        let oldNameWithoutExtension = currentURL.deletingPathExtension().lastPathComponent
        if editFileName != oldNameWithoutExtension && !editFileName.isEmpty {
            audioPlayer.stopPlayback()

            let fileManager = FileManager.default
            let folderURL = currentURL.deletingLastPathComponent()
            let extensionString = currentURL.pathExtension
            let destinationURL = folderURL.appendingPathComponent("\(editFileName).\(extensionString)")

            do {
                try fileManager.moveItem(at: currentURL, to: destinationURL)
                newURL = destinationURL
                currentURL = destinationURL // 新しいURLに切り替え
            } catch {
                print("ファイル名の変更に失敗しました: \(error.localizedDescription)")
            }
        }

        let newFileName = newURL.lastPathComponent
        
        // ファイル名が変わった場合は古いデータを削除する
        if oldFileName != newFileName {
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_note")
            UserDefaults.standard.removeObject(forKey: oldFileName) // 古い仕様のノートキーも削除
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_experimenter")
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_weather")
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_temperature")
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_humidity")
            UserDefaults.standard.removeObject(forKey: "\(oldFileName)_scene")
        }

        // 新しいデータを保存
        UserDefaults.standard.set(fileNote, forKey: "\(newFileName)_note")
        UserDefaults.standard.set(fileExperimenter, forKey: "\(newFileName)_experimenter")
        UserDefaults.standard.set(fileWeather, forKey: "\(newFileName)_weather")
        UserDefaults.standard.set(fileTemperature, forKey: "\(newFileName)_temperature")
        UserDefaults.standard.set(fileHumidity, forKey: "\(newFileName)_humidity")
        UserDefaults.standard.set(fileScene, forKey: "\(newFileName)_scene")

        isEditing = false
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}