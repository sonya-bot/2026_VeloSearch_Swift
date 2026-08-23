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
        value: selection.label
      )
    }
    .disabled(isDisabled)
  }
}

struct MeasurementDestinationPicker: View {
  @Binding var selection: String
  let isDisabled: Bool
  @StateObject private var viewModel: MeasurementDestinationPickerViewModel

  init(
    recordingFileStore: RecordingFileStoring,
    selection: Binding<String>,
    isDisabled: Bool
  ) {
    _selection = selection
    self.isDisabled = isDisabled
    _viewModel = StateObject(
      wrappedValue: MeasurementDestinationPickerViewModel(
        recordingFileStore: recordingFileStore
      )
    )
  }

  var body: some View {
    Menu {
      Picker("保存先", selection: $selection) {
        Text(RecordingFileStore.defaultSceneName).tag(RecordingFileStore.defaultSceneName)
        ForEach(viewModel.scenes, id: \.self) { scene in
          Text(scene).tag(scene)
        }
      }
    } label: {
      compactSettingRow(title: "保存先", value: selection)
    }
    .disabled(isDisabled)
    .onAppear {
      selection = viewModel.refreshedSelection(from: selection)
    }
  }
}

private func compactSettingRow(title: String, value: String) -> some View {
  VStack(alignment: .leading, spacing: 3) {
    Text(title)
      .font(.caption)
      .foregroundStyle(.secondary)
    HStack(spacing: 6) {
      Text(value)
        .foregroundStyle(.primary)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      Spacer(minLength: 2)
      Image(systemName: "chevron.up.chevron.down")
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
  }
  .padding(.horizontal, 12)
  .frame(maxWidth: .infinity, alignment: .leading)
  .frame(height: 48)
  .background(Color(uiColor: .secondarySystemGroupedBackground))
  .clipShape(RoundedRectangle(cornerRadius: 10))
}
