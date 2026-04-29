import SwiftUI

struct SettingsView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Settings")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
