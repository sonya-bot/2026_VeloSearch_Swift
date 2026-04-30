import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CollectionsView_Previews: PreviewProvider {
  static var previews: some View {
    CollectionsView()
  }
}

// MARK: - 1. Collections (ViewModel / ロジック定義)
class CollectionsViewModel: ObservableObject {
  @Published var items: [URL] = []
  @Published var favoriteAudios: Set<String> = []

  init() {
    let currentFavs = UserDefaults.standard.stringArray(forKey: "favoriteAudios") ?? []
    self.favoriteAudios = Set(currentFavs)
  }

  func fetchRecordings() {
    let fileManager = FileManager.default
    let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

    do {
      let directoryContents = try fileManager.contentsOfDirectory(
        at: documentDirectory, includingPropertiesForKeys: nil)
      self.items = directoryContents.filter { $0.pathExtension == "wav" }
        .sorted { $0.lastPathComponent > $1.lastPathComponent }  // ファイル名で降順にソート
      print("取得したファイル数: \(items.count)")
    } catch {
      print("ファイルの取得に失敗しました: \(error.localizedDescription)")
    }
  }

  func deleteAudio(audio: URL) {
    let fileManager = FileManager.default
    do {
      try fileManager.removeItem(at: audio)
      UserDefaults.standard.removeObject(forKey: audio.lastPathComponent)

      // 削除後、リストから該当のURLを取り除いて UI を更新する
      if let index = items.firstIndex(of: audio) {
        items.remove(at: index)
      }
      print("\(audio.lastPathComponent) を削除しました")
    } catch {
      print("ファイルの削除に失敗しました: \(error.localizedDescription)")
    }
  }

  func favoriteAudio(audio: URL) {
    let fileName = audio.lastPathComponent
    if favoriteAudios.contains(fileName) {
      // すでにお気に入りにある場合は削除
      favoriteAudios.remove(fileName)
      print("\(fileName) をお気に入りから削除しました")
    } else {
      // お気に入りに追加
      favoriteAudios.insert(fileName)
      print("\(fileName) をお気に入りに追加しました")
    }
    UserDefaults.standard.set(Array(favoriteAudios), forKey: "favoriteAudios")
  }
}

// MARK: - 2. CollectionsView (画面UI)
struct CollectionsView: View {
  // ViewModel を @StateObject として保持
  @StateObject private var viewModel = CollectionsViewModel()
  @State private var searchText = ""

  // 検索フィルタリング (ViewModel の items を参照)
  var filteredItems: [URL] {
    if searchText.isEmpty {
      return viewModel.items
    } else {
      return viewModel.items.filter { $0.lastPathComponent.localizedStandardContains(searchText) }
    }
  }

  var body: some View {
    NavigationStack {
      Group {
        if viewModel.items.isEmpty {
          // データが空の時の最新UI
          ContentUnavailableView(
            "No Recording Data",
            systemImage: "tray.fill",
            description: Text("Recording data will appear here once you have recordings.")
          )
        } else if filteredItems.isEmpty {
          // 検索結果が空の時の最新UI
          ContentUnavailableView.search(text: searchText)
        } else {
          // 通常のリスト表示
          List {
            ForEach(filteredItems, id: \.self) { item in
              // NavigationStack のための最新の遷移方法
              NavigationLink(value: item) {
                Label {
                  HStack {
                    // お気に入りの場合は星マークを表示
                    if viewModel.favoriteAudios.contains(item.lastPathComponent) {
                      Image(systemName: "star.fill")
                        .foregroundStyle(.green)
                    }
                    Text(item.lastPathComponent)
                      .lineLimit(1)
                  }
                } icon: {
                  Image(
                    systemName: item.lastPathComponent.contains("Recording")
                      ? "mic"
                      : (item.lastPathComponent.contains("Monitoring") ? "headphones" : "waveform"))
                }

              }
              .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                  // 削除処理を ViewModel に依頼
                  viewModel.deleteAudio(audio: item)
                } label: {
                  Label("", systemImage: "trash")
                }
              }
              .swipeActions(edge: .leading, allowsFullSwipe: false) {
                let isFavorite = viewModel.favoriteAudios.contains(item.lastPathComponent)
                Button {
                  // お気に入り処理を ViewModel に依頼
                  viewModel.favoriteAudio(audio: item)
                } label: {
                  Image(systemName: isFavorite ? "star.fill" : "star")
                }
                .tint(isFavorite ? .green : .gray)
              }
            }
          }
        }
      }
      .navigationTitle("Collections")
      .searchable(text: $searchText, prompt: "Search Recordings")
      // NavigationLink の value を受け取って遷移先を決定
      .navigationDestination(for: URL.self) { url in
        PlayerView(audioURL: url)
      }
      // ツールバーの設定
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Menu {
            Button(
              "in date order",
              action: { viewModel.items.sort { $0.lastPathComponent > $1.lastPathComponent } })
            Button("in name order", action: { /* 今後の実装 */  })
          } label: {
            Image(systemName: "arrow.up.arrow.down.circle")
          }
        }

        // ToolbarItem(placement: .topBarLeading) {
        //     Button(action: {
        //         // 編集モードなどのアクション
        //     }) {
        //         Text("編集")
        //     }
        // }
      }
      // リストを引っ張って更新
      .refreshable {
        viewModel.fetchRecordings()
      }
    }
    .onAppear {
      // 画面表示時にデータを取得
      viewModel.fetchRecordings()
    }
  }
}
