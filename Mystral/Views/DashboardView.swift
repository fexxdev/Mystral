import SwiftUI
import Charts

struct DashboardView: View {
    let fanController: FanController
    let profileManager: ProfileManager
    // Open by default so every sensor is visible at a glance; the choice is remembered.
    @AppStorage("dashboardCpuSensorsExpanded") private var cpuCoresExpanded = true
    @AppStorage("dashboardGpuSensorsExpanded") private var gpuCoresExpanded = true

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
        SensorRegistry.cpuMaximumTemperature(from: fanController.sensors)
    }

    private var cpuAvg: Double {
        SensorRegistry.cpuAverageTemperature(from: fanController.sensors) ?? 0
    }

    private var gpuMax: Double {
        gpuCoreSensors.map(\.temperature).max() ?? 0
    }

    private var gpuAvg: Double {
        let cores = gpuCoreSensors
        guard !cores.isEmpty else { return 0 }
        return cores.map(\.temperature).reduce(0, +) / Double(cores.count)
    }

    private var power: PowerMonitor { fanController.powerMonitor }

    var body: some View {
        VStack(spacing: 0) {
            if !fanController.isHelperResponsive {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text("SMC helper is not responding — fan control is inactive.")
                    Spacer()
                    Button {
                        fanController.requestManualRestart()
                    } label: {
                        Label("Restart Helper", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .tint(.white)
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(12)
                .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 8))
                .padding([.horizontal, .top])
            }

            if fanController.sensors.isEmpty && fanController.fans.isEmpty {
                ContentUnavailableView("No SMC Data", systemImage: "exclamationmark.triangle",
                                       description: Text("Waiting for SMC helper to start. You may be prompted for your password."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        temperatureOverview
                        powerSection
                        historyChartSection
                        fansSection
                        profileSection
                    }.padding()
                }
            }
        }.navigationTitle("Dashboard")
    }

    private var temperatureOverview: some View {
        VStack(spacing: 16) {
            HStack(spacing: 20) {
                TemperatureCard(title: "CPU", max: cpuMax, avg: cpuAvg,
                                sensorLabel: "\(cpuCoreSensors.count) sensors")
                TemperatureCard(title: "GPU", max: gpuMax, avg: gpuAvg,
                                sensorLabel: "\(gpuCoreSensors.count) sensors")
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
                coreGrid(title: "CPU Sensors", sensors: cpuCoreSensors, isExpanded: $cpuCoresExpanded)
            }

            if !gpuCoreSensors.isEmpty {
                coreGrid(title: "GPU Sensors", sensors: gpuCoreSensors, isExpanded: $gpuCoresExpanded)
            }
        }
    }

    private func coreGrid(title: LocalizedStringKey, sensors: [Sensor], isExpanded: Binding<Bool>) -> some View {
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
                        // A held reading is a moment old: the key is switched off right now.
                        .opacity(sensor.isStale ? 0.3 : sensor.isHeld ? 0.5 : 1)
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

    /// One point of a history chart. Both the temperature and the power chart use it.
    struct ChartPoint: Identifiable {
        let id: String
        let series: String
        let secondsAgo: Double
        let value: Double
    }

    /// Points for one series sampled once per tick, newest last. A nil entry is a tick
    /// without a reading: it gets no point, but still counts for the timing, so every
    /// other point stays at the moment it was measured.
    nonisolated static func chartPoints(_ history: [Double?], series: String, interval: Double) -> [ChartPoint] {
        let n = history.count
        return history.enumerated().compactMap { i, value in
            value.map { ChartPoint(id: "\(series)-\(i)", series: series,
                                   secondsAgo: -Double(n - 1 - i) * interval, value: $0) }
        }
    }

    private var historySamples: [ChartPoint] {
        let interval = fanController.pollingInterval
        let cpuCores = cpuCoreSensors
        let gpuCores = gpuCoreSensors
        func points(_ series: [Double], _ name: String) -> [ChartPoint] {
            Self.chartPoints(series.map { Optional($0) }, series: name, interval: interval)
        }
        return points(SensorRegistry.alignedHistory(of: cpuCores) { $0.max() ?? 0 }, "CPU Max")
            + points(SensorRegistry.alignedHistory(of: cpuCores) { $0.reduce(0, +) / Double($0.count) }, "CPU Avg")
            + points(SensorRegistry.alignedHistory(of: gpuCores) { $0.max() ?? 0 }, "GPU Max")
    }

    private var historyChartSection: some View {
        let samples = historySamples
        return GroupBox("Last 5 Minutes") {
            if samples.isEmpty {
                Text("Collecting samples…").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(samples) { p in
                    LineMark(
                        x: .value("Time", p.secondsAgo),
                        y: .value("Temp", p.value)
                    )
                    .foregroundStyle(by: .value("Series", p.series))
                    .interpolationMethod(.catmullRom)
                }
                .chartForegroundStyleScale([
                    "CPU Max": Color.orange,
                    "CPU Avg": Color.yellow,
                    "GPU Max": Color.purple
                ])
                .chartYScale(domain: 0...110)
                .chartXAxis {
                    AxisMarks(values: [-300, -240, -180, -120, -60, 0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let s = value.as(Double.self) {
                                if s == 0 { Text("now") } else { Text("\(Int(-s / 60))m") }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 25, 50, 75, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))°") }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.vertical, 8)
            }
        }
    }

    @ViewBuilder
    private var powerSection: some View {
        if power.totalWatts != nil || power.cpuWatts != nil || power.gpuWatts != nil {
            VStack(spacing: 16) {
                PowerCard(total: power.totalWatts, cpu: power.cpuWatts, gpu: power.gpuWatts)
                powerHistoryChart
            }
        }
    }


    /// Chart series names double as legend labels, so the "Total" one is localized.
    /// The same value keys `chartForegroundStyleScale`.
    private static let totalSeriesName = String(localized: "Total")

    private var powerHistorySamples: [ChartPoint] {
        let interval = fanController.pollingInterval
        return Self.chartPoints(power.totalHistory, series: Self.totalSeriesName, interval: interval)
            + Self.chartPoints(power.cpuHistory, series: "CPU", interval: interval)
            + Self.chartPoints(power.gpuHistory, series: "GPU", interval: interval)
    }

    private var powerHistoryChart: some View {
        let samples = powerHistorySamples
        let maxW = samples.map(\.value).max() ?? 0
        let upper = Swift.max(10, (maxW * 1.15).rounded(.up))
        return GroupBox("Power — Last 5 Minutes") {
            if samples.count < 2 {
                Text("Collecting samples…").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(samples) { p in
                    LineMark(
                        x: .value("Time", p.secondsAgo),
                        y: .value("Watts", p.value)
                    )
                    .foregroundStyle(by: .value("Series", p.series))
                    .interpolationMethod(.catmullRom)
                }
                .chartForegroundStyleScale([
                    Self.totalSeriesName: Color.teal,
                    "CPU": Color.orange,
                    "GPU": Color.purple
                ])
                .chartYScale(domain: 0...upper)
                .chartXAxis {
                    AxisMarks(values: [-300, -240, -180, -120, -60, 0]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let s = value.as(Double.self) {
                                if s == 0 { Text("now") } else { Text("\(Int(-s / 60))m") }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Double.self) { Text("\(Int(v))W") }
                        }
                    }
                }
                .frame(height: 160)
                .padding(.vertical, 8)
            }
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
                        Text(profile.displayName).font(.title3)
                        if !profile.sensorKey.isEmpty {
                            Text("Driving: \(SensorRegistry.nameForKey(profile.sensorKey)) (\(profile.sensorKey))")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Driving: CPU hottest sensor").font(.caption).foregroundStyle(.secondary)
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
                    ForEach(profileManager.allProfiles) { p in Text(p.displayName).tag(Optional(p.id)) }
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
    let sensorLabel: LocalizedStringKey

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

struct PowerCard: View {
    let total: Double?
    let cpu: Double?
    let gpu: Double?

    private var showBreakdown: Bool {
        guard let total, total > 0 else { return false }
        return cpu != nil || gpu != nil
    }

    var body: some View {
        GroupBox {
            VStack(spacing: 8) {
                HStack {
                    Text("Power").font(.headline)
                    Spacer()
                    Text("total system").font(.caption2).foregroundStyle(.tertiary)
                }
                Text(verbatim: total.map { PowerMonitor.formatWatts($0) } ?? "-- W")
                    .font(.system(size: 48, weight: .medium, design: .rounded))
                if showBreakdown, let total {
                    let other = PowerCard.otherWatts(total: total, cpu: cpu, gpu: gpu)
                    PowerBar(cpu: cpu ?? 0, gpu: gpu ?? 0, other: other)
                        .frame(height: 10)
                    HStack(spacing: 16) {
                        if cpu != nil { legend(.orange, "CPU", cpu) }
                        if gpu != nil { legend(.purple, "GPU", gpu) }
                        legend(.gray.opacity(0.5), "Other", other)
                    }
                    .font(.caption)
                }
            }.padding()
        }.frame(maxWidth: .infinity)
    }

    private func legend(_ color: Color, _ label: LocalizedStringKey, _ value: Double?) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            HStack(spacing: 4) {
                Text(label)
                Text(verbatim: value.map { PowerMonitor.formatWatts($0) } ?? "--")
            }
            .foregroundStyle(.secondary)
        }
    }

    /// Power not attributable to CPU/GPU (RAM, display, SSD, etc.). Clamped at 0:
    /// total (SMC) and CPU/GPU (IOReport) come from different sources sampled a beat
    /// apart and can momentarily disagree.
    nonisolated static func otherWatts(total: Double, cpu: Double?, gpu: Double?) -> Double {
        Swift.max(0, total - (cpu ?? 0) - (gpu ?? 0))
    }
}

struct PowerBar: View {
    let cpu: Double
    let gpu: Double
    let other: Double

    var body: some View {
        GeometryReader { geo in
            let w = Swift.max(geo.size.width, 1)
            let denom = Swift.max(cpu + gpu + other, 0.0001)
            HStack(spacing: 0) {
                Rectangle().fill(Color.orange).frame(width: w * cpu / denom)
                Rectangle().fill(Color.purple).frame(width: w * gpu / denom)
                Rectangle().fill(Color.gray.opacity(0.5)).frame(width: w * other / denom)
            }
        }
        .clipShape(Capsule())
    }
}
