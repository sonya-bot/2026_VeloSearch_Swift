import SwiftUI

private struct RecordingDeletionConfirmation: ViewModifier {
  @Binding var recording: URL?
  let onDeleteConfirmed: (URL) -> Void

  func body(content: Content) -> some View {
    content.alert(
      "「\(recording?.lastPathComponent ?? "")」を削除しますか？",
      isPresented: Binding(
        get: { recording != nil },
        set: { if !$0 { recording = nil } }
      ),
      presenting: recording
    ) { audioURL in
      Button("削除", role: .destructive) {
        recording = nil
        onDeleteConfirmed(audioURL)
      }
      Button("キャンセル", role: .cancel) { recording = nil }
    } message: { _ in
      Text("録音と関連するCSVなどのファイルが削除されます。この操作は取り消せません。")
    }
  }
}

extension View {
  func recordingDeletionConfirmation(
    recording: Binding<URL?>,
    onDeleteConfirmed: @escaping (URL) -> Void
  ) -> some View {
    modifier(
      RecordingDeletionConfirmation(recording: recording, onDeleteConfirmed: onDeleteConfirmed))
  }
}
