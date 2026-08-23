import SwiftUI
import UIKit

struct SceneShareSelectionView: View {
  let sceneURL: URL
  let recordingFileStore: RecordingFileStoring

  @Environment(\.dismiss) private var dismiss
  @State private var selectedType: SceneShareType = .wav
  @State private var archiveURL: IdentifiedURL?
  @State private var errorMessage: String?

  private var selectedFiles: [URL] {
    recordingFileStore.shareableFiles(in: sceneURL, type: selectedType)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section("共有する形式") {
          Picker("形式", selection: $selectedType) {
            ForEach(SceneShareType.allCases) { type in
              Text(type.rawValue).tag(type)
            }
          }
          .pickerStyle(.inline)
        }

        Section {
          LabeledContent("対象ファイル", value: "\(selectedFiles.count)件")
        }
      }
      .navigationTitle(sceneURL.lastPathComponent)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("キャンセル") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("共有") { createArchive() }
            .disabled(selectedFiles.isEmpty)
        }
      }
      .sheet(item: $archiveURL) { archive in
        ActivityView(activityItems: [archive.url])
      }
      .alert(
        "共有できません",
        isPresented: Binding(
          get: { errorMessage != nil },
          set: { if !$0 { errorMessage = nil } }
        )
      ) {
        Button("OK", role: .cancel) { errorMessage = nil }
      } message: {
        Text(errorMessage ?? "")
      }
    }
  }

  private func createArchive() {
    do {
      archiveURL = IdentifiedURL(
        url: try recordingFileStore.createShareArchive(
          sceneURL: sceneURL,
          type: selectedType
        )
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct ActivityView: UIViewControllerRepresentable {
  let activityItems: [Any]

  func makeUIViewController(context: Context) -> UIActivityViewController {
    UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
  }

  func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct IdentifiedURL: Identifiable {
  let url: URL

  var id: String { url.absoluteString }
}
