import SwiftUI

struct AudioIOSettingsView: View {
  @ObservedObject var audioIOController: AudioIOController
  @AppStorage("selectedInputDevice") private var inputDevice: InputDeviceOption = .builtIn
  @AppStorage("selectedOutputDevice") private var outputDevice: OutputDeviceOption = .speaker
  @AppStorage("recordingChannelMode") private var channelMode: RecordingChannelMode = .automatic
  @AppStorage("deviceOrientation") private var orientation: DeviceOrientationOption =
    .landscapeRight
  @AppStorage("micSource") private var micSource: MicSourceOption = .back

  var body: some View {
    Form {
      Section("Current Route") {
        routeRow(
          title: "Output",
          value: audioIOController.activeConfiguration.outputConnection,
          systemImage: audioIOController.activeConfiguration.outputIconName
        )
        routeRow(
          title: "Input",
          value: audioIOController.activeConfiguration.inputConnection,
          systemImage: audioIOController.activeConfiguration.inputIconName
        )
        routeRow(
          title: "Format",
          value: effectiveFormatDescription,
          systemImage: audioIOController.activeConfiguration.channelIconName
        )
      }

      Section {
        Picker("出力デバイス", selection: $outputDevice) {
          ForEach(OutputDeviceOption.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.navigationLink)
      } header: {
        Text("Output")
      } footer: {
        Text("Bluetoothなどの出力先は、iOSで現在選択されている経路を使用します。")
      }

      Section {
        Picker("入力デバイス", selection: $inputDevice) {
          ForEach(InputDeviceOption.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.navigationLink)

        Picker("録音形式", selection: $channelMode) {
          ForEach(RecordingChannelMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.navigationLink)

        if inputDevice == .builtIn {
          Picker("入力方向", selection: $orientation) {
            ForEach(DeviceOrientationOption.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.navigationLink)

          if channelMode == .stereo {
            NavigationLink(destination: MicSourceSettingView()) {
              HStack {
                Text("マイク構成")
                Spacer()
                Text(microphoneConfigurationLabel)
                  .foregroundStyle(.secondary)
              }
            }
          }
        }
      } header: {
        Text("Input")
      } footer: {
        Text("実行時には、接続機器で実際に成立したチャンネル数を優先します。")
      }
    }
    .navigationTitle("Audio Input / Output")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .onAppear {
      audioIOController.refresh()
    }
  }

  private var effectiveFormatDescription: String {
    let configuration = audioIOController.activeConfiguration
    if let detail = configuration.channelDetail {
      return "\(configuration.channelLabel) · \(detail)"
    }
    return configuration.channelLabel
  }

  private var microphoneConfigurationLabel: String {
    micSource == .back ? "Back + Bottom" : "Front + Bottom"
  }

  private func routeRow(title: String, value: String, systemImage: String) -> some View {
    HStack(spacing: 12) {
      Image(systemName: systemImage)
        .frame(width: 24)
      Text(title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
    }
  }
}
