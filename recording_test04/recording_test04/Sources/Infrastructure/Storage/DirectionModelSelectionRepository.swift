import Foundation

protocol DirectionModelSelectionPersisting: AnyObject {
  var selectedModelName: String? { get set }
}

final class DirectionModelSelectionRepository: DirectionModelSelectionPersisting {
  private let userDefaults: UserDefaults
  private let key = "selectedDirectionModelName"

  init(userDefaults: UserDefaults) { self.userDefaults = userDefaults }

  var selectedModelName: String? {
    get { userDefaults.string(forKey: key) }
    set { userDefaults.set(newValue, forKey: key) }
  }
}
