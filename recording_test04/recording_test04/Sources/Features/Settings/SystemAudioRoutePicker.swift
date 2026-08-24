import AVKit
import SwiftUI

struct SystemAudioRoutePicker: UIViewRepresentable {
  let onRouteSelectionStarted: () -> Void
  let onRouteSelectionCompleted: () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(
      onRouteSelectionStarted: onRouteSelectionStarted,
      onRouteSelectionCompleted: onRouteSelectionCompleted
    )
  }

  func makeUIView(context: Context) -> AVRoutePickerView {
    let routePicker = AVRoutePickerView(frame: .zero)
    routePicker.delegate = context.coordinator
    routePicker.prioritizesVideoDevices = false
    routePicker.tintColor = .systemBlue
    return routePicker
  }

  func updateUIView(_ routePicker: AVRoutePickerView, context: Context) {
    context.coordinator.onRouteSelectionStarted = onRouteSelectionStarted
    context.coordinator.onRouteSelectionCompleted = onRouteSelectionCompleted
  }

  final class Coordinator: NSObject, AVRoutePickerViewDelegate {
    var onRouteSelectionStarted: () -> Void
    var onRouteSelectionCompleted: () -> Void

    init(
      onRouteSelectionStarted: @escaping () -> Void,
      onRouteSelectionCompleted: @escaping () -> Void
    ) {
      self.onRouteSelectionStarted = onRouteSelectionStarted
      self.onRouteSelectionCompleted = onRouteSelectionCompleted
    }

    func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      onRouteSelectionStarted()
    }

    func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
      onRouteSelectionCompleted()
    }
  }
}
