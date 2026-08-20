import Combine
import Foundation

@MainActor
final class AppRootViewModel: ObservableObject {
  @Published var selectedTab = 0
  @Published private(set) var isMonitoringEnabled: Bool

  private let userDefaults: UserDefaults
  private let notificationCenter: NotificationCenter
  private var userDefaultsObserver: NSObjectProtocol?

  init(userDefaults: UserDefaults, notificationCenter: NotificationCenter) {
    self.userDefaults = userDefaults
    self.notificationCenter = notificationCenter
    self.isMonitoringEnabled = userDefaults.bool(forKey: "isMonitoringEnabled")

    userDefaultsObserver = notificationCenter.addObserver(
      forName: UserDefaults.didChangeNotification,
      object: userDefaults,
      queue: .main
    ) { [weak self] _ in
      Task { @MainActor [weak self] in
        self?.refreshMonitoringSetting()
      }
    }
  }

  deinit {
    if let userDefaultsObserver {
      notificationCenter.removeObserver(userDefaultsObserver)
    }
  }

  private func refreshMonitoringSetting() {
    isMonitoringEnabled = userDefaults.bool(forKey: "isMonitoringEnabled")
  }
}
