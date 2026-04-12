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
                                Label(
                                    item.lastPathComponent,
                                    systemImage: item.lastPathComponent.contains("録音") ? "mic" : "waveform"
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    // 削除処理を ViewModel に依頼
                                    viewModel.deleteAudio(audio: item)
                                } label: {
                                    Label("削除", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Collections")
            .searchable(text: $searchText, prompt: "データを検索")
            // NavigationLink の value を受け取って遷移先を決定
            .navigationDestination(for: URL.self) { url in
                PlayerView(audioURL: url)
            }
            // ツールバーの設定
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("日付順", action: { /* 今後の実装 */ })
                        Button("種類順", action: { /* 今後の実装 */ })
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