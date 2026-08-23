import AVFoundation
import Combine
import Foundation

enum InputDeviceOption: String, CaseIterable, Identifiable {
  case builtIn = "iPhone"
  case external = "connected device"

  var id: Self { self }

  var label: String {
    self == .builtIn ? "iPhone" : "External"
  }
}

enum OutputDeviceOption: String, CaseIterable, Identifiable {
  case speaker = "iPhone"
  case external = "connected device"

  var id: Self { self }

  var label: String {
    self == .speaker ? "iPhone" : "External"
  }
}

enum RecordingChannelMode: String, CaseIterable, Identifiable {
  case automatic = "Automatic"
  case mono = "Mono"
  case stereo = "Stereo"

  var id: Self { self }
}

enum DeviceOrientationOption: String, CaseIterable, Identifiable {
  case portrait = "Portrait"
  case landscapeRight = "Landscape"

  var id: Self { self }
}

enum MicSourceOption: String, CaseIterable, Identifiable {
  case back = "Back"
  case front = "Front"

  var id: Self { self }
}

struct ActiveAudioConfiguration: Equatable {
  let inputName: String
  let inputConnection: String
  let outputName: String
  let outputConnection: String
  let sampleRate: Double
  let channelCount: Int
  let isBuiltInInput: Bool
  let orientation: DeviceOrientationOption
  let micSource: MicSourceOption

  var inputIconName: String {
    guard isBuiltInInput else { return "mic.fill" }
    return orientation == .portrait ? "iphone" : "iphone.landscape"
  }

  var outputIconName: String {
    outputConnection == "Bluetooth" ? "hifispeaker.fill" : "speaker.wave.2.fill"
  }

  var channelIconName: String {
    channelCount >= 2 ? "waveform.path.ecg.rectangle" : "waveform"
  }

  var channelLabel: String {
    channelCount >= 2 ? "Stereo" : "Mono"
  }

  var channelDetail: String? {
    guard channelCount >= 2 else { return nil }
    if isBuiltInInput {
      return micSource == .back ? "Back + Bottom" : "Front + Bottom"
    }
    return "L / R"
  }
}

enum AudioIOError: LocalizedError {
  case inputUnavailable(String)
  case inputDataSourceUnavailable(String)
  case stereoUnavailable(Int)

  var errorDescription: String? {
    switch self {
    case .inputUnavailable(let input):
      return "\(input)入力を利用できません。"
    case .inputDataSourceUnavailable(let source):
      return "\(source)マイクを利用できません。"
    case .stereoUnavailable(let channelCount):
      return "Stereo入力を利用できません（入力 \(channelCount)ch）。"
    }
  }
}

@MainActor
final class AudioIOController: ObservableObject {
  @Published private(set) var activeConfiguration: ActiveAudioConfiguration

  private let userDefaults: UserDefaults
  private let audioSession: AVAudioSession

  init(
    userDefaults: UserDefaults = .standard,
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    self.userDefaults = userDefaults
    self.audioSession = audioSession
    self.activeConfiguration = Self.configuration(
      from: audioSession,
      userDefaults: userDefaults
    )
  }

  func refresh() {
    activeConfiguration = Self.configuration(from: audioSession, userDefaults: userDefaults)
  }

