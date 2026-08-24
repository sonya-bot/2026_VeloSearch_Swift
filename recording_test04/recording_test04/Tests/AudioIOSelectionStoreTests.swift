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
      outputDevice: .external,
      channelMode: .stereo,
      orientation: .portrait,
      micSource: .front
    )

    store.save(selection)

    #expect(store.selection == selection)
  }
}
