import SwiftUI

struct DeveloperSettingsView: View {
  private let recordingFileStore: RecordingFileStoring
  @AppStorage(SettingsStorageKey.showDebugOverlay) private var showDebugOverlay = false
  @State private var viewModel: DeveloperSettingsViewModel

  init(recordingFileStore: RecordingFileStoring) {
    self.recordingFileStore = recordingFileStore
    _viewModel = State(
      initialValue: DeveloperSettingsViewModel(recordingFileStore: recordingFileStore)
    )
  }

  var body: some View {
    Form {
      Section {
        Toggle(isOn: $showDebugOverlay) {
          SettingsRowLabel(
            systemName: "ladybug.fill",
            color: .gray,
            title: "デバッグ表示"
          )
        }
        .tint(.green)
      } footer: {
        Text("Detect画面にAI結果、更新間隔、スキップ回数を表示します。")
      }

      Section {
        if viewModel.devCSVFiles.isEmpty {
          Text("デバッグCSVはまだありません")
            .foregroundStyle(.secondary)
        } else {
          ForEach(viewModel.devCSVFiles, id: \.self) { csvURL in
            NavigationLink(
              destination: CSVPreviewView(
                csvURL: csvURL,
                recordingFileStore: recordingFileStore
              )
            ) {
              Label(csvURL.lastPathComponent, systemImage: "doc.text.fill")
            }
          }
        }
      } header: {
        Text("Debug CSV")
      } footer: {
        Text("Detect画面で保存されたDev_から始まるCSVのみを表示します。")
      }
    }
    .navigationTitle("Developer")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          viewModel.loadDevCSVFiles()
        } label: {
          Image(systemName: "arrow.clockwise")
        }
      }
    }
    .onAppear { viewModel.loadDevCSVFiles() }
  }
}
