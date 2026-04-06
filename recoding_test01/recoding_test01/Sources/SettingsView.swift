import SwiftUI

// MARK: - 0. Preview(Xcode)
struct SettingsView_Previews: PreviewProvider {
    static var previews: some View {
        SettingsView()
    }
}

// MARK: - 1. SettingsView(設定画面)
struct SettingsView: View {
    var body: some View {
        NavigationView {
            VStack {
                Spacer()
                Text("Hello World!!")
                    .padding()
                Text("あとでつくる")
                Spacer()
                Image(systemName: "ant.fill")
                    .imageScale(.large)
                    .padding(.bottom, 100)
                Spacer()
            }
            .navigationTitle("Settings")
        }
    }
}
