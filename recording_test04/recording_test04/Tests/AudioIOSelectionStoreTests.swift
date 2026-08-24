import AVFoundation
import Foundation
import Testing

@testable import recording_test04

struct AudioIOSelectionStoreTests {
  @Test
  func savePersistsConfirmedAudioIOSelection() throws {
    let suiteName = "AudioIOSelectionStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    let store = AudioIOSelectionStore(userDefaults: userDefaults)
    let selection = AudioIOSelection(
      inputDevice: .external,
      inputDeviceUID: "test-input-uid",
      outputDevice: .bluetooth,
      outputDeviceUID: "test-output-uid",
      channelMode: .stereo,
      orientation: .portrait,
      micSource: .front
    )

    store.save(selection)

    #expect(store.selection == selection)
  }

  @Test
  func legacyExternalOutputMigratesToBluetoothPreference() throws {
    let suiteName = "AudioIOSelectionStoreTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    defer { userDefaults.removePersistentDomain(forName: suiteName) }
    userDefaults.set("connected device", forKey: "selectedOutputDevice")

    let selection = AudioIOSelectionStore(userDefaults: userDefaults).selection

    #expect(selection.outputDevice == .bluetooth)
    #expect(selection.outputDeviceUID == nil)
  }

  @Test
  func outputPortTypesRemainDistinct() {
    #expect(AudioIOConfigurationInspector.outputOption(for: .builtInSpeaker) == .speaker)
    #expect(AudioIOConfigurationInspector.outputOption(for: .usbAudio) == .usb)
    #expect(AudioIOConfigurationInspector.outputOption(for: .bluetoothA2DP) == .bluetooth)
  }
}
