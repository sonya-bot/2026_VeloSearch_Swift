import Foundation
import AVFoundation
import SwiftUI
import CoreLocation
import Observation

// MARK: - 0. Preview(Xcode)
struct RecordingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingsView()
    }
}


// MARK: - 1. AudioRecorder (録音ロジック)
@Observable // ★ ObservableObject から @Observable に進化
class AudioRecorder {
    var audioRecorder: AVAudioRecorder?
    
    var isRecording = false
    var elapsedTime: TimeInterval = 0.0
    var soundLevel: [CGFloat] = Array(repeating: 0.1, count: 20)
    var currentDecibel: Float = 0.0

    private var timer: Timer?
    private var levelTimer: Timer?
    private var startTime: Date?

    private var speedcsvTimer: Timer?
    private var speedcsvData: [String] = []
    private var currentBaseFileName: String = ""

    func startRecording(locationManager: LocationManager) {
        let audioSession = AVAudioSession.sharedInstance()
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        let nextNumber = getNextSequenceNumber(dateString: dateString, in: documentPath)
        self.currentBaseFileName = "Recording_\(dateString)_\(String(format: "%02d", nextNumber))" // 録音ファイルの接頭辞は "Recording_"
        let audioFilename = documentPath.appendingPathComponent("\(self.currentBaseFileName).wav")

        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            let settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: 44100,
                AVNumberOfChannelsKey: 2,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            print("録音開始: 保存先は \(self.currentBaseFileName)です")
            elapsedTime = 0.0
            startTime = Date()
            currentDecibel = 0.0
            speedcsvData = ["elapsed_time,speed_kmh,volume_db"]

            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
            
            startMonitoring()

            speedcsvTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let time = self.elapsedTime
                let speedKmh = locationManager.speed * 3.6
                let volume = self.currentDecibel
                let logLine = String(format: "%.2f,%.1f,%.1f", time, speedKmh, volume)
                self.speedcsvData.append(logLine)
            }
            
        } catch {
            print("録音の開始に失敗しました: \(error.localizedDescription)")
        }
    }

    private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let dailyFiles = files.filter { $0.lastPathComponent.hasPrefix(dateString) && $0.pathExtension == "wav" }
            return dailyFiles.count + 1
        } catch {
            return 1
        }
    }

    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        startTime = nil
        elapsedTime = 0.0
        currentDecibel = 0.0
        speedcsvTimer?.invalidate()
        speedcsvTimer = nil
        
        savespeedCSV()
        soundLevel = Array(repeating: 0.1, count: 20)
        print("録音停止")
    }
    
    private func startMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let level = self.normalizeSoundLevel(level: power)
            self.currentDecibel = power
            self.soundLevel.removeFirst()
            self.soundLevel.append(level)
        }
    }
    
    private func normalizeSoundLevel(level: Float) -> CGFloat {
        let baseLevel = max(0.0, CGFloat(level) + 50)
        let normalized = min(baseLevel / 50, 1.0)
        return max(0.1, normalized)
    }

    private func savespeedCSV() {
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let csvFilename = documentPath.appendingPathComponent("\(currentBaseFileName).csv")
        let csvString = speedcsvData.joined(separator: "\n")
        
        do {
            try csvString.write(to: csvFilename, atomically: true, encoding: .utf8)
            print("CSV保存完了: \(currentBaseFileName).csv")
        } catch {
            print("CSVの保存に失敗しました: \(error.localizedDescription)")
        }
    }
}

// MARK: - 2. LocationManager
@Observable
class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var speed: CLLocationSpeed = 0.0
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        self.speed = max(location.speed, 0.0)
    }
}

// MARK: - 3. RecordingsView (画面UI)
struct RecordingsView: View {

    @State private var audioRecorder = AudioRecorder()
    @State private var locationManager = LocationManager()
    
    var body: some View {
        NavigationStack {
            VStack{
                Spacer().frame(height: 60)
                
                Text(formatElapsedTime(audioRecorder.elapsedTime))
                    .font(.system(size: 48, weight: .thin))
                    // 固定幅フォント
                    .monospacedDigit()
                
                Spacer()
                
                // 波形アニメーション
                HStack(spacing: 4) {
                    ForEach(0..<audioRecorder.soundLevel.count, id: \.self) { index in
                        Capsule()
                            .fill(audioRecorder.isRecording ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 6, height: audioRecorder.soundLevel[index] * 100)
                            .animation(.linear(duration: 0.05), value: audioRecorder.soundLevel[index])
                    }
                }
                .frame(height: 100)
                
                Spacer().frame(height: 50)
                
                List {
                    Section(header: Text("Details")) {
                        HStack {
                            Text("Volume:")
                                .font(.title)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(String(format: "%.1f", audioRecorder.currentDecibel)) dB")
                                .font(.title2)
                                .monospacedDigit()
                        }
                        
                        HStack {
                            Text("Speed:")
                                .font(.title)
                                .foregroundColor(.gray)
                            Spacer()
                            Text("\(String(format: "%.1f", locationManager.speed * 3.6)) km/h")
                                .font(.title2)
                                .monospacedDigit()
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .frame(height: 180) 
                .scrollDisabled(true) 
                .scrollContentBackground(.hidden)
                
                
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    } else {
                        audioRecorder.startRecording(locationManager: locationManager)
                    }
                }) {
                    ZStack {
                        Circle()
                            .strokeBorder(Color.white, lineWidth: 3)
                            .frame(width: 70, height: 70)
                        
                        if audioRecorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 60, height: 60)
                        }
                    }
                }
                .padding(.bottom, 80)
            }
            .navigationTitle("Recordings")
        }
    }
    
    private func formatElapsedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
}
