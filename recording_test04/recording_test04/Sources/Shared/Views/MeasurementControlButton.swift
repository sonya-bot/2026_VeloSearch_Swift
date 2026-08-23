import SwiftUI

struct MeasurementControlButton: View {
  let idleTitle: String
  let activeTitle: String
  let isActive: Bool
  let tint: Color
  let isDisabled: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      ZStack {
        Circle()
          .strokeBorder(Color.primary.opacity(0.25), lineWidth: 4)
          .frame(width: 76, height: 76)
        Circle()
          .fill(tint)
          .frame(width: 66, height: 66)
        Text(isActive ? activeTitle : idleTitle)
          .font(.headline)
          .fontWeight(.semibold)
          .foregroundStyle(.white)
          .lineLimit(1)
          .minimumScaleFactor(0.65)
          .padding(.horizontal, 7)
      }
      .contentShape(Circle())
    }
    .buttonStyle(.plain)
    .disabled(isDisabled)
    .opacity(isDisabled ? 0.35 : 1)
    .sensoryFeedback(.impact(flexibility: .solid), trigger: isActive)
    .accessibilityLabel(isActive ? activeTitle : idleTitle)
  }
}
