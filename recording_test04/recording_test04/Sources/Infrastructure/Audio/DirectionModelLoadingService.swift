import Foundation

struct DirectionModelResource: Identifiable, Equatable {
  let url: URL
  var id: String { url.deletingPathExtension().lastPathComponent }
}

protocol DirectionModelLoading {
  var resources: [DirectionModelResource] { get }
  func load(_ resource: DirectionModelResource) async throws -> DirectionPredicting
}

final class DirectionModelLoadingService: DirectionModelLoading {
  let resources: [DirectionModelResource]
  private let queue = DispatchQueue(label: "recording.model-loading", qos: .userInitiated)

  init(bundle: Bundle) {
    let urls = bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? []
    resources = urls.map { DirectionModelResource(url: $0) }.sorted { $0.id < $1.id }
  }

  func load(_ resource: DirectionModelResource) async throws -> DirectionPredicting {
    try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          continuation.resume(returning: try DirectionModelService(url: resource.url))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }
}
