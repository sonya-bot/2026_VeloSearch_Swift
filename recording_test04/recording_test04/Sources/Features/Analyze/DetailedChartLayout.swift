import SwiftUI

enum DetailedChartLayout {
  static let verticalTickOffset: CGFloat = 27
  static let horizontalTickOffset: CGFloat = 13
  static let tickFont = Font.system(size: 9, design: .monospaced)
  static let readoutFont = Font.system(.caption, design: .monospaced)

  static func plotFrame(in size: CGSize) -> CGRect {
    let leading: CGFloat = 64
    let trailing: CGFloat = 24
    let top: CGFloat = 34
    let bottom: CGFloat = 46
    return CGRect(
      x: leading,
      y: top,
      width: max(size.width - leading - trailing, 1),
      height: max(size.height - top - bottom, 1)
    )
  }
}
