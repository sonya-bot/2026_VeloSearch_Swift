import SwiftUI

struct MicSourceSettingView: View {
  @Binding var selectedMicSource: MicSourceOption
  let isEnabled: Bool

  var body: some View {
    Form {
      Section {
        ForEach(MicSourceOption.allCases) { option in
          Button {
            selectedMicSource = option
          } label: {
            SettingsSelectionRow(
              title: option.rawValue,
              isSelected: selectedMicSource == option
            )
          }
        }
      } header: {
        Text("ペアマイクの選択")
      }

      Section {
        HStack(spacing: 15) {
          microphoneLabel(title: "底面", color: .blue)
          Image(systemName: "plus")
            .foregroundStyle(.secondary)
          microphoneLabel(
            title: selectedMicSource == .back ? "背面" : "前面",
            color: .green
          )
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
      } header: {
        Text("Mic Preview")
      }
    }
    .navigationTitle("ペアマイク")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .disabled(!isEnabled)
  }

  private func microphoneLabel(title: String, color: Color) -> some View {
    VStack(spacing: 6) {
      Image(systemName: "mic.fill")
        .font(.title2)
        .foregroundStyle(color)
      Text(title)
        .font(.subheadline)
    }
    .frame(width: 70)
  }
}
