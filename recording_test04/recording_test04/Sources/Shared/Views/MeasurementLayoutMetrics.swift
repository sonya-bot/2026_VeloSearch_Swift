import SwiftUI

enum MeasurementLayoutMetrics {
  static let horizontalPadding: CGFloat = 16
  static let landscapeVerticalPadding: CGFloat = 8
  static let landscapeColumnSpacing: CGFloat = 16

  static func landscapeLeadingWidth(for availableWidth: CGFloat) -> CGFloat {
    (availableWidth - landscapeColumnSpacing) / 3
  }

  static func landscapeTrailingWidth(for availableWidth: CGFloat) -> CGFloat {
    (availableWidth - landscapeColumnSpacing) * 2 / 3
  }
}

struct MeasurementLandscapeLayout<LeadingContent: View, TrailingContent: View>: View {
  private let leadingContent: (CGSize) -> LeadingContent
  private let trailingContent: (CGSize) -> TrailingContent

  init(
    @ViewBuilder leadingContent: @escaping (CGSize) -> LeadingContent,
    @ViewBuilder trailingContent: @escaping (CGSize) -> TrailingContent
  ) {
    self.leadingContent = leadingContent
    self.trailingContent = trailingContent
  }

  var body: some View {
    GeometryReader { geometry in
      HStack(spacing: MeasurementLayoutMetrics.landscapeColumnSpacing) {
        leadingContent(geometry.size)
          .frame(
            width: MeasurementLayoutMetrics.landscapeLeadingWidth(
              for: geometry.size.width
            )
          )

        trailingContent(geometry.size)
          .frame(
            width: MeasurementLayoutMetrics.landscapeTrailingWidth(
              for: geometry.size.width
            )
          )
      }
      .frame(maxHeight: .infinity)
    }
    .padding(.horizontal, MeasurementLayoutMetrics.horizontalPadding)
    .padding(.vertical, MeasurementLayoutMetrics.landscapeVerticalPadding)
  }
}
