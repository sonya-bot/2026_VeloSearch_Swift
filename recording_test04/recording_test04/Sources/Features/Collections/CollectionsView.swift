import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CollectionsView_Previews: PreviewProvider {
  static var previews: some View {
    CollectionsView(recordingFileStore: RecordingFileStore.shared, userDefaults: .standard)
  }
}

// MARK: - 2. CollectionsView (画面UI)
struct CollectionsView: View {
  private let recordingFileStore: RecordingFileStoring
  private let userDefaults: UserDefaults
  @StateObject private var viewModel: CollectionsViewModel
  @State private var searchText = ""
  @State private var showingCreateScene = false
  @State private var newSceneName = ""
  @State private var sceneToRename: URL?
  @State private var renamedSceneName = ""
  @State private var sceneToDelete: URL?
  @State private var sceneToShare: IdentifiedURL?

  init(recordingFileStore: RecordingFileStoring, userDefaults: UserDefaults) {
    self.recordingFileStore = recordingFileStore
    self.userDefaults = userDefaults
    _viewModel = StateObject(
      wrappedValue: CollectionsViewModel(store: recordingFileStore, userDefaults: userDefaults)
    )
  }

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
                      recordingFileStore: recordingFileStore,
                      userDefaults: userDefaults,
                      favoriteAudios: $viewModel.favoriteAudios,
                      onFavoriteTapped: viewModel.toggleFavorite,
                      onRecordingDeleted: viewModel.removeFavorite
                    )
                  } label: {
                    Label(scene.lastPathComponent, systemImage: "folder.fill")
                  }
                  .contextMenu {
                    Button {
                      sceneToShare = IdentifiedURL(url: scene)
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
                  recordingFileStore: recordingFileStore,
                  userDefaults: userDefaults,
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
                $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent)
                  == .orderedAscending
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
        Text(
          "このScene内の録音ファイルとCSVファイルも削除されます。"
            + "この操作は取り消せません。"
        )
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
        SceneShareSelectionView(
          sceneURL: scene.url,
          recordingFileStore: recordingFileStore
        )
      }
    }
    .onAppear { viewModel.refresh() }
  }
}
