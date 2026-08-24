import SwiftUI

struct AudioIOSettingsView: View {
  @ObservedObject private var audioIOController: AudioIOController
  @StateObject private var viewModel: AudioIOSettingsViewModel

  init(audioIOController: AudioIOController) {
    self.audioIOController = audioIOController
    _viewModel = StateObject(
      wrappedValue: AudioIOSettingsViewModel(audioIOController: audioIOController)
    )
  }

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
        Picker("出力デバイス", selection: outputDeviceBinding) {
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
        Picker("入力デバイス", selection: inputDeviceBinding) {
          ForEach(InputDeviceOption.allCases) { option in
            Text(option.label).tag(option)
          }
        }
        .pickerStyle(.navigationLink)

        Picker("録音形式", selection: channelModeBinding) {
          ForEach(RecordingChannelMode.allCases) { mode in
            Text(mode.rawValue).tag(mode)
          }
        }
        .pickerStyle(.navigationLink)

        if viewModel.selection.inputDevice == .builtIn {
          Picker("入力方向", selection: orientationBinding) {
            ForEach(DeviceOrientationOption.allCases) { option in
              Text(option.rawValue).tag(option)
            }
          }
          .pickerStyle(.navigationLink)

          if viewModel.selection.channelMode == .stereo {
            NavigationLink(
              destination: MicSourceSettingView(
                selectedMicSource: micSourceBinding,
                isEnabled: !viewModel.isApplying
              )
            ) {
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
        VStack(alignment: .leading, spacing: 4) {
          Text("変更時に実機へ適用し、成立した設定だけを保存します。")
          if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
              .foregroundStyle(.red)
          }
        }
      }
    }
    .navigationTitle("Audio Input / Output")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .disabled(viewModel.isApplying)
    .task {
      await viewModel.applyStoredSelectionIfNeeded()
    }
  }

  private var effectiveFormatDescription: String {
    let configuration = audioIOController.activeConfiguration
    switch audioIOController.configurationStatus {
    case .unverified:
      return "未確認"
    case .applying:
      return "確認中"
    case .unavailable:
      return "利用不可"
    case .ready, .rejected:
      break
    }
    if let detail = configuration.channelDetail {
      return "\(configuration.channelLabel) · \(detail)"
    }
    return configuration.channelLabel
  }

  private var microphoneConfigurationLabel: String {
    viewModel.selection.micSource == .back ? "Back + Bottom" : "Front + Bottom"
  }

  private var inputDeviceBinding: Binding<InputDeviceOption> {
    Binding(
      get: { viewModel.selection.inputDevice },
      set: viewModel.selectInputDevice
    )
  }

  private var outputDeviceBinding: Binding<OutputDeviceOption> {
    Binding(
      get: { viewModel.selection.outputDevice },
      set: viewModel.selectOutputDevice
    )
  }

  private var channelModeBinding: Binding<RecordingChannelMode> {
    Binding(
      get: { viewModel.selection.channelMode },
      set: viewModel.selectChannelMode
    )
  }

  private var orientationBinding: Binding<DeviceOrientationOption> {
    Binding(
      get: { viewModel.selection.orientation },
      set: viewModel.selectOrientation
    )
  }

  private var micSourceBinding: Binding<MicSourceOption> {
    Binding(
      get: { viewModel.selection.micSource },
      set: viewModel.selectMicSource
    )
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
