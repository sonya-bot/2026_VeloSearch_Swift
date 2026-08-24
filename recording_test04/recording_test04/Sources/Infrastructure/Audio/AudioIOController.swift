import AVFoundation
import Combine
import Foundation

@MainActor
final class AudioIOController: ObservableObject {
  @Published private(set) var activeConfiguration: ActiveAudioConfiguration
  @Published private(set) var configurationStatus = AudioIOConfigurationStatus.unverified

  private let selectionStore: AudioIOSelectionStore
  private let audioSession: AVAudioSession
  private var configurationLockCount = 0

  init(
    userDefaults: UserDefaults = .standard,
    audioSession: AVAudioSession = .sharedInstance()
  ) {
    let selectionStore = AudioIOSelectionStore(userDefaults: userDefaults)
    self.selectionStore = selectionStore
    self.audioSession = audioSession
    self.activeConfiguration = AudioIOConfigurationInspector.configuration(
      from: audioSession,
      selection: selectionStore.selection
    )
  }

  func refresh() {
    guard configurationStatus != .applying else { return }
    let selection = storedSelection
    activeConfiguration = AudioIOConfigurationInspector.configuration(
      from: audioSession,
      selection: selection
    )
    do {
      try validateEstablishedConfiguration(for: selection, allowsPlayback: true)
      configurationStatus = .ready
    } catch {
      configurationStatus = .unavailable(error.localizedDescription)
    }
  }

  var storedSelection: AudioIOSelection {
    selectionStore.selection
  }

  func applyStoredSelection() async {
    _ = await apply(storedSelection)
  }

  @discardableResult
  func apply(_ selection: AudioIOSelection) async -> Bool {
    guard configurationLockCount == 0 else {
      configurationStatus = .rejected(AudioIOError.configurationLocked.localizedDescription)
      return false
    }

    let previousSelection = storedSelection
    configurationStatus = .applying
    await Task.yield()

    do {
      _ = try configure(selection: selection, allowsPlayback: true)
      try await waitForEstablishedConfiguration(
        selection: selection,
        allowsPlayback: true
      )
      selectionStore.save(selection)
      configurationStatus = .ready
      return true
    } catch {
      let applicationError = error
      do {
        _ = try configure(selection: previousSelection, allowsPlayback: true)
        try await waitForEstablishedConfiguration(
          selection: previousSelection,
          allowsPlayback: true
        )
        configurationStatus = .rejected(applicationError.localizedDescription)
      } catch {
        activeConfiguration = AudioIOConfigurationInspector.configuration(
          from: audioSession,
          selection: previousSelection
        )
        configurationStatus = .unavailable(applicationError.localizedDescription)
      }
      return false
    }
  }

  func configurationIssue(
    requiresBuiltInInput: Bool = false,
    requiresStereo: Bool = false,
    allowsPlayback: Bool = false
  ) -> String? {
    let selection = storedSelection
    let inputOption = requiresBuiltInInput ? InputDeviceOption.builtIn : selection.inputDevice
    let inputs = audioSession.availableInputs ?? []
    guard !inputs.isEmpty else { return nil }
    let inputIsAvailable = inputs.contains {
      inputOption == .builtIn ? $0.portType == .builtInMic : $0.portType != .builtInMic
    }
    guard inputIsAvailable else { return "選択した入力デバイスが接続されていません。" }

    let channelMode = requiresStereo ? RecordingChannelMode.stereo : selection.channelMode
    let maximumChannelCount = audioSession.maximumInputNumberOfChannels
    if channelMode == .stereo && maximumChannelCount > 0 && maximumChannelCount < 2 {
      return "選択した入力ではStereo録音を利用できません。"
    }

    let outputOption = allowsPlayback ? selection.outputDevice : .speaker
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
    var selection = storedSelection
    if requiresBuiltInInput {
      selection.inputDevice = .builtIn
    }
    if requiresStereo {
      selection.channelMode = .stereo
    }
    if !allowsPlayback {
      selection.outputDevice = .speaker
    }

    let configuration = try configure(selection: selection, allowsPlayback: allowsPlayback)
    try validateEstablishedConfiguration(for: selection, allowsPlayback: allowsPlayback)
    configurationStatus = .ready
    return configuration
  }

