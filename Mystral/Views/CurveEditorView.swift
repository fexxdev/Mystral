import SwiftUI

private enum FanScope: Hashable {
    case shared
    case fan(Int)
}

struct CurveEditorView: View {
    @Binding var profile: Profile
    let sensorKeys: [String]
    let fans: [Fan]

    @State private var scope: FanScope = .shared

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

    private var activeCurve: [CurvePoint] {
        switch scope {
        case .shared: return profile.curvePoints
        case .fan(let i): return profile.fanCurves?[i] ?? profile.curvePoints
        }
    }

    private var hasOverride: Bool {
        if case .fan(let i) = scope { return profile.fanCurves?[i] != nil }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                Text("Driving Sensor").font(.headline)
                Picker("", selection: Binding(
                    get: { profile.sensorKey },
                    set: { profile.sensorKey = $0 }
                )) {
                    Text("CPU Average (all cores)").tag("")
                    ForEach(groupedSensorKeys, id: \.0) { category, keys in
                        Section(category.rawValue) {
                            ForEach(keys, id: \.self) { key in
                                Text("\(SensorRegistry.nameForKey(key)) (\(key))").tag(key)
                            }
                        }
                    }
                }.frame(width: 280).labelsHidden()
                Spacer()
            }

            if fans.count > 1 {
                fanScopePicker
            }

            HStack(alignment: .top, spacing: 20) {
                curveChart.frame(minWidth: 360, minHeight: 320)
                curveTable.frame(minWidth: 220)
            }
        }
    }

    private var fanScopePicker: some View {
        HStack(spacing: 12) {
            Text("Curve").font(.headline)
            Picker("", selection: $scope) {
                Text("Shared (all fans)").tag(FanScope.shared)
                ForEach(fans) { fan in
                    let badge = profile.fanCurves?[fan.id] != nil ? " ●" : ""
                    Text("\(fan.name)\(badge)").tag(FanScope.fan(fan.id))
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if case .fan(let i) = scope {
                if hasOverride {
                    Button("Reset to shared") {
                        var fc = profile.fanCurves ?? [:]
                        fc.removeValue(forKey: i)
                        profile.fanCurves = fc.isEmpty ? nil : fc
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                } else {
                    Button("Customize") {
                        var fc = profile.fanCurves ?? [:]
                        fc[i] = profile.curvePoints
                        profile.fanCurves = fc
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var curveBinding: Binding<[CurvePoint]> {
        Binding(
            get: { activeCurve },
            set: { newPoints in
                switch scope {
                case .shared:
                    profile.curvePoints = newPoints
                case .fan(let i):
                    var fc = profile.fanCurves ?? [:]
                    fc[i] = newPoints
                    profile.fanCurves = fc
                }
            }
        )
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
                    let sorted = activeCurve.sortedByTemperature()
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
            ForEach(activeCurve.sortedByTemperature()) { point in
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
                    }.buttonStyle(.plain).disabled(activeCurve.count <= 2)
                }
            }
            Button { addPoint() } label: { Label("Add Point", systemImage: "plus.circle") }
                .disabled(activeCurve.count >= 10)
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
        var points = activeCurve
        guard let i = points.firstIndex(where: { $0.id == id }) else { return }
        if let t = temperature { points[i].temperature = max(tempRange.lowerBound, min(tempRange.upperBound, t)) }
        if let p = fanPercentage { points[i].fanPercentage = max(fanRange.lowerBound, min(fanRange.upperBound, p)) }
        curveBinding.wrappedValue = points
    }

    private func removePoint(id: UUID) {
        var points = activeCurve
        guard points.count > 2 else { return }
        points.removeAll { $0.id == id }
        curveBinding.wrappedValue = points
    }

    private func addPoint() {
        var points = activeCurve
        guard points.count < 10 else { return }
        let sorted = points.sortedByTemperature()
        var newTemp = min((sorted.last?.temperature ?? 50) + 10, 110)
        let existingTemps = Set(points.map { Int(($0.temperature * 2).rounded()) })
        while existingTemps.contains(Int((newTemp * 2).rounded())) && newTemp < 110 {
            newTemp += 1
        }
        points.append(CurvePoint(
            temperature: min(newTemp, 110),
            fanPercentage: min((sorted.last?.fanPercentage ?? 50) + 10, 100)
        ))
        curveBinding.wrappedValue = points
    }
}
