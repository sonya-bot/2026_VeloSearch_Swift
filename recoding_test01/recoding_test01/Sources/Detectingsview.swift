import SwiftUI

// MARK: - 0. Preview(Xcode)
struct DetectingsView_Previews: PreviewProvider {
    static var previews: some View {
        DetectingsView()
    }
}

// MARK: - 1. DetectingsView(検出画面)
struct DetectingsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Text("Hello World!!")
                    .padding()
                Text("ここには検出画面を表示する予定です")
                Spacer()
                Image(systemName: "ant.fill")
                    .imageScale(.large)
                    .padding(.bottom, 100)
                Spacer()
            }
            .navigationTitle("Detectings")
        }
    }
}
