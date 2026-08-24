import SwiftUI

struct DetailedFrequencyResponseGraph: View {
  let channels: [[FrequencyResponsePoint]]

  @State private var selectedFrequency: Double?

  private let frequencies: [Double] = [20, 50, 100, 200, 500, 1_000, 2_000, 5_000, 10_000, 20_000]
  private let decibelTicks: [Double] = [24, 12, 0, -12, -24, -36, -48]
  private let channelColors: [Color] = [.blue, .orange]

  var body: some View {
    GeometryReader { geometry in
      let plotFrame = DetailedChartLayout.plotFrame(in: geometry.size)
      ZStack {
        responseCanvas(plotFrame: plotFrame)
        responseLabels(in: geometry.size, plotFrame: plotFrame)
        channelLegend(plotFrame: plotFrame)
        if let selectedFrequency {
          responseReadout(at: selectedFrequency, plotFrame: plotFrame)
        }
      }
      .contentShape(Rectangle())
      .gesture(selectionGesture(in: plotFrame))
    }
    .accessibilityLabel("音響特性グラフ。横軸は周波数、縦軸は相対レベル")
    .accessibilityValue(accessibilityReadout)
  }

  private func responseCanvas(plotFrame: CGRect) -> some View {
    Canvas { context, _ in
      drawGrid(context: context, plotFrame: plotFrame)
      drawResponses(context: context, plotFrame: plotFrame)
      drawCursor(context: context, plotFrame: plotFrame)
    }
  }

  private func drawGrid(context: GraphicsContext, plotFrame: CGRect) {
    var grid = Path()
    for decibels in decibelTicks {
      let y = yPosition(for: decibels, in: plotFrame)
      grid.move(to: CGPoint(x: plotFrame.minX, y: y))
      grid.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
    }
    for frequency in frequencies {
      let x = xPosition(for: frequency, in: plotFrame)
      grid.move(to: CGPoint(x: x, y: plotFrame.minY))
      grid.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
    }
    context.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
    var border = Path()
    border.addRect(plotFrame)
    context.stroke(border, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
  }

  private func drawResponses(context: GraphicsContext, plotFrame: CGRect) {
    for (channelIndex, response) in channels.prefix(2).enumerated() {
      var path = Path()
      var hasPoint = false
      for point in response where point.frequency >= 20 && point.frequency <= 20_000 {
        let position = CGPoint(
          x: xPosition(for: point.frequency, in: plotFrame),
          y: yPosition(for: point.smoothedDecibels, in: plotFrame)
        )
        if hasPoint {
          path.addLine(to: position)
        } else {
          path.move(to: position)
          hasPoint = true
        }
      }
      context.stroke(path, with: .color(channelColors[channelIndex]), lineWidth: 2)
    }
  }

  private func drawCursor(context: GraphicsContext, plotFrame: CGRect) {
    guard let selectedFrequency else { return }
    let x = xPosition(for: selectedFrequency, in: plotFrame)
    var cursor = Path()
    cursor.move(to: CGPoint(x: x, y: plotFrame.minY))
    cursor.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
    context.stroke(cursor, with: .color(.red.opacity(0.7)), lineWidth: 1)
    for (channelIndex, point) in nearestPoints(to: selectedFrequency).enumerated() {
      guard let point else { continue }
      let y = yPosition(for: point.smoothedDecibels, in: plotFrame)
      context.fill(
        Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)),
        with: .color(channelColors[channelIndex])
      )
    }
  }

  @ViewBuilder
  private func responseLabels(in size: CGSize, plotFrame: CGRect) -> some View {
    ForEach(decibelTicks, id: \.self) { decibels in
      Text(String(format: "%+.0f", decibels))
        .font(DetailedChartLayout.tickFont)
        .foregroundStyle(.secondary)
        .position(
          x: plotFrame.minX - DetailedChartLayout.verticalTickOffset,
          y: yPosition(for: decibels, in: plotFrame)
        )
    }
    ForEach(frequencies, id: \.self) { frequency in
      Text(axisFrequencyLabel(frequency))
        .font(DetailedChartLayout.tickFont)
        .foregroundStyle(.secondary)
        .position(
          x: xPosition(for: frequency, in: plotFrame),
          y: plotFrame.maxY + DetailedChartLayout.horizontalTickOffset
        )
    }
    Text("Frequency (Hz)")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .position(x: plotFrame.midX, y: size.height - 9)
    Text("Level (dB)")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .rotationEffect(.degrees(-90))
      .position(x: 10, y: plotFrame.midY)
  }

  private func channelLegend(plotFrame: CGRect) -> some View {
    HStack(spacing: 10) {
      ForEach(Array(channels.prefix(2).indices), id: \.self) { channelIndex in
        Label {
          Text("CH\(channelIndex + 1)")
        } icon: {
          Circle()
            .fill(channelColors[channelIndex])
            .frame(width: 7, height: 7)
        }
      }
    }
    .font(.caption2)
    .foregroundStyle(.secondary)
    .position(x: plotFrame.minX + 48, y: 15)
  }

  private func responseReadout(at frequency: Double, plotFrame: CGRect) -> some View {
    Text(readout(at: frequency))
      .font(DetailedChartLayout.readoutFont)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 8)
      .padding(.vertical, 4)
      .background(.regularMaterial, in: Capsule())
      .frame(maxWidth: max(plotFrame.width - 16, 1))
      .position(x: plotFrame.midX, y: plotFrame.minY + 17)
  }

  private func selectionGesture(in plotFrame: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
        let fraction = Double((clampedX - plotFrame.minX) / max(plotFrame.width, 1))
        selectedFrequency = 20 * pow(20_000.0 / 20.0, fraction)
      }
  }

  private var accessibilityReadout: String {
    guard let selectedFrequency else {
      return "グラフをタップまたはドラッグして値を確認できます"
    }
    return readout(at: selectedFrequency)
  }

  private func readout(at frequency: Double) -> String {
    let values = nearestPoints(to: frequency).enumerated().compactMap { channelIndex, point in
      point.map { String(format: "CH%d %.1f dB", channelIndex + 1, $0.smoothedDecibels) }
    }
    return ([frequencyLabel(frequency)] + values).joined(separator: "  ·  ")
  }

  private func nearestPoints(to frequency: Double) -> [FrequencyResponsePoint?] {
    channels.prefix(2).map { response in
      response.min {
        abs(log($0.frequency / frequency)) < abs(log($1.frequency / frequency))
      }
    }
  }

  private func xPosition(for frequency: Double, in plotFrame: CGRect) -> CGFloat {
    let clampedFrequency = min(max(frequency, 20), 20_000)
    let fraction = log10(clampedFrequency / 20) / log10(20_000.0 / 20.0)
    return plotFrame.minX + CGFloat(fraction) * plotFrame.width
  }

  private func yPosition(for decibels: Double, in plotFrame: CGRect) -> CGFloat {
    let clampedDecibels = min(max(decibels, -48), 24)
    return plotFrame.minY + CGFloat((24 - clampedDecibels) / 72) * plotFrame.height
  }

  private func frequencyLabel(_ frequency: Double) -> String {
    if frequency >= 1_000 {
      let kilohertz = frequency / 1_000
      return kilohertz.rounded() == kilohertz
        ? String(format: "%.0f kHz", kilohertz)
        : String(format: "%.2f kHz", kilohertz)
    }
    return String(format: "%.0f Hz", frequency)
  }

  private func axisFrequencyLabel(_ frequency: Double) -> String {
    frequency >= 1_000
      ? String(format: "%.0fk", frequency / 1_000)
      : String(format: "%.0f", frequency)
  }
}
