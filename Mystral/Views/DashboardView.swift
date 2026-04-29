import SwiftUI
import Charts

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager

    private var cpuAvgTemp: Double {
        let s = fanController.sensors.filter { $0.id.hasPrefix("Tp") }
        guard !s.isEmpty else { return 0 }
        return s.map(\.temperature).reduce(0, +) / Double(s.count)
    }

    private var gpuAvgTemp: Double {
        let s = fanController.sensors.filter { $0.id.hasPrefix("Tg") }
        guard !s.isEmpty else { return 0 }
        return s.map(\.temperature).reduce(0, +) / Double(s.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 20) {
                    TemperatureCard(title: "CPU", temperature: cpuAvgTemp)
                    TemperatureCard(title: "GPU", temperature: gpuAvgTemp)
                }
                GroupBox("Fans") {
                    HStack(spacing: 20) {
                        ForEach(fanController.fans) { fan in FanGaugeView(fan: fan) }
                    }.padding()
                }
                GroupBox("Active Profile") {
                    HStack {
                        if let profile = profileManager.activeProfile {
                            Image(systemName: profile.icon).font(.title2)
                            Text(profile.name).font(.title3)
                        } else {
                            Text("No profile active").foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Profile", selection: Binding(
                            get: { profileManager.activeProfileId },
                            set: { profileManager.activeProfileId = $0 }
                        )) {
                            ForEach(profileManager.allProfiles) { p in Text(p.name).tag(Optional(p.id)) }
                        }.frame(width: 200)
                    }.padding()
                }
            }.padding()
        }.navigationTitle("Dashboard")
    }
}

struct TemperatureCard: View {
    let title: String
    let temperature: Double
    private var color: Color {
        switch temperature {
        case ..<50: .green
        case 50..<70: .yellow
        case 70..<85: .orange
        default: .red
        }
    }
    var body: some View {
        GroupBox(title) {
            VStack {
                Text("\(Int(temperature))°C")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                ProgressView(value: min(temperature / 110.0, 1.0)).tint(color)
            }.padding()
        }.frame(maxWidth: .infinity)
    }
}

struct FanGaugeView: View {
    let fan: Fan
    var body: some View {
        VStack(spacing: 8) {
            Text(fan.name).font(.headline)
            Text("\(fan.currentRPM) RPM").font(.system(size: 24, weight: .medium, design: .rounded))
            ProgressView(value: fan.percentage / 100.0).tint(.blue)
            Text("\(Int(fan.percentage))%").font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity)
    }
}
