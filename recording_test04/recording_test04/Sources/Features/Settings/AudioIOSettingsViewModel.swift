import Combine
import Foundation

@MainActor
final class AudioIOSettingsViewModel: ObservableObject {
  @Published private(set) var selection: AudioIOSelection
  @Published private(set) var isApplying = false
  @Published private(set) var errorMessage: String?

  private let audioIOController: AudioIOController
  private var confirmedSelection: AudioIOSelection
  private var applicationTask: Task<Void, Never>?

  init(audioIOController: AudioIOController) {
    self.audioIOController = audioIOController
    let storedSelection = audioIOController.storedSelection
    self.selection = storedSelection
    self.confirmedSelection = storedSelection
  }

  deinit {
    applicationTask?.cancel()
  }

  func applyStoredSelectionIfNeeded() async {
    guard audioIOController.configurationStatus == .unverified else { return }
    isApplying = true
    await audioIOController.applyStoredSelection()
    errorMessage = audioIOController.configurationStatus.message
    isApplying = false
  }

  func selectInputDevice(_ inputDevice: InputDeviceOption) {
    applyChange { $0.inputDevice = inputDevice }
  }

  func selectOutputDevice(_ outputDevice: OutputDeviceOption) {
    applyChange { $0.outputDevice = outputDevice }
  }

  func selectChannelMode(_ channelMode: RecordingChannelMode) {
    applyChange { $0.channelMode = channelMode }
  }

  func selectOrientation(_ orientation: DeviceOrientationOption) {
    applyChange { $0.orientation = orientation }
  }

  func selectMicSource(_ micSource: MicSourceOption) {
    applyChange { $0.micSource = micSource }
  }

  private func applyChange(_ updateSelection: (inout AudioIOSelection) -> Void) {
    guard !isApplying else { return }
    var candidate = confirmedSelection
    updateSelection(&candidate)
    guard candidate != confirmedSelection else { return }

    selection = candidate
    isApplying = true
    errorMessage = nil
    applicationTask = Task { [weak self] in
      guard let self else { return }
      let wasApplied = await audioIOController.apply(candidate)
      guard !Task.isCancelled else { return }

      if wasApplied {
        confirmedSelection = candidate
      } else {
        selection = confirmedSelection
        errorMessage = audioIOController.configurationStatus.message
      }
      isApplying = false
    }
  }
}
