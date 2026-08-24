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
  private var outputRouteConfirmationTask: Task<Void, Never>?
  private var outputRouteUIDBeforeSelection: String?

  init(audioIOController: AudioIOController) {
    self.audioIOController = audioIOController
    let storedSelection = audioIOController.storedSelection
    self.selection = storedSelection
    self.confirmedSelection = storedSelection
  }

  deinit {
    applicationTask?.cancel()
    outputRouteConfirmationTask?.cancel()
  }

  func applyStoredSelectionIfNeeded() async {
    guard audioIOController.configurationStatus == .unverified else { return }
    isApplying = true
    await audioIOController.applyStoredSelection()
    let storedSelection = audioIOController.storedSelection
    selection = storedSelection
    confirmedSelection = storedSelection
    errorMessage = audioIOController.configurationStatus.message
    isApplying = false
  }

  func selectInputDevice(withID inputDeviceID: String) {
    guard
      let inputDevice = audioIOController.availableInputDevices.first(where: {
        $0.id == inputDeviceID
      })
    else {
      errorMessage = "選択した入力デバイスが接続されていません。"
      return
    }
    applyChange {
      $0.inputDevice = inputDevice.connection
      $0.inputDeviceUID = inputDevice.id
    }
  }

  func outputRouteSelectionStarted() {
    outputRouteConfirmationTask?.cancel()
    outputRouteUIDBeforeSelection = audioIOController.currentOutputRouteUID
  }

  func outputRouteSelectionCompleted() {
    outputRouteConfirmationTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 300_000_000)
      guard let self, !Task.isCancelled else { return }
      confirmOutputRouteSelection()
    }
  }

  private func confirmOutputRouteSelection() {
    guard !isApplying else { return }
    defer { outputRouteUIDBeforeSelection = nil }
    guard outputRouteUIDBeforeSelection != audioIOController.currentOutputRouteUID else {
      audioIOController.refresh()
      errorMessage = audioIOController.configurationStatus.message
      return
    }
    audioIOController.adoptCurrentOutputRoute()
    let storedSelection = audioIOController.storedSelection
    selection = storedSelection
    confirmedSelection = storedSelection
    errorMessage = audioIOController.configurationStatus.message
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
        let storedSelection = audioIOController.storedSelection
        selection = storedSelection
        confirmedSelection = storedSelection
      } else {
        selection = confirmedSelection
      }
      errorMessage = audioIOController.configurationStatus.message
      isApplying = false
    }
  }
}
