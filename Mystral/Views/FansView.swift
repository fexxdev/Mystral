import SwiftUI

struct FansView: View {
    let fanController: FanController
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(fanController.fans) { fan in
                    FanDetailCard(fan: fan, fanController: fanController)
                }
                if fanController.fans.isEmpty {
                    ContentUnavailableView("No Fans Detected", systemImage: "fan.slash",
                                           description: Text("Could not read fan information from SMC."))
                }
            }.padding()
        }.navigationTitle("Fans")
    }
}

struct FanDetailCard: View {
    let fan: Fan
    let fanController: FanController
    @State private var isOverriding = false

    private var overridePercentage: Binding<Double> {
        Binding(
            get: { fanController.manualOverrides[fan.id] ?? fan.percentage },
            set: { fanController.manualOverrides[fan.id] = $0 }
        )
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "fan").font(.title2)
                    Text(fan.name).font(.title3.bold())
                    Spacer()
                    Text(fan.mode == .forced ? "Forced" : "Auto")
                        .font(.caption).padding(.horizontal, 8).padding(.vertical, 2)
                        .background(fan.mode == .forced ? Color.orange.opacity(0.2) : Color.green.opacity(0.2))
                        .clipShape(Capsule())
                }
                HStack(spacing: 40) {
                    VStack(alignment: .leading) {
                        Text("Current").font(.caption).foregroundStyle(.secondary)
                        Text("\(fan.currentRPM) RPM").font(.system(size: 20, design: .rounded))
                    }
                    VStack(alignment: .leading) {
                        Text("Target").font(.caption).foregroundStyle(.secondary)
                        Text("\(fan.targetRPM) RPM").font(.system(size: 20, design: .rounded))
                    }
                    VStack(alignment: .leading) {
                        Text("Range").font(.caption).foregroundStyle(.secondary)
                        Text("\(fan.minRPM)–\(fan.maxRPM) RPM").font(.system(size: 14, design: .rounded))
                    }
                }
                Divider()
                Toggle("Manual Override", isOn: $isOverriding)
                    .onChange(of: isOverriding) { _, newValue in
                        if !newValue { fanController.clearManualOverride(for: fan.id) }
                    }
                if isOverriding {
                    HStack {
                        Text("\(Int(overridePercentage.wrappedValue))%").frame(width: 50).font(.system(.body, design: .rounded))
                        Slider(value: overridePercentage, in: 0...100, step: 5)
                    }
                }
            }.padding()
        }
    }
}
