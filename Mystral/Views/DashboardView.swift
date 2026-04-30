import SwiftUI

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    @State private var cpuCoresExpanded = false
    @State private var gpuCoresExpanded = false

    private var cpuCoreSensors: [Sensor] {
        SensorRegistry.cpuCoreSensors(from: fanController.sensors)
    }

    private var gpuCoreSensors: [Sensor] {
        SensorRegistry.gpuCoreSensors(from: fanController.sensors)
    }

    private var cpuSummary: [Sensor] {
        SensorRegistry.cpuSummarySensors(from: fanController.sensors)
    }

    private var cpuMax: Double {
        cpuCoreSensors.map(\.temperature).max() ?? cpuSummary.first(where: { $0.id == "TCMz" })?.temperature ?? 0
    }

    private var cpuAvg: Double {
        let cores = cpuCoreSensors
        guard !cores.isEmpty else { return 0 }
        return cores.map(\.temperature).reduce(0, +) / Double(cores.count)
    }

    private var gpuMax: Double {
        gpuCoreSensors.map(\.temperature).max() ?? 0
    }

    private var gpuAvg: Double {
        let cores = gpuCoreSensors
        guard !cores.isEmpty else { return 0 }
        return cores.map(\.temperature).reduce(0, +) / Double(cores.count)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if fanController.sensors.isEmpty && fanController.fans.isEmpty {
                    ContentUnavailableView("No SMC Data", systemImage: "exclamationmark.triangle",
                                           description: Text("Waiting for SMC helper to start. You may be prompted for your password."))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    temperatureOverview
                    fansSection
                    profileSection
                }
            }.padding()
        }.navigationTitle("Dashboard")
    }

    private var temperatureOverview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                TemperatureCard(title: "CPU", max: cpuMax, avg: cpuAvg,
                                sensorLabel: "TCMz / \(cpuCoreSensors.count) cores")
                TemperatureCard(title: "GPU", max: gpuMax, avg: gpuAvg,
                                sensorLabel: "\(gpuCoreSensors.count) cores")
            }

            if !cpuSummary.isEmpty {
                GroupBox("CPU Summary") {
                    HStack(spacing: 24) {
                        ForEach(cpuSummary, id: \.id) { sensor in
                            VStack(spacing: 2) {
                                Text(sensor.name).font(.caption).foregroundStyle(.secondary)
                                Text("\(String(format: "%.1f", sensor.temperature))°C")
                                    .font(.system(.body, design: .rounded))
                                    .foregroundStyle(temperatureColor(sensor.temperature))
                                Text(sensor.id).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                    }.padding(.vertical, 8)
                }
            }

            if !cpuCoreSensors.isEmpty {
                coreGrid(title: "CPU Cores", sensors: cpuCoreSensors, isExpanded: $cpuCoresExpanded)
            }

            if !gpuCoreSensors.isEmpty {
                coreGrid(title: "GPU Cores", sensors: gpuCoreSensors, isExpanded: $gpuCoresExpanded)
            }
        }
    }

    private func coreGrid(title: String, sensors: [Sensor], isExpanded: Binding<Bool>) -> some View {
        let avg = sensors.map(\.temperature).reduce(0, +) / Double(sensors.count)
        let max = sensors.map(\.temperature).max() ?? 0
        return GroupBox {
            DisclosureGroup(isExpanded: isExpanded) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 6), spacing: 8) {
                    ForEach(sensors, id: \.id) { sensor in
                        VStack(spacing: 2) {
                            Text("\(String(format: "%.0f", sensor.temperature))°")
                                .font(.system(.body, design: .rounded).weight(.medium))
                                .foregroundStyle(temperatureColor(sensor.temperature))
                            Text(sensor.id).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(temperatureColor(sensor.temperature).opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            } label: {
                HStack {
                    Text(title).font(.headline)
                    Text("\(sensors.count)").font(.caption).foregroundStyle(.tertiary)
                    Spacer()
                    Text("Avg: \(String(format: "%.1f", avg))°C")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Max: \(String(format: "%.1f", max))°C")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
            .padding(8)
        }
    }

    private var fansSection: some View {
        GroupBox("Fans") {
            if fanController.fans.isEmpty {
                Text("No fans detected").foregroundStyle(.secondary).padding()
            } else {
                HStack(spacing: 20) {
                    ForEach(fanController.fans) { fan in FanGaugeView(fan: fan) }
                }.padding()
            }
        }
    }

    private var profileSection: some View {
        GroupBox("Active Profile") {
            HStack {
                if let profile = profileManager.activeProfile {
                    Image(systemName: profile.icon).font(.title2)
                    VStack(alignment: .leading) {
                        Text(profile.name).font(.title3)
                        if !profile.sensorKey.isEmpty {
                            Text("Driving: \(SensorRegistry.nameForKey(profile.sensorKey)) (\(profile.sensorKey))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Driving: CPU Average").font(.caption).foregroundStyle(.secondary)
                        }
                    }
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
    }

    private func temperatureColor(_ temp: Double) -> Color {
        switch temp {
        case ..<50: .green
        case 50..<70: .yellow
        case 70..<85: .orange
        default: .red
        }
    }
}

struct TemperatureCard: View {
    let title: String
    let max: Double
    let avg: Double
    let sensorLabel: String

    private var color: Color {
        switch max {
        case ..<50: .green
        case 50..<70: .yellow
        case 70..<85: .orange
        default: .red
        }
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 4) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(sensorLabel).font(.caption2).foregroundStyle(.tertiary)
                }
                Text("\(Int(max))°C")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                HStack(spacing: 16) {
                    Label("Max", systemImage: "arrow.up").font(.caption2).foregroundStyle(.secondary)
                    Text("Avg: \(Int(avg))°C").font(.caption).foregroundStyle(.secondary)
                }
                ProgressView(value: min(max / 110.0, 1.0)).tint(color)
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
