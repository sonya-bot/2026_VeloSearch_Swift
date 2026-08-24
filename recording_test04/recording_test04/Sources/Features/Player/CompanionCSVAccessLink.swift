import SwiftUI

enum CompanionCSVAccessStyle {
  case card
  case listRow
}

struct CompanionCSVAccessLink: View {
  let csvURL: URL?
  let recordingFileStore: RecordingFileStoring
  let style: CompanionCSVAccessStyle

  var body: some View {
    switch style {
    case .card:
      navigationContent
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    case .listRow:
      navigationContent
    }
  }

  @ViewBuilder
  private var navigationContent: some View {
    if let csvURL {
      NavigationLink {
        CSVPreviewView(
          csvURL: csvURL,
          recordingFileStore: recordingFileStore
        )
      } label: {
        accessLabel(csvURL: csvURL)
      }
      .buttonStyle(.plain)
    } else {
      accessLabel(csvURL: nil)
        .accessibilityHint("対応するCSVファイルがありません")
    }
  }

  private func accessLabel(csvURL: URL?) -> some View {
    HStack(spacing: 12) {
      Image(systemName: "tablecells")
        .font(.title3)
        .foregroundStyle(csvURL == nil ? Color.secondary : Color.accentColor)
        .frame(width: 24)
      VStack(alignment: .leading, spacing: 2) {
        Text("CSVデータ")
          .foregroundStyle(.primary)
        Text(csvURL?.lastPathComponent ?? "CSVデータなし")
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      Spacer(minLength: 8)
      if csvURL != nil {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.tertiary)
      }
    }
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}