  func lockConfiguration() {
    configurationLockCount += 1
  }

  func unlockConfiguration() {
    configurationLockCount = max(configurationLockCount - 1, 0)
  }

  private func configure(
    selection: AudioIOSelection,
    allowsPlayback: Bool
  ) throws -> ActiveAudioConfiguration {
    let inputOption = selection.inputDevice
    let outputOption = allowsPlayback ? selection.outputDevice : .speaker
    let channelMode = selection.channelMode

    let options: AVAudioSession.CategoryOptions =
      outputOption == .external ? [.allowBluetoothA2DP] : [.defaultToSpeaker]
    let sessionMode: AVAudioSession.Mode = inputOption == .builtIn ? .default : .measurement
    try audioSession.setCategory(.playAndRecord, mode: sessionMode, options: options)
    try audioSession.setActive(true)

    if outputOption == .speaker {
      try audioSession.overrideOutputAudioPort(.speaker)
    } else {
      try audioSession.overrideOutputAudioPort(.none)
    }

    let input = try preferredInput(for: inputOption)
    let isBuiltIn = input.portType == .builtInMic
    if isBuiltIn {
      try configureBuiltInDataSource(
        on: input,
        channelMode: channelMode,
        micSource: selection.micSource
      )
    }
    try audioSession.setPreferredInput(input)

    let requestedChannels = try requestedChannelCount(
      for: channelMode,
      maximumChannelCount: audioSession.maximumInputNumberOfChannels
    )
    try audioSession.setPreferredInputNumberOfChannels(requestedChannels)

    if isBuiltIn {
      try audioSession.setPreferredInputOrientation(
        selection.orientation == .portrait ? .portrait : .landscapeRight
      )
    }

    activeConfiguration = AudioIOConfigurationInspector.configuration(
      from: audioSession,
      selection: selection
    )
    return activeConfiguration
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
    channelMode: RecordingChannelMode,
    micSource: MicSourceOption
  ) throws {
    let targetOrientation: AVAudioSession.Orientation = micSource == .back ? .back : .front
    guard
      let dataSource = input.dataSources?.first(where: { $0.orientation == targetOrientation })
    else {
      throw AudioIOError.inputDataSourceUnavailable(micSource.rawValue)
    }
    try input.setPreferredDataSource(dataSource)

    if channelMode != .mono {
      guard dataSource.supportedPolarPatterns?.contains(.stereo) == true else {
        if channelMode == .stereo {
          throw AudioIOError.stereoPolarPatternUnavailable(micSource.rawValue)
        }
        return
      }
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

  private func validateEstablishedConfiguration(
    for selection: AudioIOSelection,
    allowsPlayback: Bool
  ) throws {
    try AudioIOConfigurationInspector.validate(
      session: audioSession,
      selection: selection,
      allowsPlayback: allowsPlayback
    )
  }

  private func waitForEstablishedConfiguration(
    selection: AudioIOSelection,
    allowsPlayback: Bool
  ) async throws {
    let deadline = Date().addingTimeInterval(1)
    var lastValidationError: Error?

    repeat {
      try Task.checkCancellation()
      activeConfiguration = AudioIOConfigurationInspector.configuration(
        from: audioSession,
        selection: selection
      )
      do {
        try validateEstablishedConfiguration(
          for: selection,
          allowsPlayback: allowsPlayback
        )
        return
      } catch {
        lastValidationError = error
      }
      try await Task.sleep(nanoseconds: 100_000_000)
    } while Date() < deadline

    throw lastValidationError
      ?? AudioIOError.configurationNotEstablished("経路確定タイムアウト")
  }
}
