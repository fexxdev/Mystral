import SwiftUI
import Charts

struct SensorsView: View {
    let fanController: FanController
    @State private var searchText = ""

    private var filteredSensors: [Sensor] {
        if searchText.isEmpty { return fanController.sensors }
        return fanController.sensors.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        Table(filteredSensors) {
            TableColumn("Key") { sensor in
                Text(sensor.id).font(.system(.body, design: .monospaced))
            }.width(min: 60, ideal: 80)

            TableColumn("Name") { sensor in Text(sensor.name) }.width(min: 150, ideal: 200)

            TableColumn("Temperature") { sensor in
                Text("\(String(format: "%.1f", sensor.temperature))°C")
                    .foregroundStyle(temperatureColor(sensor.temperature))
                    .font(.system(.body, design: .rounded))
            }.width(min: 80, ideal: 100)

            TableColumn("Trend") { sensor in
                SparklineView(data: sensor.history).frame(width: 100, height: 24)
            }.width(min: 100, ideal: 120)
        }
        .searchable(text: $searchText, prompt: "Filter sensors...")
        .navigationTitle("Sensors (\(fanController.sensors.count))")
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
