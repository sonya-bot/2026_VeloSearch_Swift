import FirebaseCore
import UIKit

final class FirebaseAppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    guard
      let configurationPath = Bundle.main.path(
        forResource: "GoogleService-Info",
        ofType: "plist"
      ),
      let options = FirebaseOptions(contentsOfFile: configurationPath)
    else {
      AppLogger.app.error("Firebase設定ファイルを読み込めないため、初期化を行いません")
      return true
    }

    FirebaseApp.configure(options: options)
    return true
  }
}
