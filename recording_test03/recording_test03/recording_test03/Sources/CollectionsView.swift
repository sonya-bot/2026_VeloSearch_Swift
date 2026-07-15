import SwiftUI
import UIKit

// MARK: - 0. Preview(Xcode)
struct CollectionsView_Previews: PreviewProvider {
  static var previews: some View {
    CollectionsView()
  }
}

// MARK: - 1. Collections (ViewModel / ロジック定義)
@MainActor
final class CollectionsViewModel: ObservableObject {
  @Published var scenes: [URL] = []
  @Published var defaultItems: [URL] = []
  @Published var favoriteAudios: Set<String> = []
  @Published var errorMessage: String?

  private let store = RecordingFileStore.shared

  init() {
    let currentFavs = UserDefaults.standard.stringArray(forKey: "favoriteAudios") ?? []
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

  func isFavorite(_ audio: URL) -> Bool {
    favoriteAudios.contains(audioKey(audio))
  }

  private func audioKey(_ audio: URL) -> String {
    "\(audio.deletingLastPathComponent().lastPathComponent)/\(audio.lastPathComponent)"
  }

  private func saveFavorites() {
    UserDefaults.standard.set(Array(favoriteAudios), forKey: "favoriteAudios")
  }
}

// MARK: - 2. CollectionsView (画面UI)
struct CollectionsView: View {
  @StateObject private var viewModel = CollectionsViewModel()
  @State private var searchText = ""
  @State private var showingCreateScene = false
  @State private var newSceneName = ""
  @State private var sceneToRename: URL?
  @State private var renamedSceneName = ""
  @State private var sceneToDelete: URL?
  @State private var sceneToShare: URL?

  private var filteredScenes: [URL] {
    guard !searchText.isEmpty else { return viewModel.scenes }
    return viewModel.scenes.filter {
      $0.lastPathComponent.localizedStandardContains(searchText)
    }
  }

