import SwiftUI

// MARK: ボトムシート用コンポーネント
struct EditSheetView: View {
  @Binding var isPresented: Bool
  @Binding var sheetDetent: PresentationDetent
  @Binding var editFileName: String
  @Binding var editExperimenter: String
  @Binding var editScene: String
  @Binding var editWeather: String
  @Binding var editTemperature: String
  @Binding var editHumidity: String
  @Binding var editNote: String

  var csvURL: URL?
  let showsCSVSection: Bool
  let recordingFileStore: RecordingFileStoring
  var onSave: () -> Void

  // シートが引き上げられているか（.height(180) 以外か）を判定
  var isEditingMode: Bool {
    sheetDetent != .height(180)
  }

  var body: some View {
    VStack(spacing: 0) {
      // 引き上げられている時（編集モード）だけヘッダーを表示
      if isEditingMode {
        HStack {
          Spacer()

          Button("保存") {
            onSave()
            isPresented = false
            sheetDetent = .height(180)  // 保存後に元の高さに閉じる
          }
          .bold()
          .foregroundColor(.blue)
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
      }

      // リスト形式の入力フォーム
      List {
        Section {
          TextField("ファイル名 (例: DRTF_Angle045_Take1)", text: $editFileName)
            .font(.title3)
            .bold()
            .padding(.vertical, 4)
            .disabled(!isEditingMode)  // 引き上げていない時は編集不可
        } header: {
          Text("File Name")
        }

        // 引き上げられている時だけ他の項目も表示
        if isEditingMode {
          Section(header: Text("Details")) {
            HStack {
              Text("Experimenter")
              Spacer()
              TextField("Name", text: $editExperimenter).multilineTextAlignment(.trailing)
            }
            HStack {
              Text("Scene")
              Spacer()
              TextField("Pattern", text: $editScene).multilineTextAlignment(.trailing)
            }
          }

          Section(header: Text("Environment")) {
            HStack {
              Text("Weather")
              Spacer()
              TextField("Weather", text: $editWeather).multilineTextAlignment(.trailing)
            }
            HStack {
              Text("Temperature")
              Spacer()
              TextField("Temp", text: $editTemperature)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
              Text("°C").foregroundColor(.secondary)
            }
            HStack {
              Text("Humidity")
              Spacer()
              TextField("Humid", text: $editHumidity)
                .multilineTextAlignment(.trailing).keyboardType(.decimalPad)
              Text("%").foregroundColor(.secondary)
            }
          }

          Section(header: Text("Note")) {
            TextEditor(text: $editNote)
              .frame(minHeight: 80)
          }

          if showsCSVSection {
            Section(
              header: HStack {
                Text("CSV Data")
                Spacer()
                if let csvURL {
                  ShareLink(item: csvURL) {
                    Label("Share", systemImage: "square.and.arrow.up")
                      .textCase(.none)
                      .font(.body)
                      .foregroundColor(.blue)
                  }
                }
              }
            ) {
              CompanionCSVAccessLink(
                csvURL: csvURL,
                recordingFileStore: recordingFileStore,
                style: .listRow
              )
            }
          }
        }
      }
      .listStyle(.insetGrouped)
    }
  }
}
