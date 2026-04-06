import AVFoundation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct PlayerView_Previews: PreviewProvider {
  static var previews: some View {
    PlayerView(audioURL: URL(string: "https://example.com/audio.m4a")!)
  }
}

// MARK: - 1. AudioPlayer(動作の定義)
class AudioPlayer: ObservableObject {
  var audioPlayer: AVAudioPlayer?

  @Published var isPlaying = false
  @Published var currentTime: TimeInterval = 0.0
  @Published var duration: TimeInterval = 0.0

  private var timer: Timer?

  // 録音ファイルの長さを取得・再生の準備をするメソッド
  func prepareAudio(audio: URL) {
    do {
      audioPlayer = try AVAudioPlayer(contentsOf: audio)
      audioPlayer?.prepareToPlay()
      duration = audioPlayer?.duration ?? 0.0
      currentTime = 0.0
    } catch {
      print("音声の準備に失敗しました: \(error.localizedDescription)")
    }
  }

  // 再生を開始するメソッド
  func startPlayback() {
    let playbackSession = AVAudioSession.sharedInstance()
    do {
      try playbackSession.setCategory(.playback, mode: .default)
      try playbackSession.setActive(true)

      audioPlayer?.play()
      isPlaying = true

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

  // 再生を一時停止するメソッド
  func pausePlayback() {
    audioPlayer?.pause()
    isPlaying = false
  }

  // 再生を停止するメソッド
  func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
    timer?.invalidate()
    timer = nil
  }

  // 指定した場所から再生する(シークバー)メソッド
  func seek(to time: TimeInterval) {
    audioPlayer?.currentTime = time
    self.currentTime = time
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

// MARK: - 2. csvファイルの保存と読み込みの定義
struct CSVRecord {
  let time: Double
  let speed: String
}

// MARK: - 3. AudioDetailView(画面UI)
struct PlayerView: View {
  let initialURL: URL
  @State private var currentURL: URL

  @StateObject private var audioPlayer = AudioPlayer()
  @Environment(\.presentationMode) var presentationMode

  @State private var showingDeleteAlert = false

  // ★ 追加: 通常モードで表示するための保存用変数
  @State private var fileNote: String = ""
  @State private var fileExperimenter: String = ""
  @State private var fileWeather: String = ""
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

  @State private var csvRecords: [CSVRecord] = []
  @State private var currentSpeed: String = "--"

  init(audioURL: URL) {
    self.initialURL = audioURL
    self.currentURL = audioURL
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
        .font(.system(size: 30, weight: .thin))
        .onChange(of: audioPlayer.currentTime) { oldTime, newTime in
                            updateSpeed(for: newTime)
        }

      // 再生ボタン
      HStack(spacing: 50) {
        Button(action: {
          if audioPlayer.isPlaying {
            audioPlayer.pausePlayback()
          } else {
            audioPlayer.startPlayback()
          }
        }) {
          Image(systemName: audioPlayer.isPlaying ? "pause.circle.fill" : "play.circle.fill")
            .font(.system(size: 50))
            .foregroundColor(.white)
        }
      }

      // シークバー
      Slider(
        value: Binding(
          get: { audioPlayer.currentTime },
          set: { newValue in
            audioPlayer.seek(to: newValue)
          }
        ), in: 0...(audioPlayer.duration > 0 ? audioPlayer.duration : 1.0)
      )
      .accentColor(.red)  // 録音アプリらしい赤色に設定
      .padding(.horizontal, 20)  // 画面の両端に余白を設ける

      // 速度(csvファイル)表示
      HStack(spacing: 50) {
        Text("Speed:")
          .font(.title2)
          .foregroundColor(.gray)
        Text("\(currentSpeed) km/h")
          .font(.title)
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
            // 編集画面のUI
            VStack(alignment: .leading, spacing: 12) {  // 余白を少し広げて見やすく調整

              Group {
                Text("File Name").font(.caption).foregroundColor(.gray)
                TextField("Enter file name", text: $editFileName)  // .constant から変数をバインディング
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
                    .keyboardType(.numbersAndPunctuation)  // マイナスも打てるキーボードに変更
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
                TextEditor(text: $editNote)  // .constant から変更
                  .frame(minHeight: 80)
                  .padding(4)
                  .background(Color(UIColor.secondarySystemBackground))  // TextEditor専用の背景スタイル
                  .cornerRadius(8)
              }
            }
            .padding(.vertical, 4)

          } else {
            VStack(alignment: .leading, spacing: 12) {  // 余白を少し広げて見やすく調整

              Group {
                Text("File Name: \(currentURL.lastPathComponent)").font(.caption).foregroundColor(
                  .gray)  // ファイル名
                Text("Experimenter: \(fileExperimenter)").font(.caption).foregroundColor(.gray)  // 実験者
              }
              Group {
                Text("Environment").font(.caption).foregroundColor(.gray)  // 実験環境
                Text("Weather: \(fileWeather)").font(.caption).foregroundColor(.gray)  // 天気
                HStack(spacing: 20) {
                  Text("Temperature: \(fileTemperature.isEmpty ? "N/A" : "\(fileTemperature)°C")")
                    .font(.caption).foregroundColor(.gray)
                  Text("Humidity: \(fileHumidity.isEmpty ? "N/A" : "\(fileHumidity)%")").font(
                    .caption
                  ).foregroundColor(.gray)
                }
              }

              Group {
                Text("Scene: \(fileScene)").font(.caption).foregroundColor(.gray)

                Text("Note").font(.caption).foregroundColor(.gray)
                Text(fileNote).font(.body).foregroundColor(.gray)
              }
            }
            .font(.body)

            Text("FilePath: \(currentURL.path)")
              .font(.caption)
              .foregroundColor(.gray)
              .padding(.top, 4)
          }
        }

        let csvURL = currentURL.deletingPathExtension().appendingPathExtension("csv")
                
            Section(
                header: HStack {
                    Text("Speed Data (CSV)")
                    Spacer()
                    ShareLink(item: csvURL) {
                        Text("Share")
                            .textCase(.none)
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }
            ) {
            // タップした時に遷移する先の画面（今は仮のテキストを置いています）
            NavigationLink(destination: CSVPreviewView(csvURL: csvURL)) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.gray)
                        .imageScale(.large)
                    
                    Text(csvURL.lastPathComponent)
                        .font(.body)
                        .padding(.leading, 8)
                    
                    Spacer()
                }
                .padding(.vertical, 4)
            }
            }
      }
      .scrollContentBackground(.hidden)
      .padding(.bottom, 80)  // 下部に余白を追加して、タブバーと被らないようにする
    }
    .padding()
    .navigationTitle(currentURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .navigationBarTrailing) {
        HStack(spacing: 20) {
          // 共有ボタン
          ShareLink(item: currentURL) {
            Image(systemName: "square.and.arrow.up")
              .foregroundColor(.white)
          }
          // 削除ボタン
          Button(action: { showingDeleteAlert = true }) {
            Image(systemName: "trash").foregroundColor(.white)
          }
        }
      }
    }
    .alert(isPresented: $showingDeleteAlert) {
      Alert(
        title: Text("Delete Recording?"),
        message: Text(
          "Are you sure you want to delete '\(currentURL.lastPathComponent)'? This action cannot be undone."
        ),
        primaryButton: .destructive(Text("Delete")) {
          audioPlayer.deleteAudio(audio: currentURL)
          self.presentationMode.wrappedValue.dismiss()
        },
        secondaryButton: .cancel()
      )
    }
    .onAppear {
      audioPlayer.prepareAudio(audio: currentURL)
      loadSavedData(for: currentURL.lastPathComponent)
      loadCSVData()
    }
    .onDisappear {
      audioPlayer.stopPlayback()
    }
  }

  // MARK:  - 4. 編集機能のメソッド群

  // ファイル名に応じたデータを読み込む
  private func loadSavedData(for fileName: String) {
    fileNote =
      UserDefaults.standard.string(forKey: "\(fileName)_note") ?? UserDefaults.standard.string(
        forKey: fileName) ?? ""
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

      let oldCSVURL = currentURL.deletingPathExtension().appendingPathExtension("csv")
      let newCSVURL = folderURL.appendingPathComponent("\(editFileName).csv")

      do {
        try fileManager.moveItem(at: currentURL, to: destinationURL)
        if fileManager.fileExists(atPath: oldCSVURL.path) {
                    try fileManager.moveItem(at: oldCSVURL, to: newCSVURL)
                }

        newURL = destinationURL
        currentURL = destinationURL  // 新しいURLに切り替え
        loadCSVData()
      } catch {
        print("ファイル名の変更に失敗しました: \(error.localizedDescription)")
      }
    }

    let newFileName = newURL.lastPathComponent

    // ファイル名が変わった場合は古いデータを削除する
    if oldFileName != newFileName {
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_note")
      UserDefaults.standard.removeObject(forKey: oldFileName)  // 古い仕様のノートキーも削除
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

  // CSV読み込みと速度更新ロジック

  private func loadCSVData() {
    let csvURL = currentURL.deletingPathExtension().appendingPathExtension("csv")

    do {
      let csvString = try String(contentsOf: csvURL, encoding: .utf8)
      let lines = csvString.components(separatedBy: .newlines)

      var records: [CSVRecord] = []
      // 1行目(ヘッダー)を飛ばして、2行目から読み込む
      for line in lines.dropFirst() {
        let columns = line.components(separatedBy: ",")
        if columns.count >= 2, let time = Double(columns[0]) {
          records.append(CSVRecord(time: time, speed: columns[1]))
        }
      }
      self.csvRecords = records

      // ロード直後に0秒の速度を表示
      updateSpeed(for: 0.0)

    } catch {
      print("CSVファイルの読み込みに失敗、またはファイルが存在しません: \(error.localizedDescription)")
      self.currentSpeed = "--"
    }
  }

  private func updateSpeed(for time: TimeInterval) {
    // データがない場合は処理しない
    guard !csvRecords.isEmpty else { return }

    // 現在の時間に最も近いレコードを探す
    // 二分探索（Binary Search）を使えば高速ですが、データ数が多くないので今回はシンプルな方法で
    if let closestRecord = csvRecords.min(by: { abs($0.time - time) < abs($1.time - time) }) {
      self.currentSpeed = closestRecord.speed
    }
  }
}
