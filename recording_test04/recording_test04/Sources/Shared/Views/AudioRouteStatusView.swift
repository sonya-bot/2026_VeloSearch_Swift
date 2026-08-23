import AVFoundation
import SwiftUI

private enum AudioRouteStatusColumnStyle {
  case summary
  case modal
}

private struct AudioRouteStatusColumn: View {
  let title: String
  let icon: String
  let value: String
  let detail: String?
  let style: AudioRouteStatusColumnStyle

  var body: some View {
    VStack(spacing: style == .summary ? 2 : 5) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)

      if style == .summary {
        HStack(spacing: 4) {
          Image(systemName: icon)
            .font(.caption)
          valueText
        }
      } else {
        Image(systemName: icon)
          .font(.title2)
        valueText
        Text(detail ?? " ")
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if style == .summary, let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var valueText: some View {
    Text(value)
      .font(.caption)
      .lineLimit(1)
      .minimumScaleFactor(0.7)
  }
}

struct AudioRouteStatusButton: View {
  @ObservedObject var audioIOController: AudioIOController
  @State private var isPresented = false

  var body: some View {
    Button {
      audioIOController.refresh()
      isPresented = true
    } label: {
      let configuration = audioIOController.activeConfiguration
      HStack(spacing: 0) {
        AudioRouteStatusColumn(
          title: "Output",
          icon: configuration.outputIconName,
          value: configuration.outputConnection,
          detail: nil,
          style: .summary
        )
        Divider()
        AudioRouteStatusColumn(
          title: "Input",
          icon: configuration.inputIconName,
          value: configuration.inputConnection,
          detail: configuration.isBuiltInInput
            ? configuration.orientation.rawValue : nil,
          style: .summary
        )
        Divider()
        AudioRouteStatusColumn(
          title: "Format",
          icon: configuration.channelIconName,
          value: configuration.channelLabel,
          detail: configuration.channelDetail,
          style: .summary
        )
      }
      .frame(height: 66)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
    .buttonStyle(.plain)
    .frame(maxWidth: .infinity)
    .accessibilityLabel("Audio I/Oの状態")
    .sheet(isPresented: $isPresented) {
      AudioRouteStatusView(audioIOController: audioIOController)
        .presentationDetents([.height(210)])
    }
    .onAppear { audioIOController.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
      _ in
      audioIOController.refresh()
    }
  }

}

struct AudioRouteStatusView: View {
  @ObservedObject var audioIOController: AudioIOController

  var body: some View {
    let configuration = audioIOController.activeConfiguration
    VStack(spacing: 18) {
      Text("Audio I/O")
        .font(.headline)

      HStack(spacing: 0) {
        AudioRouteStatusColumn(
          title: "Output",
          icon: configuration.outputIconName,
          value: configuration.outputConnection,
          detail: nil,
          style: .modal
        )
        Divider()
        AudioRouteStatusColumn(
          title: "Input",
          icon: configuration.inputIconName,
          value: configuration.inputConnection,
          detail: nil,
          style: .modal
        )
        Divider()
        AudioRouteStatusColumn(
          title: "Format",
          icon: configuration.channelIconName,
          value: configuration.channelLabel,
          detail: configuration.channelDetail,
          style: .modal
        )
      }
      .frame(height: 102)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    .padding()
    .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) {
      _ in
      audioIOController.refresh()
    }
  }

}
