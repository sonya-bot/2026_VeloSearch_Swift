import AVFoundation
import SwiftUI

enum AudioRouteStatusDisplayMode {
  case regular
  case compact

  var height: CGFloat {
    switch self {
    case .regular: return 96
    case .compact: return 66
    }
  }
}

struct AudioRouteStatusButton: View {
  @ObservedObject var audioIOController: AudioIOController
  let displayMode: AudioRouteStatusDisplayMode
  @State private var isPresented = false

  init(
    audioIOController: AudioIOController,
    displayMode: AudioRouteStatusDisplayMode = .regular
  ) {
    self.audioIOController = audioIOController
    self.displayMode = displayMode
  }

  var body: some View {
    Button {
      audioIOController.refresh()
      isPresented = true
    } label: {
      let configuration = audioIOController.activeConfiguration
      HStack(spacing: 0) {
        statusColumn(
          title: "Output",
          icon: configuration.outputIconName,
          value: configuration.outputConnection,
          detail: nil
        )
        Divider()
        statusColumn(
          title: "Input",
          icon: configuration.inputIconName,
          value: configuration.inputConnection,
          detail: configuration.isBuiltInInput
            ? configuration.orientation.rawValue : nil
        )
        Divider()
        statusColumn(
          title: "Format",
          icon: configuration.channelIconName,
          value: configuration.channelLabel,
          detail: configuration.channelDetail
        )
      }
      .frame(height: displayMode.height)
      .background(Color(uiColor: .secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 16))
    }
    .buttonStyle(.plain)
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

  private func statusColumn(
    title: String,
    icon: String,
    value: String,
    detail: String?
  ) -> some View {
    VStack(spacing: displayMode == .compact ? 2 : 4) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(displayMode == .compact ? .caption : .title3)
        Text(value)
          .font(displayMode == .compact ? .caption : .subheadline.weight(.semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      if displayMode == .regular, let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      } else if displayMode == .compact, let detail {
        Text(detail)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
    .frame(maxWidth: .infinity)
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
        statusColumn(
          title: "Output",
          icon: configuration.outputIconName,
          value: configuration.outputConnection,
          detail: nil
        )
        Divider()
        statusColumn(
          title: "Input",
          icon: configuration.inputIconName,
          value: configuration.inputConnection,
          detail: nil
        )
        Divider()
        statusColumn(
          title: "Format",
          icon: configuration.channelIconName,
          value: configuration.channelLabel,
          detail: configuration.channelDetail
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

  private func statusColumn(
    title: String,
    icon: String,
    value: String,
    detail: String?
  ) -> some View {
    VStack(spacing: 5) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Image(systemName: icon)
        .font(.title2)
      Text(value)
        .font(.caption)
        .lineLimit(1)
      Text(detail ?? " ")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }
    .frame(maxWidth: .infinity)
  }
}
