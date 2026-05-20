import SwiftUI
import Charts

struct SensorsView: View {
    let fanController: FanController
    @State private var searchText = ""
    @State private var selectedCategory: SensorCategory?
    @State private var sortOrder: [KeyPathComparator<Sensor>] = [
        KeyPathComparator(\Sensor.temperature, order: .reverse)
    ]

    private var filteredSensors: [Sensor] {
        var sensors = fanController.sensors
        if let cat = selectedCategory {
            sensors = sensors.filter { SensorRegistry.categoryForKey($0.id) == cat }
        }
        if !searchText.isEmpty {
            sensors = sensors.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText)
            }
        }
        return sensors.sorted(using: sortOrder)
    }

    private var availableCategories: [SensorCategory] {
        let cats = Set(fanController.sensors.map { SensorRegistry.categoryForKey($0.id) })
        return SensorCategory.allCases.filter { cats.contains($0) }
    }

    var body: some View {
        Group {
            if fanController.sensors.isEmpty {
                ContentUnavailableView("No Sensors Detected", systemImage: "exclamationmark.triangle",
                                       description: Text("Waiting for SMC helper to start. You may be prompted for your password."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    categoryBar
                    Table(filteredSensors, sortOrder: $sortOrder) {
                        TableColumn("Key", value: \.id) { sensor in
                            Text(sensor.id).font(.system(.body, design: .monospaced))
                        }.width(min: 60, ideal: 80)

                        TableColumn("Name", value: \.name) { sensor in
                            Text(sensor.name)
                        }.width(min: 150, ideal: 200)

                        TableColumn("Category") { sensor in
                            Text(SensorRegistry.categoryForKey(sensor.id).rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }.width(min: 80, ideal: 100)

                        TableColumn("Temperature", value: \.temperature) { sensor in
                            Text("\(String(format: "%.1f", sensor.temperature))°C")
                                .foregroundStyle(temperatureColor(sensor.temperature))
                                .font(.system(.body, design: .rounded))
                        }.width(min: 80, ideal: 100)

                        TableColumn("Trend") { sensor in
                            SparklineView(data: sensor.history).frame(width: 100, height: 24)
                        }.width(min: 100, ideal: 120)
                    }
                    .searchable(text: $searchText, prompt: "Filter sensors...")
                }
            }
        }
        .navigationTitle("Sensors (\(filteredSensors.count)/\(fanController.sensors.count))")
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                categoryChip(label: "All", category: nil)
                ForEach(availableCategories, id: \.self) { cat in
                    categoryChip(label: cat.rawValue, category: cat)
                }
            }.padding(.horizontal).padding(.vertical, 8)
        }
    }

    private func categoryChip(label: String, category: SensorCategory?) -> some View {
        let isSelected = selectedCategory == category
        return Button {
            selectedCategory = category
        } label: {
            Text(label)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1))
        }.buttonStyle(.plain)
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

struct SparklineView: View {
    let data: [Double]
    var body: some View {
        if data.count >= 2 {
            Chart {
                ForEach(Array(data.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Time", index), y: .value("Temp", value)).foregroundStyle(.blue.gradient)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: ((data.min() ?? 0) - 5)...((data.max() ?? 100) + 5))
        } else {
            Text("—").foregroundStyle(.secondary)
        }
    }
}
