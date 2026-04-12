import SwiftUI

// MARK: - 0. Preview(Xcode)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

struct SettingsView: View {
    // @AppStorageを使うと、状態がUserDefaultsに自動保存され、次回起動時にも維持されます
    @AppStorage("isNoiseFilterEnabled") private var isNoiseFilterEnabled = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - 録音設定セクション
                Section {
                    Toggle(isOn: $isNoiseFilterEnabled) {
                        HStack(spacing: 12) {
                            // アイコンの背景を青色にしてiOS設定アプリっぽくする
                            Image(systemName: "waveform.badge.minus")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 32, height: 32)
                                .background(Color.black)
                                .cornerRadius(8)
                            
                            Text("Noise Filter")
                                .font(.system(size: 16))
                        }
                    }
                    .tint(.green) // トグルのON時の色を指定
                    .onChange(of: isNoiseFilterEnabled) {
                        print("Noise Filter: \(isNoiseFilterEnabled)")
                    }
                
                } footer: {
                    Text("録音時の環境ノイズを低減します。\n※現在デコイとしてUIのみ実装中")
                        .font(.system(size: 12))
                }

                // MARK: - その他の設定セクション（今後の拡張用デコイ）
                Section {
                    HStack {
                        Text("Version")
                            .font(.system(size: 16))
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            // タブバーに被らないように下部に余白を追加（CustomTabBarの高さ分）
            .padding(.bottom, 80) 
        }
    }
}
