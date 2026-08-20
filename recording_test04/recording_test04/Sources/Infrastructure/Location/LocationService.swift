import CoreLocation
import Foundation
import Observation

@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
  private let manager = CLLocationManager()
  var speed: CLLocationSpeed = 0.0

  override init() {
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    manager.requestWhenInUseAuthorization()
    manager.startUpdatingLocation()
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let location = locations.last else { return }
    self.speed = max(location.speed, 0.0)
  }
}
