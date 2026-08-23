import SwiftUI

struct SettingsIconView: View {
  let systemName: String
  let color: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 14, weight: .semibold))
      .foregroundStyle(.white)
      .frame(width: 28, height: 28)
      .background(color, in: RoundedRectangle(cornerRadius: 6))
  }
}

struct SettingsRowLabel: View {
  let systemName: String
  let color: Color
  let title: String

  var body: some View {
    HStack(spacing: 12) {
      SettingsIconView(systemName: systemName, color: color)
      Text(title)
        .font(.system(size: 16))
    }
  }
}

struct SettingsNavigationRow: View {
  let systemName: String
  let color: Color
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 12) {
      SettingsRowLabel(systemName: systemName, color: color, title: title)
      Spacer()
      Text(value)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
  }
}

struct SettingsSelectionRow: View {
  let title: String
  let isSelected: Bool

  var body: some View {
    HStack {
      Text(title)
        .foregroundStyle(.primary)
      Spacer()
      if isSelected {
        Image(systemName: "checkmark")
          .foregroundStyle(.blue)
      }
    }
  }
}
