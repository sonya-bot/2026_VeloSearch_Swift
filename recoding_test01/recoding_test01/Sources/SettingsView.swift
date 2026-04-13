import AudioToolbox
import SwiftUI

// MARK: - 0. Preview(Xcode)
struct SettingsView_Previews: PreviewProvider {
  static var previews: some View {
    SettingsView()
  }
}

// MARK: - 1. データ定義
struct SoundOption: Identifiable {
  let id: Int
  let name: String
}

let soundOptions: [SoundOption] = [
  SoundOption(id: 1052, name: "デフォルト (1052)"),
  SoundOption(id: 1005, name: "アラーム (1005)"),
  SoundOption(id: 1033, name: "チャイム (1033)"),
  SoundOption(id: 1322, name: "警告 (1322)"),
]

struct SettingsView: View {
  // @AppStorageを使うと、状態がUserDefaultsに自動保存され、次回起動時にも維持されます
  @AppStorage("isNoiseFilterEnabled") private var isNoiseFilterEnabled = false
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - 録音設定セクション
        Section {
          Toggle(isOn: $isNoiseFilterEnabled) {
            HStack(spacing: 12) {
              Image(systemName: "waveform.badge.minus")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.green)
                .frame(width: 32, height: 32)
                .background(Color.black)
                .cornerRadius(8)

              Text("Noise Filter")
                .font(.system(size: 16))
            }
          }
          .tint(.green)  // トグルのON時の色を指定
          .onChange(of: isNoiseFilterEnabled) {
            print("Noise Filter: \(isNoiseFilterEnabled)")
          }
          Picker(selection: $selectedSoundID) {
            ForEach(soundOptions, id: \.id) { option in
              Text(option.name).tag(option.id)
            }
          } label: {
            HStack(spacing: 12) {
              Image(systemName: "bell.badge.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(.red)
                .frame(width: 32, height: 32)
                .background(Color.black)
                .cornerRadius(8)

              Text("Arart Sound")
                .font(.system(size: 16))
            }
          }
          // 純正アプリのように、タップすると別画面でリストが開くスタイル
          .pickerStyle(.navigationLink)
          // 選択が変更された瞬間に音を鳴らしてプレビューする
          .onChange(of: selectedSoundID) { oldValue, newValue in
            AudioServicesPlaySystemSound(SystemSoundID(newValue))
          }

        } footer: {
          Text("・録音時の環境ノイズを低減します\n(※現在デコイとしてUIのみ実装中)\n・車両接近検知時に鳴る警告音の種類を選択します")
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
