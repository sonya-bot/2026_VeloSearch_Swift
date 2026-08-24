import AVFoundation

enum AudioIOConfigurationInspector {
  static func configuration(
    from session: AVAudioSession,
    selection: AudioIOSelection
  ) -> ActiveAudioConfiguration {
    let input = session.currentRoute.inputs.first
    let output = session.currentRoute.outputs.first
    let isBuiltIn =
      input?.portType == .builtInMic || (input == nil && selection.inputDevice == .builtIn)

    return ActiveAudioConfiguration(
      inputName: input?.portName ?? selection.inputDevice.label,
      inputConnection: connectionLabel(
        for: input?.portType,
        fallback: selection.inputDevice.label
      ),
      outputName: output?.portName ?? "iPhone",
      outputConnection: connectionLabel(for: output?.portType, fallback: "iPhone"),
      sampleRate: session.sampleRate,
      channelCount: max(Int(session.inputNumberOfChannels), 1),
      isBuiltInInput: isBuiltIn,
      orientation: selection.orientation,
      micSource: selection.micSource
    )
  }

  static func validate(
    session: AVAudioSession,
    selection: AudioIOSelection,
    allowsPlayback: Bool
  ) throws {
    guard let input = session.currentRoute.inputs.first else {
      throw AudioIOError.configurationNotEstablished("入力経路なし")
    }
    let hasExpectedInput =
      selection.inputDevice == .builtIn
      ? input.portType == .builtInMic
      : input.portType != .builtInMic
    guard hasExpectedInput else {
      throw AudioIOError.configurationNotEstablished("入力デバイス不一致")
    }

    if allowsPlayback {
      try validateOutput(session: session, selection: selection)
    }

    try validateChannelCount(session: session, channelMode: selection.channelMode)
    try validateBuiltInMicrophone(input: input, selection: selection)
  }

  private static func validateOutput(
    session: AVAudioSession,
    selection: AudioIOSelection
  ) throws {
    guard let output = session.currentRoute.outputs.first else {
      throw AudioIOError.configurationNotEstablished("出力経路なし")
    }
    let hasExpectedOutput =
      selection.outputDevice == .speaker
      ? output.portType == .builtInSpeaker
      : output.portType != .builtInSpeaker
    guard hasExpectedOutput else {
      throw AudioIOError.configurationNotEstablished("出力デバイス不一致")
    }
  }

  private static func validateChannelCount(
    session: AVAudioSession,
    channelMode: RecordingChannelMode
  ) throws {
    let actualChannelCount = session.inputNumberOfChannels
    if channelMode == .stereo, actualChannelCount < 2 {
      throw AudioIOError.configurationNotEstablished("Stereo入力が1chで成立")
    }
    if channelMode == .mono, actualChannelCount != 1 {
      throw AudioIOError.configurationNotEstablished("Mono入力が\(actualChannelCount)chで成立")
    }
  }

  private static func validateBuiltInMicrophone(
    input: AVAudioSessionPortDescription,
    selection: AudioIOSelection
  ) throws {
    guard selection.inputDevice == .builtIn else { return }
    let expectedDataSourceOrientation: AVAudioSession.Orientation =
      selection.micSource == .back ? .back : .front
    guard input.selectedDataSource?.orientation == expectedDataSourceOrientation else {
      throw AudioIOError.configurationNotEstablished("マイク構成不一致")
    }
    if selection.channelMode == .stereo,
      input.selectedDataSource?.selectedPolarPattern != .stereo
    {
      throw AudioIOError.configurationNotEstablished("Stereoマイク構成不一致")
    }
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
