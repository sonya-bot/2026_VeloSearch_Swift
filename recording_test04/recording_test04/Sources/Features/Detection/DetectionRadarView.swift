import SwiftUI

struct RadarView: View {
  let state: DetectionState
  let aiAngle: Int?

  var body: some View {
    ZStack {
      Canvas { context, size in
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = size.width / 2
        drawRangeCircles(in: &context, center: center, maximumRadius: maxRadius)
        drawDirectionLines(in: &context, center: center, maximumRadius: maxRadius)
      }

      if state == .detect, let aiAngle {
        SectorHighlight(state: state)
          .rotationEffect(.degrees(Double(aiAngle - 90)))
      }

      Circle()
        .fill(Color.gray)
        .frame(width: 40, height: 40)
        .symbolEffect(.pulse, isActive: state != .standby)
    }
  }

  private func drawRangeCircles(
    in context: inout GraphicsContext,
    center: CGPoint,
    maximumRadius: CGFloat
  ) {
    for index in 1...3 {
      let radius = maximumRadius * CGFloat(index) / 3
      let circle = CGRect(
        x: center.x - radius,
        y: center.y - radius,
        width: radius * 2,
        height: radius * 2
      )
      context.stroke(
        Path(ellipseIn: circle),
        with: .color(.secondary.opacity(0.2)),
        lineWidth: 1
      )
    }
  }

  private func drawDirectionLines(
    in context: inout GraphicsContext,
    center: CGPoint,
    maximumRadius: CGFloat
  ) {
    for index in 0..<8 {
      let angle = Angle.degrees(Double(index) * 45)
      var path = Path()
      path.move(to: center)
      path.addLine(
        to: CGPoint(
          x: center.x + maximumRadius * cos(CGFloat(angle.radians)),
          y: center.y + maximumRadius * sin(CGFloat(angle.radians))
        )
      )
      context.stroke(path, with: .color(.secondary.opacity(0.1)), lineWidth: 1)
    }
  }
}

private struct SectorHighlight: View {
  let state: DetectionState
  @State private var opacity = 0.8

  var body: some View {
    GeometryReader { geometry in
      Path { path in
        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let radius = geometry.size.width / 2
        path.move(to: center)
        path.addArc(
          center: center,
          radius: radius,
          startAngle: .degrees(-22.5),
          endAngle: .degrees(22.5),
          clockwise: false
        )
        path.closeSubpath()
      }
      .fill(state.themeColor.opacity(opacity))
      .onAppear {
        withAnimation(.easeInOut(duration: 0.4).repeatForever()) { opacity = 0.3 }
      }
    }
  }
}
