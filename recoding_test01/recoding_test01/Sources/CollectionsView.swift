import SwiftUI

// MARK: - 0. Preview(Xcode)
struct CollectionsView_Previews: PreviewProvider {
    static var previews: some View {
        CollectionsView()
    }
}

// MARK: - 1. CollectionsView(録音ファイル一覧表示)
struct CollectionsView: View {
    @State private var recordings: [URL] = [] 

    var body: some View {
        NavigationView {
            List {
                ForEach(recordings, id: \.self) { url in
                    NavigationLink(destination: PlayerView(audioURL: url)) {
                        HStack {
                            Image(systemName: "waveform.circle")
                                .foregroundColor(.white) // アイコンの色を白に変更
                                .imageScale(.large)
                            
                            Text(url.lastPathComponent)
                                .font(.body)
                                .padding(.leading, 8)
                            
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Collections")
            .onAppear {
                fetchRecordings()
            }
        }
    }

    private func fetchRecordings() {
        let fileManager = FileManager.default
        let documentDirectory = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        
        do {
            let directoryContents = try fileManager.contentsOfDirectory(at: documentDirectory, includingPropertiesForKeys: nil)
            self.recordings = directoryContents.filter { $0.pathExtension == "wav"}
            print("取得したファイル数: \(recordings.count)")
        } catch {
            print("ファイルの取得に失敗しました: \(error.localizedDescription)")
        }
    }
}