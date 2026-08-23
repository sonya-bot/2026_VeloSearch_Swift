import SwiftUI

struct MonitoringSettingView: View {
  @AppStorage(SettingsStorageKey.isMonitoringEnabled) private var isMonitoringEnabled = false

  var body: some View {
    Form {
      Section {
        VStack(alignment: .leading, spacing: 16) {
          Image(systemName: "headphones")
            .font(.system(size: 36))
            .foregroundStyle(.white)
            .frame(width: 64, height: 64)
            .background(.pink, in: RoundedRectangle(cornerRadius: 16))

          Text("モニタリング")
            .font(.title2.bold())

          Text(
            "スピーカーからの音声をリアルタイムで録音します。\n"
              + "ハウリング防止のため、有線イヤホンやヘッドフォンの接続を強く推奨します。"
          )
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
      }

      Section {
        Toggle(isOn: $isMonitoringEnabled) {
          SettingsRowLabel(
            systemName: "headphones",
            color: .pink,
            title: "モニタリング機能"
          )
        }
      }
    }
    .navigationTitle("モニタリング")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
  }
}
