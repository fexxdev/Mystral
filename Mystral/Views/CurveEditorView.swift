import SwiftUI

struct CurveEditorView: View {
    @Binding var curvePoints: [CurvePoint]
    let sensorKeys: [String]
    @Binding var sensorKey: String

    private let tempRange: ClosedRange<Double> = 0...110
    private let fanRange: ClosedRange<Double> = 0...100

    private var groupedSensorKeys: [(SensorCategory, [String])] {
        var grouped: [SensorCategory: [String]] = [:]
        for key in sensorKeys {
            let cat = SensorRegistry.categoryForKey(key)
            grouped[cat, default: []].append(key)
        }
        return SensorCategory.allCases.compactMap { cat in
            guard let keys = grouped[cat], !keys.isEmpty else { return nil }
            return (cat, keys)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Driving Sensor").font(.headline)
                Picker("", selection: $sensorKey) {
                    Text("CPU Average (all cores)").tag("")
                    ForEach(groupedSensorKeys, id: \.0) { category, keys in
                        Section(category.rawValue) {
                            ForEach(keys, id: \.self) { key in
                                Text("\(SensorRegistry.nameForKey(key)) (\(key))").tag(key)
                            }
                        }
                    }
                }.frame(width: 280)
            }
            HStack(alignment: .top, spacing: 20) {
                curveChart.frame(minWidth: 300, minHeight: 300)
                curveTable.frame(minWidth: 200)
            }
        }
    }

    private var curveChart: some View {
        VStack(spacing: 4) {
            HStack(spacing: 4) {
                VStack {
                    Text("100%").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("50%").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("0%").font(.caption2).foregroundStyle(.secondary)
                }
                .frame(width: 32)

                GeometryReader { geometry in
                    let sorted = curvePoints.sortedByTemperature()
                    let w = geometry.size.width
                    let h = geometry.size.height
                    ZStack {
                        gridLines(width: w, height: h)
                        Path { path in
                            guard !sorted.isEmpty else { return }
                            for (i, pt) in sorted.enumerated() {
                                let p = CGPoint(x: xPos(pt.temperature, w), y: yPos(pt.fanPercentage, h))
                                if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
                            }
                        }.stroke(Color.accentColor, lineWidth: 2)
                        ForEach(sorted) { point in
                            Circle().fill(Color.accentColor).frame(width: 12, height: 12)
                                .position(x: xPos(point.temperature, w), y: yPos(point.fanPercentage, h))
                                .gesture(DragGesture().onChanged { value in
                                    updatePoint(id: point.id,
                                                temperature: tempFromX(value.location.x, w),
                                                fanPercentage: pctFromY(value.location.y, h))
                                })
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            HStack {
                Spacer().frame(width: 32)
                HStack {
                    Text("0°").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("Temperature (°C)").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("110°").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func gridLines(width: Double, height: Double) -> some View {
        Canvas { context, _ in
            let color = Color.gray.opacity(0.2)
            for temp in stride(from: 0.0, through: 110.0, by: 10.0) {
                let x = xPos(temp, width)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: height)) },
                    with: .color(color)
                )
            }
            for pct in stride(from: 0.0, through: 100.0, by: 10.0) {
                let y = yPos(pct, height)
                context.stroke(
                    Path { p in p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: width, y: y)) },
                    with: .color(color)
                )
            }
        }
    }

    private var curveTable: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Temp (°C)").font(.caption.bold()).frame(width: 80)
                Text("Fan (%)").font(.caption.bold()).frame(width: 80)
                Spacer()
            }
            ForEach(curvePoints.sortedByTemperature()) { point in
                HStack {
                    TextField("°C", value: Binding(
                        get: { point.temperature },
                        set: { updatePoint(id: point.id, temperature: $0, fanPercentage: nil) }
                    ), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                    TextField("%", value: Binding(
                        get: { point.fanPercentage },
                        set: { updatePoint(id: point.id, temperature: nil, fanPercentage: $0) }
                    ), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { removePoint(id: point.id) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain).disabled(curvePoints.count <= 2)
                }
            }
            Button { addPoint() } label: { Label("Add Point", systemImage: "plus.circle") }
                .disabled(curvePoints.count >= 10)
        }
    }

    private func xPos(_ temp: Double, _ w: Double) -> Double {
        (temp - tempRange.lowerBound) / (tempRange.upperBound - tempRange.lowerBound) * w
    }

    private func yPos(_ pct: Double, _ h: Double) -> Double {
        h - (pct - fanRange.lowerBound) / (fanRange.upperBound - fanRange.lowerBound) * h
    }

    private func tempFromX(_ x: Double, _ w: Double) -> Double {
        let t = (x / w) * (tempRange.upperBound - tempRange.lowerBound) + tempRange.lowerBound
        return max(tempRange.lowerBound, min(tempRange.upperBound, (t * 2).rounded() / 2))
    }

    private func pctFromY(_ y: Double, _ h: Double) -> Double {
        let p = (1 - y / h) * (fanRange.upperBound - fanRange.lowerBound) + fanRange.lowerBound
        return max(fanRange.lowerBound, min(fanRange.upperBound, p.rounded()))
    }

    private func updatePoint(id: UUID, temperature: Double?, fanPercentage: Double?) {
        guard let i = curvePoints.firstIndex(where: { $0.id == id }) else { return }
        if let t = temperature { curvePoints[i].temperature = max(tempRange.lowerBound, min(tempRange.upperBound, t)) }
        if let p = fanPercentage { curvePoints[i].fanPercentage = max(fanRange.lowerBound, min(fanRange.upperBound, p)) }
    }

    private func removePoint(id: UUID) {
        guard curvePoints.count > 2 else { return }
        curvePoints.removeAll { $0.id == id }
    }

    private func addPoint() {
        guard curvePoints.count < 10 else { return }
        let sorted = curvePoints.sortedByTemperature()
        curvePoints.append(CurvePoint(
            temperature: min((sorted.last?.temperature ?? 50) + 10, 110),
            fanPercentage: min((sorted.last?.fanPercentage ?? 50) + 10, 100)
        ))
    }
}
