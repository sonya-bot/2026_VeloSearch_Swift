import SwiftUI

struct CollectionView: View {
    // 録音ファイルのURLを格納する配列
    @State private var recordings: [URL] = [] 

    var body: some View {
        // タイトル文字
        VStack {
            HStack{
                Text("Collections")
                    .font(.largeTitle)
                    .bold()
                    .padding(10)
                Spacer()
            }
            Spacer()
        }

        NavigationView {
            List {
                // 配列内のURLを一つずつ取り出してリスト表示
                ForEach(recordings, id: \.self) { url in
                    HStack {
                        Image(systemName: "waveform.circle")
                            .foregroundColor(.blue)
                            .imageScale(.large)
                        
                        // ファイル名を表示
                        Text(url.lastPathComponent)
                            .font(.body)
                            .padding(.leading, 8)
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Collections")
            // 画面が表示されるタイミングでファイルを取得する
            .onAppear {
                fetchRecordings()
            }
        }
    }

    // ドキュメントフォルダから録音ファイルを取得するメソッド
    private func fetchRecordings() {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            // フォルダ内のすべてのファイルを取得
            let directoryContents = try fileManager.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
            
            // .m4a または .wav 拡張子のファイルだけを抽出し、作成日時などの順に並び替えることも可能（今回は単純にフィルタリングのみ）
            self.recordings = directoryContents.filter { $0.pathExtension == "m4a" || $0.pathExtension == "wav" || $0.pathExtension == "caf" }
            
            print("取得したファイル数: \(recordings.count)")
        } catch {
            print("ファイルの取得に失敗しました: \(error.localizedDescription)")
        }
    }
}