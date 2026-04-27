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

enum DeviceOrientationOption: String, CaseIterable, Identifiable {
  case portrait = "縦"
  case landscapeRight = "横"
  var id: String { self.rawValue }
}

enum MicSourceOption: String, CaseIterable, Identifiable {
  case back = "背面"
  case front = "前面"
  var id: String { self.rawValue }
}

// MARK: - アイコン用コンポーネント
struct SettingsIconView: View {
  let systemName: String
  let color: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 14, weight: .semibold))
      .foregroundColor(.white)  // 背景色に対して常に白なので、テーマ問わず視認性が高い
      .frame(width: 28, height: 28)
      .background(color)
      .cornerRadius(6)
  }
}

// MARK: - 2. SettingsView UI (メイン画面)
struct SettingsView: View {
  @AppStorage("isNoiseFilterEnabled") private var isNoiseFilterEnabled = false
  @AppStorage("warningSoundID") private var selectedSoundID: Int = 1052
  @AppStorage("deviceOrientation") private var selectedOrientation: DeviceOrientationOption =
    .landscapeRight
  @AppStorage("micSource") private var selectedMicSource: MicSourceOption = .back

  var body: some View {
    NavigationStack {
      Form {
        // MARK: - 一般設定セクション
        Section {
          Toggle(isOn: $isNoiseFilterEnabled) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "waveform.badge.minus", color: .green)
              Text("Noise Filter")
                .font(.system(size: 16))
            }
          }
          .tint(.green)

          Picker(selection: $selectedSoundID) {
            ForEach(soundOptions, id: \.id) { option in
              Text(option.name).tag(option.id)
            }
          } label: {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "bell.badge.fill", color: .red)
              Text("Alert Sound")
                .font(.system(size: 16))
            }
          }
          .pickerStyle(.navigationLink)
          .onChange(of: selectedSoundID) { oldValue, newValue in
            AudioServicesPlaySystemSound(SystemSoundID(newValue))
          }
        } header: {
          Text("General Settings")
        } footer: {
          Text("・録音時の環境ノイズを低減します(デコイ)\n・車両接近検知時の警告音を選択します")
            .font(.system(size: 12))
        }

        // MARK: - 録音設定セクション
        Section {
          // 端末の向き設定
          Picker(selection: $selectedOrientation) {
            ForEach(DeviceOrientationOption.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          } label: {
            HStack(spacing: 12) {
              SettingsIconView(
                systemName: selectedOrientation == .portrait
                  ? "rectangle.portrait.rotate" : "rectangle.landscape.rotate", color: .blue
              )
              Text("端末の向き")
            }
          }

          // ペアマイク設定（タップで別画面へ遷移）
          NavigationLink(destination: MicSourceSettingView()) {
            HStack(spacing: 12) {
              SettingsIconView(systemName: "mic.fill", color: .orange)
              Text("ペアマイク")
              Spacer()
              Text(selectedMicSource.rawValue)
                .foregroundColor(.secondary)
            }
          }
        } header: {
          Text("Recording Settings")
        }

        // MARK: - Aboutセクション
        Section {
          HStack {
            Text("Version")
              .font(.system(size: 16))
            Spacer()
            Text("2.1.0")
              .foregroundColor(.secondary)
          }
        } header: {
          Text("About")
        }
      }
      .navigationTitle("Settings")
    }
  }
}

// MARK: - 3. ペアマイク専用設定画面 (サブビュー)
struct MicSourceSettingView: View {
  @AppStorage("micSource") private var selectedMicSource: MicSourceOption = .back
  @AppStorage("deviceOrientation") private var selectedOrientation: DeviceOrientationOption =
    .landscapeRight

  var body: some View {
    Form {
      // 選択セクション
      Section {
        ForEach(MicSourceOption.allCases) { option in
          Button(action: {
            selectedMicSource = option
          }) {
            HStack {
              Text(option.rawValue)
                .foregroundColor(.primary)
              Spacer()
              if selectedMicSource == option {
                Image(systemName: "checkmark")
                  .foregroundColor(.blue)
              }
            }
          }
        }
      } header: {
        Text("ペアマイクの選択")
      }

      // プレビューセクション
      Section {
        VStack(alignment: .leading, spacing: 10) {
          ZStack {
            // マイク構成を中央に配置
            HStack(spacing: 15) {
              VStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.title2).foregroundColor(.blue)
                Text("底面").font(.subheadline).bold()
              }
              .frame(width: 70)

              Image(systemName: "plus").font(.body).foregroundColor(.secondary)

              VStack(spacing: 6) {
                Image(systemName: "mic.fill").font(.title2).foregroundColor(.green)
                Text(selectedMicSource == .back ? "背面" : "前面").font(.subheadline).bold()
              }
              .frame(width: 70)
            }

            // iPhoneアイコンを右端に配置
            // HStack {
            //   Spacer()
            //   Image(
            //     systemName: selectedOrientation == .portrait
            //       ? "iphone.portrait" : "iphone.landscape"
            //   )
            //   .font(.title3)
            //   .foregroundColor(.secondary)
            //   .padding(.trailing, 5)
            // }
          }
          .padding(.vertical, 8)
        }
      } header: {
        Text("Mic Preview")
      }
    }
    .navigationTitle("ペアマイク")
    .navigationBarTitleDisplayMode(.inline)
  }
}
