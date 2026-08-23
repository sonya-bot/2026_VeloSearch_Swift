import SwiftUI

struct TestSoundSelectionView: View {
  private let audioPreviewController: AudioPreviewController
  @AppStorage(SettingsStorageKey.selectedMonitoringSound) private var selectedMonitoringSound =
    MonitoringSoundSource.sweep5Seconds

  init(audioPreviewController: AudioPreviewController) {
    self.audioPreviewController = audioPreviewController
  }

  var body: some View {
    Form {
      Section {
        ForEach(MonitoringSoundSource.availableCases) { source in
          Button {
            selectedMonitoringSound = source
            audioPreviewController.play(fileName: source.fileName)
          } label: {
            SettingsSelectionRow(
              title: source.rawValue,
              isSelected: selectedMonitoringSound == source
            )
          }
        }
      } footer: {
        Text("選択すると確認のために音が1回再生されます。")
      }
    }
    .navigationTitle("テスト音源")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear {
      if !selectedMonitoringSound.isBundled {
        selectedMonitoringSound = .sweep5Seconds
      }
    }
    .onDisappear { audioPreviewController.stop() }
  }
}
