import SwiftUI

/// Lightweight entry point for previews and existing callers.
public struct ContentView: View {
  private let dependencies: AppDependencies

  public init() {
    dependencies = .live
  }

  init(dependencies: AppDependencies) {
    self.dependencies = dependencies
  }

  public var body: some View {
    AppRootView(dependencies: dependencies)
  }
}

#Preview {
  ContentView()
}
