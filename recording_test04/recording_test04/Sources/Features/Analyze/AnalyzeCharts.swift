import SwiftUI

struct AnalyzeWaveform: View {
  let samples: [Float]

  var body: some View {
    Canvas { context, size in
      var path = Path()
      let center = size.height / 2
      let sampleCount = max(samples.count, 1)
      let strideSize = max(sampleCount / max(Int(size.width), 1), 1)
      for (pointIndex, sampleIndex) in stride(from: 0, to: samples.count, by: strideSize)
        .enumerated()
      {
        let x = CGFloat(pointIndex) / CGFloat(max(samples.count / strideSize - 1, 1)) * size.width
        let y = center - CGFloat(samples[sampleIndex]) * center
        if pointIndex == 0 {
          path.move(to: CGPoint(x: x, y: y))
        } else {
          path.addLine(to: CGPoint(x: x, y: y))
        }
      }
      context.stroke(path, with: .color(.blue), lineWidth: 1)
    }
    .background(Color.black.opacity(0.06))
  }
}

struct FrequencyResponseGraph: View {
  let channels: [[FrequencyResponsePoint]]

  var body: some View {
    Canvas { context, size in
      drawGrid(context: context, size: size)
      let colors: [Color] = [.blue, .orange]
      for (channelIndex, response) in channels.prefix(2).enumerated() {
        var path = Path()
        for (index, point) in response.enumerated() {
          let x = log10(point.frequency / 20) / log10(20_000.0 / 20.0) * size.width
          let clamped = min(max(point.smoothedDecibels, -48), 24)
          let y = CGFloat((24 - clamped) / 72) * size.height
          if index == 0 {
            path.move(to: CGPoint(x: x, y: y))
          } else {
            path.addLine(to: CGPoint(x: x, y: y))
          }
        }
        context.stroke(path, with: .color(colors[channelIndex]), lineWidth: 2)
      }
    }
    .overlay(alignment: .topLeading) {
      Text("20 Hz – 20 kHz  •  1/12 oct  •  1 kHz = 0 dB")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(8)
    }
  }

  private func drawGrid(context: GraphicsContext, size: CGSize) {
    var path = Path()
    for fraction in stride(from: 0.0, through: 1.0, by: 0.25) {
      let y = size.height * fraction
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size.width, y: y))
    }
    for frequency in [20.0, 100, 1_000, 10_000, 20_000] {
      let x = log10(frequency / 20) / log10(20_000.0 / 20.0) * size.width
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
    }
    context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
  }
}

#Preview {
  AnalyzeView(
    recordingFileStore: RecordingFileStore.shared,
    userDefaults: .standard,
    audioIOController: AudioIOController(),
    resultWriter: AnalyzeResultWriter()
  )
}
