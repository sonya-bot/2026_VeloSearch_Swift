import Foundation
import AVFoundation
import SwiftUI
import CoreLocation

// MARK: - 0. Preview(Xcode)
struct RecordingsView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingsView()
    }
}

// MARK: - 1. AudioRecorder(録音ロジック)
class AudioRecorder: ObservableObject {
    var audioRecorder: AVAudioRecorder?
    
    // @Published をつけると、この値が変わった時にUIが自動で更新される
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0.0
    @Published var soundLevel: [CGFloat] = Array(repeating: 0.1, count: 20) // 音量レベルの配列（例: 20段階）
    @Published var currentDecibel: Float = 0.0 // 現在のデシベル値（初期値は最小値）

    private var timer: Timer?
    private var levelTimer: Timer?
    private var startTime: Date?
    
    // 録音開始メソッド
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // ファイル命名規則の決定
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        let nextNumber = getNextSequenceNumber(dateString: dateString, in: documentPath)
        let fileName = "\(dateString)_\(String(format: "%02d", nextNumber)).wav"
        let audioFilename = documentPath.appendingPathComponent(fileName)

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
            // マイク音量の取得を有効化
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            
            isRecording = true
            print("録音開始: 保存先は \(fileName) です")
            elapsedTime = 0.0
            startTime = Date()
            currentDecibel = 0.0 // デシベル値をリセット

            // 時間計測タイマー (0.01秒ごとに更新)
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.startTime else { return }
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
            
            // 波形アニメーション用の監視を開始
            startMonitoring()
            
        } catch {
            print("録音の開始に失敗しました: \(error.localizedDescription)")
        }
    }

    // 連番を取得するためのヘルパーメソッド
    private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
        let fileManager = FileManager.default
        do {
            let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            let dailyFiles = files.filter { $0.lastPathComponent.hasPrefix(dateString) }
            return dailyFiles.count + 1
        } catch {
            return 1
        }
    }

    // 録音停止メソッド
    func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
        
        // タイマーをすべて停止
        timer?.invalidate()
        timer = nil
        levelTimer?.invalidate()
        levelTimer = nil
        startTime = nil
        currentDecibel = 0.0 // デシベル値をリセット
        
        // 波形を平らにリセット
        soundLevel = Array(repeating: 0.1, count: 20)
        print("録音停止")
    }
    
    // 波形アニメーション用メソッド
    
    private func startMonitoring() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
            guard let self = self, let recorder = self.audioRecorder else { return }
            
            recorder.updateMeters()
            let power = recorder.averagePower(forChannel: 0)
            let level = self.normalizeSoundLevel(level: power)
            
            // 配列を左にスライドさせて新しいデータを右に追加
            self.soundLevel.removeFirst()
            self.soundLevel.append(level)
        }
    }
    
    private func normalizeSoundLevel(level: Float) -> CGFloat {
        let baseLevel = max(0.0, CGFloat(level) + 50)
        let normalized = min(baseLevel / 50, 1.0)
        return max(0.1, normalized)
    }
}

// MARK: - 2. 移動速度の取得
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    @Published var speed: CLLocationSpeed = 0.0
    
    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation // 高精度を要求
        // 位置情報の使用許可をリクエスト
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // 速度が取得できない場合（-1.0）は0にする
        self.speed = max(location.speed, 0.0)
    }
}

// MARK: - 3. AudioRecorderview(画面UI)
struct RecordingsView: View {
    // クラスの呼び出し
    @StateObject private var audioRecorder = AudioRecorder() // 録音ロジックを管理するAudioRecorderクラスのインスタンス
    @StateObject private var locationManager = LocationManager() // 速度取得用のLocationManager
    
    var body: some View {
        NavigationView {
            VStack{
                Spacer().frame(height: 60)
                // 録音時間の表示（0.01秒まで表示）
                Text(formatElapsedTime(audioRecorder.elapsedTime))
                    .font(.system(size: 48, weight: .thin))
                Spacer()
                // リアルタイム波形アニメーション
                HStack(spacing: 4) {
                    ForEach(0..<audioRecorder.soundLevel.count, id: \.self) { index in
                        Capsule()
                            .fill(audioRecorder.isRecording ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 6, height: audioRecorder.soundLevel[index] * 100)
                            .animation(.linear(duration: 0.05), value: audioRecorder.soundLevel[index])
                    }
                }
                
                Spacer().frame(height: 100)
                
                // 音量表示
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
                            Spacer() // ★値を右端に綺麗に揃えるバネ
                            Text("\(String(format: "%.1f", locationManager.speed * 3.6)) km/h")
                                .font(.title2)
                                .monospacedDigit()
                        }
                    }
                
                .listStyle(InsetGroupedListStyle()) 
                .frame(height: 10) 
                .scrollDisabled(true) 
                }
                .scrollContentBackground(.hidden)

                
                Spacer()
                
                // 録音・停止ボタン
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    } else {
                        audioRecorder.startRecording()
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
                .padding(.bottom, 100) // 画面の底から少し浮かせる
            }
            .navigationTitle("Recordings")
        }
    }
    
    // 時間を "00:00.00" の形式にフォーマットするヘルパー関数
    private func formatElapsedTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }

}
