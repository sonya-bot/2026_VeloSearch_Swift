import SwiftUI

struct AlertSoundSettingView: View {
  private let audioPreviewController: AudioPreviewController
  @AppStorage(SettingsStorageKey.warningSoundID) private var selectedSoundID = 1052

  init(audioPreviewController: AudioPreviewController) {
    self.audioPreviewController = audioPreviewController
  }

  var body: some View {
    Form {
      Section {
        ForEach(SoundOption.available) { option in
          Button {
            selectedSoundID = option.id
            audioPreviewController.play(fileName: option.fileName)
          } label: {
            SettingsSelectionRow(
              title: option.name,
              isSelected: selectedSoundID == option.id
            )
          }
        }
      }
    }
    .navigationTitle("Alert Sound")
    .navigationBarTitleDisplayMode(.inline)
    .toolbar(.hidden, for: .tabBar)
    .onDisappear { audioPreviewController.stop() }
  }
}
