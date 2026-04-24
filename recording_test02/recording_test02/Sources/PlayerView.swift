import AVFoundation
import Observation
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct PlayerView_Previews: PreviewProvider {
  static var previews: some View {
    PlayerView(audioURL: URL(string: "https://example.com/audio.m4a")!)
  }
}

// MARK: - 1. AudioPlayer (動作の定義)
@Observable
class AudioPlayer {
  var audioPlayer: AVAudioPlayer?

  var isPlaying = false
  var currentTime: TimeInterval = 0.0
  var duration: TimeInterval = 0.0

  private var timer: Timer?

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

  func pausePlayback() {
    audioPlayer?.pause()
    isPlaying = false
  }

  func stopPlayback() {
    audioPlayer?.stop()
    isPlaying = false
    timer?.invalidate()
    timer = nil
  }

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

// MARK: - 2. CSVRecord
struct CSVRecord {
  let time: Double
  let speed: String
}

// MARK: - 3. PlayerView (画面UI)
struct PlayerView: View {
  let initialURL: URL
  @State private var currentURL: URL

  @State private var audioPlayer = AudioPlayer()  // ★ @StateObject -> @State

  @Environment(\.dismiss) private var dismiss

  @State private var showingDeleteAlert = false

  @State private var fileNote: String = ""
  @State private var fileExperimenter: String = ""
  @State private var fileWeather: String = ""
  @State private var fileTemperature: String = ""
  @State private var fileHumidity: String = ""
  @State private var fileScene: String = ""

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

  init(audioURL: URL) {
    self.initialURL = audioURL
    self._currentURL = State(initialValue: audioURL)
  }

  var body: some View {
    VStack(spacing: 20) {
      Text("\(formatTime(audioPlayer.currentTime)) / \(formatTime(audioPlayer.duration))")
        .font(.system(size: 30, weight: .thin))
        .monospacedDigit()
        .onChange(of: audioPlayer.currentTime) { oldTime, newTime in
          updateSpeed(for: newTime)
        }

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

      Slider(
        value: Binding(
          get: { audioPlayer.currentTime },
          set: { newValue in
            audioPlayer.seek(to: newValue)
          }
        ), in: 0...(audioPlayer.duration > 0 ? audioPlayer.duration : 1.0)
      )
      .accentColor(.red)
      .padding(.horizontal, 20)

      HStack(spacing: 50) {
        Text("Speed:")
          .font(.title2)
          .foregroundColor(.gray)
          .frame(width: 80, alignment: .trailing)
        Text("\(currentSpeed) km/h")
          .font(.title)
          .monospacedDigit()
          .frame(width: 150, alignment: .leading)
      }

      List {
        Section(
          header: HStack {
            Text("File Information")
            Spacer()
            Button(action: {
              withAnimation {
                if isEditing {
                  saveChanges()
                } else {
                  startEditing()
                }
              }
            }) {
              Label(isEditing ? "Save" : "Edit", systemImage: isEditing ? "checkmark" : "pencil")
                .textCase(.none)
                .font(.body)
                .bold(isEditing)
                .foregroundColor(.blue)
            }
          }
        ) {
          if isEditing {
            VStack(alignment: .leading, spacing: 12) {
              Group {
                Text("File Name").font(.caption).foregroundColor(.gray)
                TextField("Enter file name", text: $editFileName)
                  .textFieldStyle(.roundedBorder)

                Text("Experimenter").font(.caption).foregroundColor(.gray)
                TextField("Enter experimenter name", text: $editExperimenter)
                  .textFieldStyle(.roundedBorder)
              }

              Group {
                Text("Environment").font(.caption).foregroundColor(.gray)

                Text("Weather").font(.caption).foregroundColor(.gray)
                TextField("Enter weather", text: $editWeather)
                  .textFieldStyle(.roundedBorder)

                HStack {
                  Text("Temperature").font(.caption).foregroundColor(.gray)
                  Spacer()
                  TextField("Temp", text: $editTemperature)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)
                    .keyboardType(.numbersAndPunctuation)
                  Text("°C").font(.caption).foregroundColor(.gray)

                  Spacer()

                  Text("Humidity").font(.caption).foregroundColor(.gray)
                  Spacer()
                  TextField("Hum", text: $editHumidity)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 60)
                    .keyboardType(.numberPad)
                  Text("%").font(.caption).foregroundColor(.gray)
                }
              }

              Group {
                Text("Scene").font(.caption).foregroundColor(.gray)
                TextField("Enter pattern details", text: $editScene)
                  .textFieldStyle(.roundedBorder)

                Text("Note").font(.caption).foregroundColor(.gray)
                TextEditor(text: $editNote)
                  .frame(minHeight: 80)
                  .padding(4)
                  .scrollContentBackground(.hidden)
                  .background(.quaternary)
                  .cornerRadius(8)
              }
            }
            .padding(.vertical, 4)

          } else {
            VStack(alignment: .leading, spacing: 12) {
              Group {
                Text("File Name: \(currentURL.lastPathComponent)").font(.caption).foregroundColor(
                  .gray)
                Text("Experimenter: \(fileExperimenter)").font(.caption).foregroundColor(.gray)
              }
              Group {
                Text("Environment").font(.caption).foregroundColor(.gray)
                Text("Weather: \(fileWeather)").font(.caption).foregroundColor(.gray)
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
      .scrollContentBackground(.hidden)
      .padding(.bottom, 80)
    }
    .padding()
    .navigationTitle(currentURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItemGroup(placement: .topBarTrailing) {
          // 1. 共有ボタン
          ShareLink(item: currentURL) {
              Image(systemName: "square.and.arrow.up")
          }
          
          // 2. 削除ボタン
          Button(action: { showingDeleteAlert = true }) {
              Image(systemName: "trash")
                  .foregroundColor(.white)
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
      loadCSVData()
    }
    .onDisappear {
      audioPlayer.stopPlayback()
    }
  }

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

      do {
        try fileManager.moveItem(at: currentURL, to: destinationURL)
        if fileManager.fileExists(atPath: oldCSVURL.path) {
          try fileManager.moveItem(at: oldCSVURL, to: newCSVURL)
        }

        newURL = destinationURL
        currentURL = destinationURL
        loadCSVData()
      } catch {
        print("ファイル名の変更に失敗しました: \(error.localizedDescription)")
      }
    }

    let newFileName = newURL.lastPathComponent

    if oldFileName != newFileName {
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_note")
      UserDefaults.standard.removeObject(forKey: oldFileName)
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_experimenter")
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_weather")
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_temperature")
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_humidity")
      UserDefaults.standard.removeObject(forKey: "\(oldFileName)_scene")
    }

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
      print("CSVファイルの読み込みに失敗、またはファイルが存在しません")
      self.currentSpeed = "--"
    }
  }

  private func updateSpeed(for time: TimeInterval) {
    guard !csvRecords.isEmpty else { return }
    if let closestRecord = csvRecords.min(by: { abs($0.time - time) < abs($1.time - time) }) {
      self.currentSpeed = closestRecord.speed
    }
  }
}
