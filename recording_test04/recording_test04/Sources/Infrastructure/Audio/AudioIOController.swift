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
  private var routeChangeCancellable: AnyCancellable?
  private var routeChangeTask: Task<Void, Never>?

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
    routeChangeCancellable = NotificationCenter.default.publisher(
      for: AVAudioSession.routeChangeNotification
    )
    .sink { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.scheduleRouteValidation()
      }
    }
  }

  var storedSelection: AudioIOSelection {
    selectionStore.selection
  }

  var availableInputDevices: [AudioInputDevice] {
    (audioSession.availableInputs ?? []).map { input in
      AudioInputDevice(
        id: input.uid,
        name: input.portName,
        connection: AudioIOConfigurationInspector.inputOption(for: input.portType)
      )
    }
  }

  var currentOutputRouteUID: String? {
    audioSession.currentRoute.outputs.first?.uid
  }

  func refresh() {
    guard configurationStatus != .applying else { return }
    updateStatus(for: storedSelection)
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
      let appliedSelection = try configure(selection: selection)
      try await waitForEstablishedConfiguration(
        selection: appliedSelection,
        allowsPlayback: appliedSelection.outputDevice == .speaker
      )
      selectionStore.save(appliedSelection)
      updateStatus(for: appliedSelection)
      return true
    } catch {
      let applicationError = error
      await restore(previousSelection: previousSelection, applicationError: applicationError)
      return false
    }
  }

  func adoptCurrentOutputRoute() {
    guard configurationLockCount == 0, let output = audioSession.currentRoute.outputs.first else {
      return
    }
    var selection = storedSelection
    selection.outputDevice = AudioIOConfigurationInspector.outputOption(for: output.portType)
    selection.outputDeviceUID = output.uid
    selectionStore.save(selection)
    updateStatus(for: selection)
  }

  func configurationIssue(
    requiresBuiltInInput: Bool = false,
    requiresStereo: Bool = false,
    allowsPlayback: Bool = false
  ) -> String? {
    let selection = requiredSelection(
      requiresBuiltInInput: requiresBuiltInInput,
      requiresStereo: requiresStereo
    )
    do {
      try validateEstablishedConfiguration(for: selection, allowsPlayback: allowsPlayback)
      return nil
    } catch {
      return error.localizedDescription
    }
  }

  @discardableResult
  func configureForRecording(
    requiresBuiltInInput: Bool = false,
    requiresStereo: Bool = false,
    allowsPlayback: Bool = false
  ) throws -> ActiveAudioConfiguration {
    let selection = requiredSelection(
      requiresBuiltInInput: requiresBuiltInInput,
      requiresStereo: requiresStereo
    )
    try validateEstablishedConfiguration(for: selection, allowsPlayback: allowsPlayback)
    activeConfiguration = AudioIOConfigurationInspector.configuration(
      from: audioSession,
      selection: selection
    )
    if allowsPlayback {
      configurationStatus = .ready
    }
    return activeConfiguration
  }

  func lockConfiguration() {
    configurationLockCount += 1
  }

  func unlockConfiguration() {
    configurationLockCount = max(configurationLockCount - 1, 0)
  }

  private func configure(selection: AudioIOSelection) throws -> AudioIOSelection {
    let options = categoryOptions(for: selection.outputDevice)
    let sessionMode: AVAudioSession.Mode =
      selection.inputDevice == .builtIn ? .default : .measurement
    try audioSession.setCategory(.playAndRecord, mode: sessionMode, options: options)
    try audioSession.setActive(true)

    if selection.outputDevice == .speaker {
      try audioSession.overrideOutputAudioPort(.speaker)
    } else {
      try audioSession.overrideOutputAudioPort(.none)
    }

    let input = try preferredInput(for: selection)
    var appliedSelection = selection
    appliedSelection.inputDevice = AudioIOConfigurationInspector.inputOption(
      for: input.portType
    )
    appliedSelection.inputDeviceUID = input.uid

    let isBuiltIn = input.portType == .builtInMic
    if isBuiltIn {
      try configureBuiltInDataSource(
        on: input,
        channelMode: selection.channelMode,
        micSource: selection.micSource
      )
    }
    try audioSession.setPreferredInput(input)

    let requestedChannels = try requestedChannelCount(
      for: selection.channelMode,
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
      selection: appliedSelection
    )
    return appliedSelection
  }

  private func categoryOptions(
    for outputDevice: OutputDeviceOption
  ) -> AVAudioSession.CategoryOptions {
    var options: AVAudioSession.CategoryOptions = [.allowBluetoothA2DP]
    if outputDevice == .speaker {
      options.insert(.defaultToSpeaker)
    }
    return options
  }

  private func preferredInput(
    for selection: AudioIOSelection
  ) throws -> AVAudioSessionPortDescription {
    let inputs = audioSession.availableInputs ?? []
    if let inputDeviceUID = selection.inputDeviceUID,
      let input = inputs.first(where: { $0.uid == inputDeviceUID })
    {
      return input
    }

    let input = inputs.first { candidate in
      let candidateOption = AudioIOConfigurationInspector.inputOption(for: candidate.portType)
      return candidateOption == selection.inputDevice
        || selection.inputDevice == .external && candidate.portType != .builtInMic
    }
    guard let input else {
      throw AudioIOError.inputUnavailable(selection.inputDevice.label)
    }
    return input
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

    if channelMode == .mono {
      try dataSource.setPreferredPolarPattern(nil)
      return
    }
    guard dataSource.supportedPolarPatterns?.contains(.stereo) == true else {
      if channelMode == .stereo {
        throw AudioIOError.stereoPolarPatternUnavailable(micSource.rawValue)
      }
      return
    }
    try dataSource.setPreferredPolarPattern(.stereo)
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

  private func requiredSelection(
    requiresBuiltInInput: Bool,
    requiresStereo: Bool
  ) -> AudioIOSelection {
    var selection = storedSelection
    if requiresBuiltInInput {
      selection.inputDevice = .builtIn
      selection.inputDeviceUID = nil
    }
    if requiresStereo {
      selection.channelMode = .stereo
    }
    return selection
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

  private func updateStatus(for selection: AudioIOSelection) {
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

  private func restore(
    previousSelection: AudioIOSelection,
    applicationError: Error
  ) async {
    do {
      let restoredSelection = try configure(selection: previousSelection)
      try await waitForEstablishedConfiguration(
        selection: restoredSelection,
        allowsPlayback: restoredSelection.outputDevice == .speaker
      )
      selectionStore.save(restoredSelection)
      activeConfiguration = AudioIOConfigurationInspector.configuration(
        from: audioSession,
        selection: restoredSelection
      )
      configurationStatus = .rejected(applicationError.localizedDescription)
    } catch {
      activeConfiguration = AudioIOConfigurationInspector.configuration(
        from: audioSession,
        selection: previousSelection
      )
      configurationStatus = .unavailable(applicationError.localizedDescription)
    }
  }

  private func scheduleRouteValidation() {
    routeChangeTask?.cancel()
    routeChangeTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 250_000_000)
      guard let self, !Task.isCancelled else { return }
      refresh()
      guard configurationLockCount > 0, configurationStatus != .ready else { return }
      NotificationCenter.default.post(name: .audioIORouteBecameInvalid, object: self)
    }
  }
}