  func configurationIssue(
    requiresBuiltInInput: Bool = false,
    requiresStereo: Bool = false,
    allowsPlayback: Bool = false
  ) -> String? {
    let inputOption = selectedInputOption(requiresBuiltInInput: requiresBuiltInInput)
    let inputs = audioSession.availableInputs ?? []
    guard !inputs.isEmpty else { return nil }
    let input = inputs.first {
      inputOption == .builtIn ? $0.portType == .builtInMic : $0.portType != .builtInMic
    }
    guard let input else { return "選択した入力デバイスが接続されていません。" }

    let channelMode = selectedChannelMode(requiresStereo: requiresStereo)
    let maximumChannelCount = audioSession.maximumInputNumberOfChannels
    if channelMode == .stereo && maximumChannelCount > 0 && maximumChannelCount < 2 {
      return "選択した入力ではStereo録音を利用できません。"
    }

    let outputOption = selectedOutputOption(allowsPlayback: allowsPlayback)
    if allowsPlayback && outputOption == .external {
      guard let output = audioSession.currentRoute.outputs.first,
        output.portType != .builtInSpeaker
      else {
        return "外部出力をiOSのオーディオ経路で選択してください。"
      }
      let isBluetoothOutput = [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains(
        output.portType)
      if input.portType == .usbAudio && isBluetoothOutput {
        return "Bluetooth出力とUSB入力の同時使用には対応していません。"
      }
    }
    return nil
  }

  @discardableResult
  func configureForRecording(
    requiresBuiltInInput: Bool = false,
    requiresStereo: Bool = false,
    allowsPlayback: Bool = false
  ) throws -> ActiveAudioConfiguration {
    let inputOption = selectedInputOption(requiresBuiltInInput: requiresBuiltInInput)
    let outputOption = selectedOutputOption(allowsPlayback: allowsPlayback)
    let channelMode = selectedChannelMode(requiresStereo: requiresStereo)

    let options: AVAudioSession.CategoryOptions =
      outputOption == .external ? [.allowBluetoothA2DP] : [.defaultToSpeaker]
    try audioSession.setCategory(.playAndRecord, mode: .measurement, options: options)
    try audioSession.setActive(true)

    if outputOption == .speaker {
      try audioSession.overrideOutputAudioPort(.speaker)
    } else {
      try audioSession.overrideOutputAudioPort(.none)
    }

    let input = try preferredInput(for: inputOption)
    try audioSession.setPreferredInput(input)

    let isBuiltIn = input.portType == .builtInMic
    if isBuiltIn {
      try configureBuiltInDataSource(on: input, channelMode: channelMode)
    }

    let requestedChannels = try requestedChannelCount(
      for: channelMode,
      maximumChannelCount: audioSession.maximumInputNumberOfChannels
    )
    try audioSession.setPreferredInputNumberOfChannels(requestedChannels)

    if isBuiltIn {
      let orientation = selectedOrientation()
      try audioSession.setPreferredInputOrientation(
        orientation == .portrait ? .portrait : .landscapeRight
      )
    }

    refresh()
    return activeConfiguration
  }

  private func selectedInputOption(requiresBuiltInInput: Bool) -> InputDeviceOption {
    if requiresBuiltInInput { return .builtIn }
    let rawValue = userDefaults.string(forKey: "selectedInputDevice")
    return InputDeviceOption(rawValue: rawValue ?? "") ?? .builtIn
  }

  private func selectedOutputOption(allowsPlayback: Bool) -> OutputDeviceOption {
    guard allowsPlayback else { return .speaker }
    let rawValue = userDefaults.string(forKey: "selectedOutputDevice")
    return OutputDeviceOption(rawValue: rawValue ?? "") ?? .speaker
  }

  private func selectedChannelMode(requiresStereo: Bool) -> RecordingChannelMode {
    if requiresStereo { return .stereo }
    let rawValue = userDefaults.string(forKey: "recordingChannelMode")
    return RecordingChannelMode(rawValue: rawValue ?? "") ?? .automatic
  }

  private func selectedOrientation() -> DeviceOrientationOption {
    let rawValue = userDefaults.string(forKey: "deviceOrientation")
    return DeviceOrientationOption(rawValue: rawValue ?? "") ?? .landscapeRight
  }

  private func selectedMicSource() -> MicSourceOption {
    let rawValue = userDefaults.string(forKey: "micSource")
    return MicSourceOption(rawValue: rawValue ?? "") ?? .back
  }

  private func preferredInput(for option: InputDeviceOption) throws -> AVAudioSessionPortDescription
  {
    let inputs = audioSession.availableInputs ?? []
    switch option {
    case .builtIn:
      guard let input = inputs.first(where: { $0.portType == .builtInMic }) else {
        throw AudioIOError.inputUnavailable(option.rawValue)
      }
      return input
    case .external:
      guard let input = inputs.first(where: { $0.portType != .builtInMic }) else {
        throw AudioIOError.inputUnavailable(option.rawValue)
      }
      return input
    }
  }

  private func configureBuiltInDataSource(
    on input: AVAudioSessionPortDescription,
    channelMode: RecordingChannelMode
  ) throws {
    let micSource = selectedMicSource()
    let targetOrientation: AVAudioSession.Orientation = micSource == .back ? .back : .front
    guard
      let dataSource = input.dataSources?.first(where: { $0.orientation == targetOrientation })
    else {
      throw AudioIOError.inputDataSourceUnavailable(micSource.rawValue)
    }
    try input.setPreferredDataSource(dataSource)

    if channelMode != .mono,
      dataSource.supportedPolarPatterns?.contains(.stereo) == true
    {
      try dataSource.setPreferredPolarPattern(.stereo)
    }
  }

  private func requestedChannelCount(
    for mode: RecordingChannelMode,
    maximumChannelCount: Int
  ) throws -> Int {
    switch mode {
    case .automatic:
      return maximumChannelCount >= 2 ? 2 : 1
    case .mono:
      return 1
    case .stereo:
      guard maximumChannelCount >= 2 else {
        throw AudioIOError.stereoUnavailable(maximumChannelCount)
      }
      return 2
    }
  }

  private static func configuration(
    from session: AVAudioSession,
    userDefaults: UserDefaults
  ) -> ActiveAudioConfiguration {
    let input = session.currentRoute.inputs.first
    let output = session.currentRoute.outputs.first
    let inputOption =
      InputDeviceOption(
        rawValue: userDefaults.string(forKey: "selectedInputDevice") ?? ""
      ) ?? .builtIn
    let orientation =
      DeviceOrientationOption(
        rawValue: userDefaults.string(forKey: "deviceOrientation") ?? ""
      ) ?? .landscapeRight
    let micSource =
      MicSourceOption(
        rawValue: userDefaults.string(forKey: "micSource") ?? ""
      ) ?? .back
    let isBuiltIn = input?.portType == .builtInMic || (input == nil && inputOption == .builtIn)

    return ActiveAudioConfiguration(
      inputName: input?.portName ?? inputOption.label,
      inputConnection: connectionLabel(for: input?.portType, fallback: inputOption.label),
      outputName: output?.portName ?? "iPhone",
      outputConnection: connectionLabel(for: output?.portType, fallback: "iPhone"),
      sampleRate: session.sampleRate,
      channelCount: max(Int(session.inputNumberOfChannels), 1),
      isBuiltInInput: isBuiltIn,
      orientation: orientation,
      micSource: micSource
    )
  }

  private static func connectionLabel(
    for portType: AVAudioSession.Port?,
    fallback: String
  ) -> String {
    switch portType {
    case .builtInMic, .builtInSpeaker: return "iPhone"
    case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE: return "Bluetooth"
    case .usbAudio: return "USB"
    case .headphones, .headsetMic, .lineIn, .lineOut: return "Wired"
    case .airPlay: return "AirPlay"
    case .none: return fallback
    default: return "External"
    }
  }
}
