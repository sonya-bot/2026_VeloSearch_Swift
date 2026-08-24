import SwiftUI

struct DetailedAnalyzeWaveform: View {
  let samples: [Float]
  let sampleRate: Double

  @State private var selectedSampleIndex: Int?

  private let amplitudeTicks: [Double] = [1, 0.5, 0, -0.5, -1]
  private let timeFractions: [Double] = [0, 0.25, 0.5, 0.75, 1]

  var body: some View {
    GeometryReader { geometry in
      let plotFrame = DetailedChartLayout.plotFrame(in: geometry.size)
      ZStack {
        waveformCanvas(plotFrame: plotFrame)
        waveformLabels(in: geometry.size, plotFrame: plotFrame)
        if let selectedSampleIndex {
          waveformReadout(for: selectedSampleIndex, plotFrame: plotFrame)
        }
      }
      .contentShape(Rectangle())
      .gesture(selectionGesture(in: plotFrame))
    }
    .accessibilityLabel("音量波形。横軸は時間、縦軸は正規化振幅")
    .accessibilityValue(accessibilityReadout)
  }

  private func waveformCanvas(plotFrame: CGRect) -> some View {
    Canvas { context, _ in
      drawGrid(context: context, plotFrame: plotFrame)
      drawWaveform(context: context, plotFrame: plotFrame)
      drawCursor(context: context, plotFrame: plotFrame)
    }
  }

  private func drawGrid(context: GraphicsContext, plotFrame: CGRect) {
    var grid = Path()
    for amplitude in amplitudeTicks {
      let y = yPosition(for: amplitude, in: plotFrame)
      grid.move(to: CGPoint(x: plotFrame.minX, y: y))
      grid.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
    }
    for fraction in timeFractions {
      let x = plotFrame.minX + plotFrame.width * fraction
      grid.move(to: CGPoint(x: x, y: plotFrame.minY))
      grid.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
    }
    context.stroke(grid, with: .color(.secondary.opacity(0.25)), lineWidth: 0.5)
    var border = Path()
    border.addRect(plotFrame)
    context.stroke(border, with: .color(.secondary.opacity(0.5)), lineWidth: 1)
  }

  private func drawWaveform(context: GraphicsContext, plotFrame: CGRect) {
    guard !samples.isEmpty else { return }
    var path = Path()
    let strideSize = max(samples.count / max(Int(plotFrame.width), 1), 1)
    for (pointIndex, sampleIndex) in stride(from: 0, to: samples.count, by: strideSize)
      .enumerated()
    {
      let x = xPosition(forSampleAt: sampleIndex, in: plotFrame)
      let y = yPosition(for: Double(samples[sampleIndex]), in: plotFrame)
      if pointIndex == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    context.stroke(path, with: .color(.blue), lineWidth: 1.25)
  }

  private func drawCursor(context: GraphicsContext, plotFrame: CGRect) {
    guard let selectedSampleIndex, samples.indices.contains(selectedSampleIndex) else { return }
    let x = xPosition(forSampleAt: selectedSampleIndex, in: plotFrame)
    let y = yPosition(for: Double(samples[selectedSampleIndex]), in: plotFrame)
    var cursor = Path()
    cursor.move(to: CGPoint(x: x, y: plotFrame.minY))
    cursor.addLine(to: CGPoint(x: x, y: plotFrame.maxY))
    cursor.move(to: CGPoint(x: plotFrame.minX, y: y))
    cursor.addLine(to: CGPoint(x: plotFrame.maxX, y: y))
    context.stroke(cursor, with: .color(.red.opacity(0.7)), lineWidth: 1)
    context.fill(
      Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6)), with: .color(.red))
  }

  @ViewBuilder
  private func waveformLabels(in size: CGSize, plotFrame: CGRect) -> some View {
    ForEach(amplitudeTicks, id: \.self) { amplitude in
      Text(String(format: "%+.1f", amplitude))
        .font(DetailedChartLayout.tickFont)
        .foregroundStyle(.secondary)
        .position(
          x: plotFrame.minX - DetailedChartLayout.verticalTickOffset,
          y: yPosition(for: amplitude, in: plotFrame)
        )
    }
    ForEach(timeFractions, id: \.self) { fraction in
      Text(formattedTime(duration * fraction))
        .font(DetailedChartLayout.tickFont)
        .foregroundStyle(.secondary)
        .position(
          x: plotFrame.minX + plotFrame.width * fraction,
          y: plotFrame.maxY + DetailedChartLayout.horizontalTickOffset
        )
    }
    Text("Time (s)")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .position(x: plotFrame.midX, y: size.height - 9)
    Text("Amplitude (FS)")
      .font(.caption2)
      .foregroundStyle(.secondary)
      .rotationEffect(.degrees(-90))
      .position(x: 10, y: plotFrame.midY)
  }

  private func waveformReadout(for sampleIndex: Int, plotFrame: CGRect) -> some View {
    Text(
      String(
        format: "%.3f s  ·  %+.3f",
        Double(sampleIndex) / sampleRate,
        samples[sampleIndex]
      )
    )
    .font(DetailedChartLayout.readoutFont)
    .padding(.horizontal, 8)
    .padding(.vertical, 4)
    .background(.regularMaterial, in: Capsule())
    .position(x: plotFrame.midX, y: plotFrame.minY + 17)
  }

  private func selectionGesture(in plotFrame: CGRect) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        guard !samples.isEmpty else { return }
        let clampedX = min(max(value.location.x, plotFrame.minX), plotFrame.maxX)
        let fraction = (clampedX - plotFrame.minX) / max(plotFrame.width, 1)
        selectedSampleIndex = Int((fraction * CGFloat(samples.count - 1)).rounded())
      }
  }

  private var duration: Double {
    guard sampleRate > 0, samples.count > 1 else { return 0 }
    return Double(samples.count - 1) / sampleRate
  }

  private var accessibilityReadout: String {
    guard let selectedSampleIndex, samples.indices.contains(selectedSampleIndex) else {
      return "グラフをタップまたはドラッグして値を確認できます"
    }
    return String(
      format: "時間 %.3f秒、振幅 %+.3f",
      Double(selectedSampleIndex) / sampleRate,
      samples[selectedSampleIndex]
    )
  }

  private func xPosition(forSampleAt sampleIndex: Int, in plotFrame: CGRect) -> CGFloat {
    let denominator = max(samples.count - 1, 1)
    return plotFrame.minX + CGFloat(sampleIndex) / CGFloat(denominator) * plotFrame.width
  }

  private func yPosition(for amplitude: Double, in plotFrame: CGRect) -> CGFloat {
    let clampedAmplitude = min(max(amplitude, -1), 1)
    return plotFrame.minY + CGFloat((1 - clampedAmplitude) / 2) * plotFrame.height
  }

  private func formattedTime(_ seconds: Double) -> String {
    seconds >= 10 ? String(format: "%.1f", seconds) : String(format: "%.2f", seconds)
  }
}
