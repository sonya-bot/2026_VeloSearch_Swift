import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CSVPreviewView_Previews: PreviewProvider {
  static var previews: some View {
    CSVPreviewView(csvURL: URL(string: "https://example.com/data.csv")!)
  }
}

// MARK: - 1. リスト表示用のデータ構造
struct CSVDataRow: Identifiable {
  let id = UUID()
  let columns: [String]
}

// MARK: - 2. プレビュー画面UI
struct CSVPreviewView: View {
  let csvURL: URL
  @State private var headers: [String] = []
  @State private var rows: [CSVDataRow] = []

  var body: some View {
    VStack(spacing: 0) {
      if headers.isEmpty {
        ProgressView("Loading CSV...")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        ScrollView([.horizontal, .vertical]) {
          VStack(alignment: .leading, spacing: 0) {
            // 見出し行（ヘッダー）
            HStack(spacing: 16) {
              ForEach(Array(headers.enumerated()), id: \.offset) { index, header in
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
              ForEach(rows) { row in
                HStack(spacing: 16) {
                  ForEach(Array(row.columns.enumerated()), id: \.offset) { index, col in
                    Text(col)
                      .font(.system(.caption, design: .monospaced))
                      .frame(
                        width: index < headers.count ? columnWidth(for: headers[index]) : 100,
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
    }
    .padding(.bottom, 80)  // タブバーと被らないように余白を追加
    .navigationTitle(csvURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      loadCSV()
    }
  }

  // 各カラムの幅をよしなに計算
  private func columnWidth(for header: String) -> CGFloat {
    return max(100, CGFloat(header.count * 10))
  }

  // MARK: - 3. CSV読み込み処理
  private func loadCSV() {
    do {
      // URLからテキストデータを読み込む
      let data = try String(contentsOf: csvURL, encoding: .utf8)
      let lines = data.components(separatedBy: .newlines).filter { !$0.isEmpty }
      guard let firstLine = lines.first else { return }

      let parsedHeaders = firstLine.components(separatedBy: ",")
      var parsedRows: [CSVDataRow] = []

      // 1行目（ヘッダー）を飛ばして、2行目から読み込む
      for line in lines.dropFirst() {
        let columns = line.components(separatedBy: ",")
        parsedRows.append(CSVDataRow(columns: columns))
      }

      // 画面に反映
      DispatchQueue.main.async {
        self.headers = parsedHeaders
        self.rows = parsedRows
      }
    } catch {
      AppLogger.storage.error("CSVの読み込みに失敗しました: \(error.localizedDescription)")
    }
  }
}