  private var filteredDefaultItems: [URL] {
    guard !searchText.isEmpty else { return viewModel.defaultItems }
    return viewModel.defaultItems.filter {
      $0.lastPathComponent.localizedStandardContains(searchText)
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.scenes.isEmpty && viewModel.defaultItems.isEmpty {
          ContentUnavailableView(
            "No Recording Data",
            systemImage: "tray.fill",
            description: Text("Recording data will appear here once you have recordings.")
          )
        } else if filteredScenes.isEmpty && filteredDefaultItems.isEmpty {
          ContentUnavailableView.search(text: searchText)
        } else {
          List {
            if !filteredScenes.isEmpty {
              Section("Scenes") {
                ForEach(filteredScenes, id: \.self) { scene in
                  NavigationLink {
                    SceneRecordingsView(
                      sceneURL: scene,
                      favoriteAudios: $viewModel.favoriteAudios,
                      onFavoritesChanged: viewModel.refresh
                    )
                  } label: {
                    Label(scene.lastPathComponent, systemImage: "folder.fill")
                  }
                  .contextMenu {
                    Button {
                      sceneToShare = scene
                    } label: {
                      Label("共有", systemImage: "square.and.arrow.up")
                    }

                    Button {
                      renamedSceneName = scene.lastPathComponent
                      sceneToRename = scene
                    } label: {
                      Label("名前を変更", systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                      sceneToDelete = scene
                    } label: {
                      Label("削除", systemImage: "trash")
                    }
                  }
                }
              }
            }

            if !filteredDefaultItems.isEmpty {
              Section("Default") {
                RecordingRows(
                  items: filteredDefaultItems,
                  favoriteAudios: viewModel.favoriteAudios,
                  onDelete: viewModel.deleteAudio,
                  onFavorite: viewModel.toggleFavorite,
                  isFavorite: viewModel.isFavorite
                )
              }
            }
          }
        }
      }
      .navigationTitle("Collections")
      .navigationBarTitleDisplayMode(.inline)
      .searchable(text: $searchText, prompt: "Search Recordings")
      .navigationDestination(for: URL.self) { url in
        PlayerView(audioURL: url)
      }
      .toolbar {
        ToolbarItemGroup(placement: .topBarTrailing) {
          Button {
            newSceneName = ""
            showingCreateScene = true
          } label: {
            Image(systemName: "plus")
          }
          .accessibilityLabel("Sceneを作成")

          Menu {
            Button("in date order") {
              viewModel.defaultItems.sort { $0.lastPathComponent > $1.lastPathComponent }
            }
            Button("in name order") {
              viewModel.defaultItems.sort {
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
              }
            }
          } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
          }
        }
      }
      .refreshable { viewModel.refresh() }
      .alert("Sceneを作成", isPresented: $showingCreateScene) {
        TextField("Scene名", text: $newSceneName)
        Button("作成") { viewModel.createScene(named: newSceneName) }
        Button("キャンセル", role: .cancel) {}
      }
      .alert(
        "Scene名を変更",
        isPresented: Binding(
          get: { sceneToRename != nil },
          set: { if !$0 { sceneToRename = nil } }
        )
      ) {
        TextField("Scene名", text: $renamedSceneName)
        Button("変更") {
          if let sceneToRename {
            viewModel.renameScene(sceneToRename, to: renamedSceneName)
          }
          sceneToRename = nil
        }
        Button("キャンセル", role: .cancel) { sceneToRename = nil }
      }
      .confirmationDialog(
        "「\(sceneToDelete?.lastPathComponent ?? "")」を削除しますか？",
        isPresented: Binding(
          get: { sceneToDelete != nil },
          set: { if !$0 { sceneToDelete = nil } }
        ),
        titleVisibility: .visible
      ) {
        Button("削除", role: .destructive) {
          if let sceneToDelete { viewModel.deleteScene(sceneToDelete) }
          sceneToDelete = nil
        }
        Button("キャンセル", role: .cancel) { sceneToDelete = nil }
      } message: {
        Text("このScene内の録音ファイルとCSVファイルも削除されます。この操作は取り消せません。")
      }
      .alert(
        "エラー",
        isPresented: Binding(
          get: { viewModel.errorMessage != nil },
          set: { if !$0 { viewModel.errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { viewModel.errorMessage = nil }
      } message: {
        Text(viewModel.errorMessage ?? "")
      }
      .sheet(item: $sceneToShare) { scene in
        SceneShareSelectionView(sceneURL: scene)
      }
    }
    .onAppear { viewModel.refresh() }
  }
}

private struct SceneRecordingsView: View {
  let sceneURL: URL
  @Binding var favoriteAudios: Set<String>
  let onFavoritesChanged: () -> Void

  @State private var items: [URL] = []
  @State private var searchText = ""
  @State private var errorMessage: String?

  private var filteredItems: [URL] {
    guard !searchText.isEmpty else { return items }
    return items.filter { $0.lastPathComponent.localizedStandardContains(searchText) }
  }

  var body: some View {
    Group {
      if items.isEmpty {
        ContentUnavailableView(
          "No Recording Data",
          systemImage: "waveform",
          description: Text("This Scene has no recordings.")
        )
      } else if filteredItems.isEmpty {
        ContentUnavailableView.search(text: searchText)
      } else {
        List {
          RecordingRows(
            items: filteredItems,
            favoriteAudios: favoriteAudios,
            onDelete: deleteAudio,
            onFavorite: toggleFavorite,
            isFavorite: isFavorite
          )
        }
      }
    }
    .navigationTitle(sceneURL.lastPathComponent)
    .searchable(text: $searchText, prompt: "Search Recordings")
    .refreshable { refresh() }
    .alert("エラー", isPresented: Binding(
      get: { errorMessage != nil },
      set: { if !$0 { errorMessage = nil } }
    )) {
      Button("OK", role: .cancel) { errorMessage = nil }
    } message: {
      Text(errorMessage ?? "")
    }
    .onAppear { refresh() }
  }

  private func refresh() {
    items = RecordingFileStore.shared.recordings(in: sceneURL)
  }

  private func audioKey(_ audio: URL) -> String {
    "\(audio.deletingLastPathComponent().lastPathComponent)/\(audio.lastPathComponent)"
  }

  private func isFavorite(_ audio: URL) -> Bool {
    favoriteAudios.contains(audioKey(audio))
  }

  private func toggleFavorite(_ audio: URL) {
    let key = audioKey(audio)
    if favoriteAudios.contains(key) {
      favoriteAudios.remove(key)
    } else {
      favoriteAudios.insert(key)
    }
    UserDefaults.standard.set(Array(favoriteAudios), forKey: "favoriteAudios")
    onFavoritesChanged()
  }

  private func deleteAudio(_ audio: URL) {
    do {
      try RecordingFileStore.shared.deleteRecording(at: audio)
      favoriteAudios.remove(audioKey(audio))
      UserDefaults.standard.set(Array(favoriteAudios), forKey: "favoriteAudios")
      refresh()
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct RecordingRows: View {
  let items: [URL]
  let favoriteAudios: Set<String>
  let onDelete: (URL) -> Void
  let onFavorite: (URL) -> Void
  let isFavorite: (URL) -> Bool

  var body: some View {
    ForEach(items, id: \.self) { item in
      NavigationLink(value: item) {
        Label {
          HStack {
            if isFavorite(item) {
              Image(systemName: "star.fill")
                .foregroundStyle(.green)
            }
            Text(item.lastPathComponent)
              .lineLimit(1)
          }
        } icon: {
          Image(systemName: recordingIcon(for: item))
        }
      }
      .swipeActions(edge: .trailing, allowsFullSwipe: false) {
        Button(role: .destructive) { onDelete(item) } label: {
          Label("", systemImage: "trash")
        }
      }
      .swipeActions(edge: .leading, allowsFullSwipe: false) {
        Button { onFavorite(item) } label: {
          Image(systemName: isFavorite(item) ? "star.fill" : "star")
        }
        .tint(isFavorite(item) ? .green : .gray)
      }
    }
  }

  private func recordingIcon(for item: URL) -> String {
    if item.lastPathComponent.contains("Recording") { return "mic" }
    if item.lastPathComponent.contains("Monitoring") { return "headphones" }
    return "waveform"
  }
}

private struct SceneShareSelectionView: View {
  let sceneURL: URL

  @Environment(\.dismiss) private var dismiss
  @State private var selectedType: SceneShareType = .wav
  @State private var archiveURL: URL?
  @State private var errorMessage: String?

  private var selectedFiles: [URL] {
    RecordingFileStore.shared.shareableFiles(in: sceneURL, type: selectedType)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("共有する形式") {
          Picker("形式", selection: $selectedType) {
            ForEach(SceneShareType.allCases) { type in
              Text(type.rawValue).tag(type)
            }
          }
          .pickerStyle(.inline)
        }

        Section {
          LabeledContent("対象ファイル", value: "\(selectedFiles.count)件")
        }
      }
      .navigationTitle(sceneURL.lastPathComponent)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("共有") { createArchive() }
            .disabled(selectedFiles.isEmpty)
        }
      }
      .sheet(item: $archiveURL) { url in
        ActivityView(activityItems: [url])
      }
      .alert("共有できません", isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } }
      )) {
        Button("OK", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func createArchive() {
    do {
      archiveURL = try RecordingFileStore.shared.createShareArchive(
        sceneURL: sceneURL,
        type: selectedType
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct ActivityView: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
  public var id: String { absoluteString }
}
