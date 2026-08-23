import SwiftUI

enum MeasurementDirectionTag: String, CaseIterable, Identifiable {
  case none = ""
  case degrees0 = "0"
  case degrees45 = "45"
  case degrees90 = "90"
  case degrees135 = "135"
  case degrees180 = "180"
  case degrees225 = "225"
  case degrees270 = "270"
  case degrees315 = "315"

  var id: Self { self }

  var label: String {
    self == .none ? "未設定" : "\(rawValue)°"
  }
}

struct MeasurementDirectionPicker: View {
  @Binding var selection: MeasurementDirectionTag
  let isDisabled: Bool

  var body: some View {
    Menu {
      Picker("方向タグ", selection: $selection) {
        ForEach(MeasurementDirectionTag.allCases) { direction in
          Text(direction.label).tag(direction)
        }
      }
    } label: {
      compactSettingRow(
        title: "方向タグ",
        value: selection.label,
        systemImage: "location.north.circle.fill"
      )
    }
    .disabled(isDisabled)
  }
}

struct MeasurementDestinationPicker: View {
  let recordingFileStore: RecordingFileStoring
  @Binding var selection: String
  let isDisabled: Bool
  @State private var scenes: [String] = []

  var body: some View {
    Menu {
      Picker("保存先", selection: $selection) {
        Text(RecordingFileStore.defaultSceneName).tag(RecordingFileStore.defaultSceneName)
        ForEach(scenes, id: \.self) { scene in
          Text(scene).tag(scene)
        }
      }
    } label: {
      compactSettingRow(title: "保存先", value: selection, systemImage: "folder.fill")
    }
    .disabled(isDisabled)
    .onAppear(perform: refresh)
  }

  private func refresh() {
    do {
      try recordingFileStore.prepareStorage()
      scenes = recordingFileStore.sceneDirectories().map(\.lastPathComponent)
      if selection != RecordingFileStore.defaultSceneName && !scenes.contains(selection) {
        selection = RecordingFileStore.defaultSceneName
      }
    } catch {
      scenes = []
      selection = RecordingFileStore.defaultSceneName
    }
  }
}

private func compactSettingRow(title: String, value: String, systemImage: String) -> some View {
  HStack(spacing: 10) {
    Image(systemName: systemImage)
      .foregroundStyle(.blue)
    Text(title)
      .foregroundStyle(.primary)
    Spacer()
    Text(value)
      .foregroundStyle(.secondary)
      .lineLimit(1)
    Image(systemName: "chevron.up.chevron.down")
      .font(.caption2)
      .foregroundStyle(.secondary)
  }
  .padding(.horizontal, 14)
  .frame(height: 42)
  .background(Color(uiColor: .secondarySystemGroupedBackground))
  .clipShape(RoundedRectangle(cornerRadius: 10))
}
