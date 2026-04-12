import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CSVPreviewView_Previews: PreviewProvider {
  static var previews: some View {
    CSVPreviewView(csvURL: URL(string: "https://example.com/data.csv")!)
  }
}

// MARK: - 1. リスト表示用のデータ構造
struct CSVDataRow: Identifiable {
  let id = UUID()  // SwiftUIのリストで扱うために必要な固有ID
  let time: String
  let speed: String
  let volume: String
  let status: String
  let type: String
}

// MARK: - 2. プレビュー画面UI
struct CSVPreviewView: View {
  let csvURL: URL
  @State private var rows: [CSVDataRow] = []

  var body: some View {
    VStack(spacing: 0) {
      // 見出し行（ヘッダー）
      HStack {
        Text("Time (s)")
          .font(.caption)
          .bold()
          .frame(maxWidth: .infinity, alignment: .leading)

        Text("Speed (km/h)")
          .font(.caption)
          .bold()
          .frame(maxWidth: .infinity, alignment: .center)

        Text("Volume (dB)")
          .font(.caption)
          .bold()
          .frame(maxWidth: .infinity, alignment: .center)

        Text("Status")
          .font(.caption2)
          .bold()
          .frame(maxWidth: .infinity, alignment: .center)

        Text("Type")
          .font(.caption2)
          .bold()
          .frame(maxWidth: .infinity, alignment: .trailing)
      }
      .foregroundColor(.gray)
      .padding(.horizontal, 20)
      .padding(.vertical, 12)
      .background(Color(UIColor.secondarySystemBackground))

      // データ一覧リスト
      List(rows) { row in
        HStack {
          Text(row.time)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .leading)

          Text(row.speed)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .center)

          Text(row.volume)
            .font(.system(.body, design: .monospaced))
            .frame(maxWidth: .infinity, alignment: .trailing)

          Text(row.status)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)

        Text(row.type)
            .font(.system(.body, design: .monospaced))
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
        }
      }
      .listStyle(PlainListStyle())  // 背景なしのシンプルなリストスタイル
    }
    .padding(.bottom, 80)  // タブバーと被らないように余白を追加
    .navigationTitle(csvURL.lastPathComponent)
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      loadCSV()
    }
  }

  // MARK: - 3. CSV読み込み処理
  private func loadCSV() {
    do {
      // URLからテキストデータを読み込む
      let data = try String(contentsOf: csvURL, encoding: .utf8)
      let lines = data.components(separatedBy: .newlines)

      var parsedRows: [CSVDataRow] = []

      // 1行目（ヘッダー）を飛ばして、2行目から読み込む
      for line in lines.dropFirst() {
        if line.isEmpty { continue } // 空行によるクラッシュを防止

        let columns = line.components(separatedBy: ",")
        
        // ★修正: 最低3つ（時間、速度、音量）のデータが揃っていれば読み込む
        if columns.count >= 3 {
          let time = columns[0]
          let speed = columns[1]
          let volume = columns[2]
          
          // ★修正: 4列目・5列目が存在しない場合（RecordingsViewのデータ）は "--" を入れる
          let status = columns.count >= 4 ? columns[3] : "--"
          let type = columns.count >= 5 ? columns[4] : "--"
          
          let row = CSVDataRow(time: time, speed: speed, volume: volume, status: status, type: type)
          parsedRows.append(row)
        }
      }
      // 画面に反映
      self.rows = parsedRows

    } catch {
      print("CSVの読み込みに失敗しました: \(error.localizedDescription)")
    }
  }
}
