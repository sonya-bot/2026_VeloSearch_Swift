import SwiftUI

struct MeasurementRepeatStepper: View {
  @Binding var repeatCount: Int
  let isDisabled: Bool

  var body: some View {
    Stepper(value: $repeatCount, in: 1...99) {
      Text("Repeat \(repeatCount)")
        .font(.subheadline)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
    .disabled(isDisabled)
    .padding(.horizontal, 10)
    .frame(height: 48)
    .background(Color(uiColor: .secondarySystemGroupedBackground))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}
