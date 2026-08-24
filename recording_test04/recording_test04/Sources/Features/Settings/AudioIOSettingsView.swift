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
          value: outputRouteDescription,
          systemImage: audioIOController.activeConfiguration.outputIconName
        )
        routeRow(
          title: "Input",
          value: inputRouteDescription,
          systemImage: audioIOController.activeConfiguration.inputIconName
        )
        routeRow(
          title: "Format",
          value: effectiveFormatDescription,
          systemImage: audioIOController.activeConfiguration.channelIconName
        )
      }

      Section {
        HStack {
          Text("出力デバイス")
          Spacer()
          SystemAudioRoutePicker(
            onRouteSelectionStarted: viewModel.outputRouteSelectionStarted,
            onRouteSelectionCompleted: viewModel.outputRouteSelectionCompleted
          )
            .frame(width: 44, height: 36)
        }
      } header: {
        Text("Output")
      } footer: {
        Text("システムの出力一覧からiPhone、USB、Bluetoothを選択します。")
      }

      Section {
        Picker("入力デバイス", selection: inputDeviceBinding) {
          ForEach(audioIOController.availableInputDevices) { device in
            Text(device.label).tag(Optional(device.id))
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

  private var inputRouteDescription: String {
    routeDescription(
      connection: audioIOController.activeConfiguration.inputConnection,
      name: audioIOController.activeConfiguration.inputName
    )
  }

  private var outputRouteDescription: String {
    routeDescription(
      connection: audioIOController.activeConfiguration.outputConnection,
      name: audioIOController.activeConfiguration.outputName
    )
  }

  private var inputDeviceBinding: Binding<String?> {
    Binding(
      get: { viewModel.selection.inputDeviceUID },
      set: { inputDeviceID in
        guard let inputDeviceID else { return }
        viewModel.selectInputDevice(withID: inputDeviceID)
      }
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

  private func routeDescription(connection: String, name: String) -> String {
    connection == name ? connection : "\(connection) · \(name)"
  }
}
