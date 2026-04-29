import SwiftUI

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    var body: some View {
        Text("Dashboard")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
