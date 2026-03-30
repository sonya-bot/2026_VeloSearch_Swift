import SwiftUI

// 各画面のレイアウト
struct RecordingsView: View {
    // 録音中かどうかを管理する状態（デコイ）
    @State private var isRecording = false
    
    var body: some View {
        ZStack {
            
            VStack {
                HStack{
                    Text("Collections")
                        .font(.largeTitle)
                        .bold()
                        .padding(10)
                    Spacer()
                }
                Spacer()
            
                
                // --- 波形イメージ（デコイ） ---
                // 録音中にピコピコ動く赤いバーのダミー
                HStack(spacing: 4) {
                    ForEach(0..<15) { _ in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(isRecording ? Color.red : Color.gray.opacity(0.3))
                            // 録音中は高さをランダムに変えて動かす
                            .frame(width: 4, height: isRecording ? CGFloat.random(in: 20...80) : 10)
                            // ヌルッと動くアニメーション
                            .animation(isRecording ? .easeInOut(duration: 0.5).repeatForever() : .default, value: isRecording)
                    }
                }
                .frame(height: 100)
                
                Spacer()
                
                // --- 録音ボタン（デコイ） ---
                Button(action: {
                    // ボタンを押した時の処理（見た目の切り替えだけ）
                    withAnimation {
                        isRecording.toggle()
                    }
                }) {
                    ZStack {
                        // 土台の白丸
                        Circle()
                            .fill(Color.white)
                            .frame(width: 80, height: 80)
                        
                        if isRecording {
                            // 停止ボタンの形（角丸の赤四角）
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.red)
                                .frame(width: 30, height: 30)
                        } else {
                            // 録音ボタンの形（赤丸）
                            Circle()
                                .fill(Color.red)
                                .frame(width: 70, height: 70)
                        }
                    }
                }
                // 重要：カスタムタブバーに被らないように、下の余白を大きく取ります
                .padding(.bottom, 150)
            }
            .padding()
        }
    }
}