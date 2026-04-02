import SwiftUI

// MARK: - 0. Preview(Xcode)
struct RecordingssView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingsView()
    }
}

// MARK: - 1. AudioRecorder(録音機能)
// class AudioRecorder: ObservableObject {
//     private var audioRecorder: AVAudioRecorder?
//     private var timer: Timer?  
//     @Published var isRecording = false
//     @Published var elapsedTime: TimeInterval = 0.0
//     private var startTime: Date?

//     // 録音開始メソッド
//     func startRecording() {
//         let audioSession = AVAudioSession.sharedInstance()
//         let fileManager = FileManager.default
//         let documentPath = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

// MARK: - 2. RecordingsView(録音画面)
struct RecordingsView: View {
    @StateObject private var audioRecorder = AudioRecorder()

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                    .frame(height: 50)

                // --- 録音時間の表示 ---
                Text(formatTime(audioRecorder.elapsedTime))
                    .font(.system(size: 40, weight: .thin, design: .monospaced))
            
                // --- 波形イメージ ---
                HStack(spacing: 4) {
                    ForEach(0..<15) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(audioRecorder.isRecording ? Color.red : Color.gray.opacity(0.3))
                            .frame(width: 4, height: audioRecorder.isRecording ? CGFloat.random(in: 20...80) : 10)
                            .animation(audioRecorder.isRecording ? .easeInOut(duration: 0.5).repeatForever() : .default, value: audioRecorder.isRecording)
                    }
                }
                .frame(height: 100)
                
                Spacer()
                
                // --- 録音ボタン---
                Button(action: {
                    if audioRecorder.isRecording {
                        audioRecorder.stopRecording()
                    } else {
                        audioRecorder.startRecording()
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 80, height: 80)
                        
                        if audioRecorder.isRecording {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
                .padding(.bottom, 150)
            }
            // タイトルバーの設定
            .navigationTitle("Recordings")
        }
    }
}