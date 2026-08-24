import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CSVPreviewView_Previews: PreviewProvider {
  static var previews: some View {
    CSVPreviewView(
      csvURL: URL(string: "https://example.com/data.csv")!,
      recordingFileStore: RecordingFileStore.shared
    )
  }
}

// MARK: - 2. プレビュー画面UI
struct CSVPreviewView: View {
  let csvURL: URL
  @State private var viewModel: CSVPreviewViewModel

  init(csvURL: URL, recordingFileStore: RecordingFileStoring) {
    self.csvURL = csvURL
    _viewModel = State(
      initialValue: CSVPreviewViewModel(
        csvURL: csvURL,
        recordingFileStore: recordingFileStore
      )
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      switch viewModel.loadState {
      case .idle, .loading:
        ProgressView("Loading CSV...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      case .loaded:
        csvTable
      case .empty:
        ContentUnavailableView(
          "CSVデータなし",
          systemImage: "tablecells",
          description: Text("CSVファイルに表示できるデータがありません。")
        )
      case .failed:
        ContentUnavailableView(
          "CSVを読み込めません",
          systemImage: "exclamationmark.triangle",
          description: Text("ファイルが存在することと内容を確認してください。")
        )
      }
    }
    .padding(.bottom, 80)  // タブバーと被らないように余白を追加
    .navigationTitle(csvURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      viewModel.load()
    }
  }

  private var csvTable: some View {
    ScrollView([.horizontal, .vertical]) {
      VStack(alignment: .leading, spacing: 0) {
        // 見出し行（ヘッダー）
        HStack(spacing: 16) {
          ForEach(Array(viewModel.headers.enumerated()), id: \.offset) { _, header in
            Text(header)
              .font(.caption)
              .bold()
              .frame(width: columnWidth(for: header), alignment: .leading)
          }
        }
        .foregroundColor(.gray)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(UIColor.secondarySystemBackground))

        // データ一覧リスト
        LazyVStack(alignment: .leading, spacing: 12) {
          ForEach(viewModel.rows) { row in
            HStack(spacing: 16) {
              ForEach(Array(row.columns.enumerated()), id: \.offset) { index, col in
                Text(col)
                  .font(.system(.caption, design: .monospaced))
                  .frame(
                    width: index < viewModel.headers.count
                      ? columnWidth(for: viewModel.headers[index]) : 100,
                    alignment: .leading)
              }
            }
            .padding(.horizontal, 20)
            Divider()
          }
        }
        .padding(.vertical, 10)
      }
    }
  }

  // 各カラムの幅をよしなに計算
  private func columnWidth(for header: String) -> CGFloat {
    return max(100, CGFloat(header.count * 10))
  }
}
