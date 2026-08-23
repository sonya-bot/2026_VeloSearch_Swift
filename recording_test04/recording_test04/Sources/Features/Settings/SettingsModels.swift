enum SettingsStorageKey {
  static let isNoiseFilterEnabled = "isNoiseFilterEnabled"
  static let warningSoundID = "warningSoundID"
  static let isMonitoringEnabled = "isMonitoringEnabled"
  static let selectedMonitoringSound = "selectedMonitoringSound"
  static let showDebugOverlay = "showDebugOverlay"
  static let selectedInputDevice = "selectedInputDevice"
  static let selectedOutputDevice = "selectedOutputDevice"
  static let recordingChannelMode = "recordingChannelMode"
  static let deviceOrientation = "deviceOrientation"
  static let micSource = "micSource"
}

struct SoundOption: Identifiable {
  let id: Int
  let name: String
  let fileName: String

  static let available = [
    SoundOption(id: 1052, name: "デフォルト", fileName: "alert_default"),
    SoundOption(id: 1005, name: "アラーム", fileName: "alert_alarm"),
    SoundOption(id: 1033, name: "チャイム", fileName: "alert_chime"),
    SoundOption(id: 1322, name: "警告", fileName: "alert_warning"),
  ]
}

enum MonitoringSoundSource: String, CaseIterable, Identifiable {
  case sweep5Seconds = "スイープ信号 (5秒)"
  case sweep10Seconds = "スイープ信号 (10秒)"
  case sweep30Seconds = "スイープ信号 (30秒)"
  case pinkNoise = "ピンクノイズ"
  case whiteNoise = "ホワイトノイズ"
  case sineWave1k = "サイン波 (1kHz)"
  case cat = "猫の鳴き声"
  case beep = "ビープ音"

  var id: Self { self }

  static var availableCases: [Self] {
    allCases.filter(\.isBundled)
  }

  var isBundled: Bool {
    switch self {
    case .sweep5Seconds, .sweep10Seconds, .sweep30Seconds, .cat, .beep:
      return true
    case .pinkNoise, .whiteNoise, .sineWave1k:
      return false
    }
  }

  var fileName: String {
    switch self {
    case .sweep5Seconds: return "sweep_5s"
    case .sweep10Seconds: return "sweep_10s"
    case .sweep30Seconds: return "sweep_30s"
    case .pinkNoise: return "pink_noise"
    case .whiteNoise: return "white_noise"
    case .sineWave1k: return "sine_1k"
    case .cat: return "cat"
    case .beep: return "beep"
    }
  }
}
