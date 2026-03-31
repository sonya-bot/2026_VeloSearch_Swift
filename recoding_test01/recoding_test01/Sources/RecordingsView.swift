import SwiftUI

// 各画面のレイアウト
struct RecordingsView: View {
    // 録音中かどうかを管理する状態(AudioRecorderクラスの呼び出し)
    @StateObject private var audioRecorder = AudioRecorder()

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        // 1未満の端数を取り出し、100を掛けて2桁の整数（ミリ秒）にする
        let milliseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        
        return String(format: "%02d:%02d.%02d", minutes, seconds, milliseconds)
    }
    
    var body: some View {
        // 文字
        ZStack {
            VStack {
                HStack{
                    Text("Recordings")
                        .font(.largeTitle)
                        .bold()
                        .padding(10)
                    Spacer()
                }
                Spacer()
                    .frame(height: 50)

                // --- 録音時間の表示 ---
                Text(formatTime(audioRecorder.elapsedTime))
                .font(.system(size: 40, weight: .thin, design: .monospaced)) // 等幅フォントで数字のブレを防ぐ
            
                
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
                    // 録音状態に応じて、開始と停止を切り替える
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
            .padding()
        }
    }
}
