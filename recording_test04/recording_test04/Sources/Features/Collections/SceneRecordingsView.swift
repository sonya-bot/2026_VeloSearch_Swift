import SwiftUI

struct SceneRecordingsView: View {
  let sceneURL: URL
  let recordingFileStore: RecordingFileStoring
  let userDefaults: UserDefaults
  @Binding var favoriteAudios: Set<String>
  let onFavoriteTapped: (URL) -> Void
  let onRecordingDeleted: (URL) -> Void

  @StateObject private var viewModel: SceneRecordingsViewModel
  @State private var searchText = ""

  init(
    sceneURL: URL,
    recordingFileStore: RecordingFileStoring,
    userDefaults: UserDefaults,
    favoriteAudios: Binding<Set<String>>,
    onFavoriteTapped: @escaping (URL) -> Void,
    onRecordingDeleted: @escaping (URL) -> Void
  ) {
    self.sceneURL = sceneURL
    self.recordingFileStore = recordingFileStore
    self.userDefaults = userDefaults
    _favoriteAudios = favoriteAudios
    self.onFavoriteTapped = onFavoriteTapped
    self.onRecordingDeleted = onRecordingDeleted
    _viewModel = StateObject(
      wrappedValue: SceneRecordingsViewModel(
        sceneURL: sceneURL,
        recordingFileStore: recordingFileStore
      )
    )
  }

  private var filteredItems: [URL] {
    guard !searchText.isEmpty else { return viewModel.items }
    return viewModel.items.filter { $0.lastPathComponent.localizedStandardContains(searchText) }
  }

  var body: some View {
    Group {
      if viewModel.items.isEmpty {
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
            recordingFileStore: recordingFileStore,
            userDefaults: userDefaults,
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
    .refreshable { viewModel.refresh() }
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
    .onAppear { viewModel.refresh() }
  }

  private func audioKey(_ audio: URL) -> String {
    "\(audio.deletingLastPathComponent().lastPathComponent)/\(audio.lastPathComponent)"
  }

  private func isFavorite(_ audio: URL) -> Bool {
    favoriteAudios.contains(audioKey(audio))
  }

  private func toggleFavorite(_ audio: URL) {
    onFavoriteTapped(audio)
  }

  private func deleteAudio(_ audio: URL) {
    if viewModel.deleteRecording(at: audio) {
      onRecordingDeleted(audio)
    }
  }
}

struct RecordingRows: View {
  let items: [URL]
  let recordingFileStore: RecordingFileStoring
  let userDefaults: UserDefaults
  let favoriteAudios: Set<String>
  let onDelete: (URL) -> Void
  let onFavorite: (URL) -> Void
  let isFavorite: (URL) -> Bool

  var body: some View {
    ForEach(items, id: \.self) { item in
      // URL値ベースの遷移では一覧更新時に遷移状態が解除されることがあるため、
      // Playerを直接生成する。
      NavigationLink(
        destination: PlayerView(
          audioURL: item,
          recordingFileStore: recordingFileStore,
          userDefaults: userDefaults
        )
      ) {
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
        Button(role: .destructive) {
          onDelete(item)
        } label: {
          Label("", systemImage: "trash")
        }
      }
      .swipeActions(edge: .leading, allowsFullSwipe: false) {
        Button {
          onFavorite(item)
        } label: {
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
