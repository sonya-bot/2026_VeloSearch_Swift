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

struct AudioIOSelection: Equatable {
  var inputDevice: InputDeviceOption
  var outputDevice: OutputDeviceOption
  var channelMode: RecordingChannelMode
  var orientation: DeviceOrientationOption
  var micSource: MicSourceOption
}

enum AudioIOConfigurationStatus: Equatable {
  case unverified
  case applying
  case ready
  case rejected(String)
  case unavailable(String)

  var message: String? {
    switch self {
    case .unverified:
      return "Audio I/Oを確認していません。"
    case .applying:
      return "Audio I/Oを確認中です。"
    case .ready:
      return nil
    case .rejected(let message), .unavailable(let message):
      return message
    }
  }
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
  case stereoPolarPatternUnavailable(String)
  case configurationNotEstablished(String)
  case configurationLocked

  var errorDescription: String? {
    switch self {
    case .inputUnavailable(let input):
      return "\(input)入力を利用できません。"
    case .inputDataSourceUnavailable(let source):
      return "\(source)マイクを利用できません。"
    case .stereoUnavailable(let channelCount):
      return "Stereo入力を利用できません（入力 \(channelCount)ch）。"
    case .stereoPolarPatternUnavailable(let source):
      return "\(source)マイク構成ではStereo入力を利用できません。"
    case .configurationNotEstablished(let detail):
      return "Audio I/O設定を確定できません（\(detail)）。"
    case .configurationLocked:
      return "計測中はAudio I/O設定を変更できません。"
    }
  }
}
