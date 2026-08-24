import Foundation

struct AudioIOSelectionStore {
  private let userDefaults: UserDefaults

  init(userDefaults: UserDefaults) {
    self.userDefaults = userDefaults
  }

  var selection: AudioIOSelection {
    AudioIOSelection(
      inputDevice: InputDeviceOption(
        rawValue: userDefaults.string(forKey: "selectedInputDevice") ?? ""
      ) ?? .builtIn,
      outputDevice: OutputDeviceOption(
        rawValue: userDefaults.string(forKey: "selectedOutputDevice") ?? ""
      ) ?? .speaker,
      channelMode: RecordingChannelMode(
        rawValue: userDefaults.string(forKey: "recordingChannelMode") ?? ""
      ) ?? .automatic,
      orientation: DeviceOrientationOption(
        rawValue: userDefaults.string(forKey: "deviceOrientation") ?? ""
      ) ?? .landscapeRight,
      micSource: MicSourceOption(
        rawValue: userDefaults.string(forKey: "micSource") ?? ""
      ) ?? .back
    )
  }

  func save(_ selection: AudioIOSelection) {
    userDefaults.set(selection.inputDevice.rawValue, forKey: "selectedInputDevice")
    userDefaults.set(selection.outputDevice.rawValue, forKey: "selectedOutputDevice")
    userDefaults.set(selection.channelMode.rawValue, forKey: "recordingChannelMode")
    userDefaults.set(selection.orientation.rawValue, forKey: "deviceOrientation")
    userDefaults.set(selection.micSource.rawValue, forKey: "micSource")
  }
}
