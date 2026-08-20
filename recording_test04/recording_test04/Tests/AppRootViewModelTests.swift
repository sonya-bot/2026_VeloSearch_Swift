import Foundation
import Testing

@testable import recording_test04

struct AppRootViewModelTests {
  @Test
  @MainActor
  func monitoringSettingChangeUpdatesRootState() async throws {
    let suiteName = "AppRootViewModelTests.\(UUID().uuidString)"
    let userDefaults = try #require(UserDefaults(suiteName: suiteName))
    let notificationCenter = NotificationCenter()
    let viewModel = AppRootViewModel(
      userDefaults: userDefaults,
      notificationCenter: notificationCenter
    )

    #expect(viewModel.selectedTab == 0)
    #expect(!viewModel.isMonitoringEnabled)

    viewModel.selectedTab = 3
    userDefaults.set(true, forKey: "isMonitoringEnabled")
    notificationCenter.post(
      name: UserDefaults.didChangeNotification,
      object: userDefaults
    )
    await Task.yield()

    #expect(viewModel.selectedTab == 3)
    #expect(viewModel.isMonitoringEnabled)
  }
}
