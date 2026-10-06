import SwiftUI

struct DirectionModelSelectionView: View {
  @Bindable var controller: DirectionModelSelectionController
  @ObservedObject var audioIOController: AudioIOController

  var body: some View {
    List {
      Section {
        ForEach(controller.resources) { resource in
          Button {
            Task { await controller.selectModel(named: resource.id) }
          } label: {
            HStack {
              Text(resource.id)
                .foregroundStyle(.primary)
              Spacer()
              if controller.selectedModelName == resource.id {
                Image(systemName: "checkmark").foregroundStyle(.tint)
              }
            }
          }
          .disabled(!controller.canSelectModel || audioIOController.isConfigurationLocked)
        }
      } footer: {
        Text("アプリ同梱モデル。モデルは計測停止中のみ変更できます。判定閾値は40％です。")
      }
      if controller.isLoading { ProgressView("モデルを確認中…") }
      if let message = controller.message {
        Text(message).foregroundStyle(.red)
      }
      if controller.resources.isEmpty { Text("同梱モデルがありません。") }
    }
    .navigationTitle("推論モデル")
    .navigationBarTitleDisplayMode(.inline)
  }
}
