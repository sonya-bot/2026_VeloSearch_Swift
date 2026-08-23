import SwiftUI

struct PlayerTimeDisplay: View {
  let currentTime: TimeInterval
  let duration: TimeInterval
  let onTimeChanged: (TimeInterval) -> Void

  var body: some View {
    Text("\(formatted(currentTime)) / \(formatted(duration))")
      .font(.system(size: 40, weight: .thin))
      .monospacedDigit()
      .onChange(of: currentTime) { _, newTime in onTimeChanged(newTime) }
  }

  private func formatted(_ time: TimeInterval) -> String {
    String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60)
  }
}

struct PlayerPlaybackButton: View {
  let isPlaying: Bool
  let onTapped: () -> Void

  var body: some View {
    Button(action: onTapped) {
      ZStack {
        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
          .font(.system(size: 64))
          .foregroundColor(.red)
        Circle()
          .strokeBorder(Color.primary.opacity(0.2), lineWidth: 4)
          .frame(width: 74, height: 74)
      }
    }
  }
}

struct PlayerSeekSlider: View {
  let currentTime: TimeInterval
  let duration: TimeInterval
  let horizontalPadding: CGFloat
  let onSeek: (TimeInterval) -> Void

  var body: some View {
    Slider(
      value: Binding(get: { currentTime }, set: onSeek),
      in: 0...(duration > 0 ? duration : 1)
    )
    .tint(.red)
    .padding(.horizontal, horizontalPadding)
  }
}

struct PlayerStereoMeters: View {
  let leftLevel: CGFloat
  let rightLevel: CGFloat
  let leftDecibel: Float
  let rightDecibel: Float
  let spacing: CGFloat
  let meterWidth: CGFloat?

  var body: some View {
    HStack(spacing: spacing) {
      meter(level: leftLevel, decibel: leftDecibel, label: "L")
      meter(level: rightLevel, decibel: rightDecibel, label: "R")
    }
  }

  private func meter(level: CGFloat, decibel: Float, label: String) -> some View {
    VStack {
      VerticaldBMeter(
        level: level,
        label: label,
        font: .system(.caption),
        width: meterWidth ?? 56
      )
      Text("\(Int(decibel)) dB")
        .font(.system(.title3))
        .monospacedDigit()
        .frame(width: 80)
    }
  }
}
