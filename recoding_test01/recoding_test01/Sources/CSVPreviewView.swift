import SwiftUI
// MARK: - 0. Preview(Xcode)
struct CSVPreviewView_Previews: PreviewProvider {
  static var previews: some View {
    CSVPreviewView(csvURL: URL(string: "https://example.com/data.csv")!)
  }
}

// MARK: - 1. リスト表示用のデータ構造
struct CSVDataRow: Identifiable {
    let id = UUID() // SwiftUIのリストで扱うために必要な固有ID
    let time: String
    let speed: String
    let volume: String
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
                }
            }
            .listStyle(PlainListStyle()) // 背景なしのシンプルなリストスタイル
        }
        .padding(.bottom, 80) // タブバーと被らないように余白を追加
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
                let columns = line.components(separatedBy: ",")
                // 時間、速度、音量の3つのデータが揃っているか確認
                if columns.count >= 3 {
                    let row = CSVDataRow(time: columns[0], speed: columns[1], volume: columns[2])
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