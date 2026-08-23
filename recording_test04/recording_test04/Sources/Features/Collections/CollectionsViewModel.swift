import Combine
import Foundation

// MARK: - 1. Collections (ViewModel / ロジック定義)
@MainActor
final class CollectionsViewModel: ObservableObject {
  @Published var scenes: [URL] = []
  @Published var defaultItems: [URL] = []
  @Published var favoriteAudios: Set<String> = []
  @Published var errorMessage: String?

  private let store: RecordingFileStoring
  private let userDefaults: UserDefaults

  init(store: RecordingFileStoring, userDefaults: UserDefaults) {
    self.store = store
    self.userDefaults = userDefaults
    let currentFavs = userDefaults.stringArray(forKey: "favoriteAudios") ?? []
    favoriteAudios = Set(currentFavs)
  }

  func refresh() {
    do {
      try store.prepareStorage()
      scenes = store.sceneDirectories()
      defaultItems = store.recordings(in: store.defaultDirectory)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func createScene(named name: String) {
    do {
      try store.createScene(named: name)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func renameScene(_ scene: URL, to name: String) {
    do {
      try store.renameScene(at: scene, to: name)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func deleteScene(_ scene: URL) {
    do {
      try store.deleteScene(at: scene)
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func deleteAudio(_ audio: URL) {
    do {
      try store.deleteRecording(at: audio)
      favoriteAudios.remove(audioKey(audio))
      saveFavorites()
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func toggleFavorite(_ audio: URL) {
    let key = audioKey(audio)
    if favoriteAudios.contains(key) {
      favoriteAudios.remove(key)
    } else {
      favoriteAudios.insert(key)
    }
    saveFavorites()
  }

  func removeFavorite(_ audio: URL) {
    favoriteAudios.remove(audioKey(audio))
    saveFavorites()
  }

  func isFavorite(_ audio: URL) -> Bool {
    favoriteAudios.contains(audioKey(audio))
  }

  private func audioKey(_ audio: URL) -> String {
    "\(audio.deletingLastPathComponent().lastPathComponent)/\(audio.lastPathComponent)"
  }

  private func saveFavorites() {
    userDefaults.set(Array(favoriteAudios), forKey: "favoriteAudios")
  }
}
