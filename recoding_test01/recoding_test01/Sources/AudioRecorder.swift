import Foundation
import AVFoundation

// UI側から状態（isRecording）を監視できるように ObservableObject にする
class AudioRecorder: ObservableObject {
    var audioRecorder: AVAudioRecorder?
    
    // @Published をつけると、この値が変わった時にUIが自動で更新される
    @Published var isRecording = false
    @Published var elapsedTime: TimeInterval = 0.0

    private var timer: Timer?
    private var startTime: Date?
    
    // 録音開始メソッド
    func startRecording() {
        let audioSession = AVAudioSession.sharedInstance()
        let fileManager = FileManager.default
        let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // ファイル命名規則の決定
        // 今日の日付文字列（YYYYMMDD）を作成
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let dateString = formatter.string(from: Date())
        // 連番の決定
        let nextNumber = getNextSequenceNumber(dateString: dateString, in: documentPath)
        // 最終的なファイル名の決定
        let fileName = "\(dateString)_\(String(format: "%02d", nextNumber)).wav"
        let audioFilename = documentPath.appendingPathComponent(fileName)

        do {
            // マイクを使用する設定
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)

            // 録音の音質やフォーマットの設定
            let settings = [
                AVFormatIDKey: Int(kAudioFormatLinearPCM), // 音声フォーマットの指定(今回はリニアPCM)
                AVSampleRateKey: 44100, // サンプリング周波数の指定
                AVNumberOfChannelsKey: 2, // ステレオ
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

            // 録音機（AVAudioRecorder）の準備と録音開始
            audioRecorder = try AVAudioRecorder(url: audioFilename, settings: settings)
            audioRecorder?.record()
            
            isRecording = true
            print("録音開始: 保存先は \(fileName) です")
            elapsedTime = 0.0
            startTime = Date()

            // タイマーを開始して、録音時間を更新する
            timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [weak self] _ in
                guard let self = self, let startTime = self.startTime else { return }
                // 現在時刻と開始時刻の差分を計算（誤差が出ない正確な方法）
                self.elapsedTime = Date().timeIntervalSince(startTime)
            }
            
        } catch {
            print("録音の開始に失敗しました: \(error.localizedDescription)")
        }
    }

        // 連番を取得するためのヘルパーメソッド
        private func getNextSequenceNumber(dateString: String, in directory: URL) -> Int {
            let fileManager = FileManager.default
            do {
                let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                // 今日の日付で始まるファイルだけを抽出
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
        
        timer?.invalidate()
        timer = nil
        startTime = nil
        print("録音停止")
    }
}