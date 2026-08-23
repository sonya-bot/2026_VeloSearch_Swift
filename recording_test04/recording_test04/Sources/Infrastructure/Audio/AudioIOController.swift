import AVFoundation
import Combine
import Foundation

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
    let inputIsAvailable = inputs.contains {
      inputOption == .builtIn ? $0.portType == .builtInMic : $0.portType != .builtInMic
    }
    guard inputIsAvailable else { return "選択した入力デバイスが接続されていません。" }

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
