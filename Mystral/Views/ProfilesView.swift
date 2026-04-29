import SwiftUI

struct ProfilesView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Profiles")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
