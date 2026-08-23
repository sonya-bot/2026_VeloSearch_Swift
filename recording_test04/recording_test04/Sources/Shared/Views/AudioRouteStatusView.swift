import AVFoundation
import SwiftUI

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

  private func statusColumn(
    title: String,
    icon: String,
    value: String,
    detail: String?
  ) -> some View {
    VStack(spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.secondary)
      HStack(spacing: 4) {
        Image(systemName: icon)
          .font(.caption)
        Text(value)
          .font(.caption)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
      }
      if let detail {
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
