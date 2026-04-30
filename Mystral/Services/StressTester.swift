import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "StressTester")

@Observable
@MainActor
final class StressTester {
    enum State: Equatable {
        case idle
        case running(elapsed: Int, total: Int)
        case finished(StressResult)
    }

    struct StressResult: Equatable {
        let baselineMaxTemp: Double
        let peakTemp: Double
        let baselineMaxRPM: Int
        let peakRPM: Int
        let durationSeconds: Int
        let fanResponded: Bool
    }

    private(set) var state: State = .idle
    private var task: Task<Void, Never>?

    func runStressTest(durationSeconds: Int = 30, fanController: FanController) {
        guard task == nil else { return }
        let baselineTemp = currentMaxCpuTemp(fanController: fanController)
        let baselineRPM = fanController.fans.map { $0.currentRPM }.max() ?? 0

        state = .running(elapsed: 0, total: durationSeconds)
        let workerCount = ProcessInfo.processInfo.activeProcessorCount

        task = Task { [weak self, weak fanController] in
            let workers = (0..<workerCount).map { _ in Self.spawnBurner() }
            var peakTemp = baselineTemp
            var peakRPM = baselineRPM
            for second in 1...durationSeconds {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { break }
                guard let fc = fanController else { break }
                let t = await MainActor.run { Self.maxCpuTemp(sensors: fc.sensors) }
                let r = await MainActor.run { fc.fans.map { $0.currentRPM }.max() ?? 0 }
                if t > peakTemp { peakTemp = t }
                if r > peakRPM { peakRPM = r }
                await MainActor.run { self?.state = .running(elapsed: second, total: durationSeconds) }
            }
            workers.forEach { $0.cancel() }
            let result = StressResult(
                baselineMaxTemp: baselineTemp,
                peakTemp: peakTemp,
                baselineMaxRPM: baselineRPM,
                peakRPM: peakRPM,
                durationSeconds: durationSeconds,
                fanResponded: peakRPM > baselineRPM + 200 || peakRPM > baselineRPM * 105 / 100
            )
            await MainActor.run {
                self?.state = .finished(result)
                self?.task = nil
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
        state = .idle
    }

    private func currentMaxCpuTemp(fanController: FanController) -> Double {
        Self.maxCpuTemp(sensors: fanController.sensors)
    }

    private static func maxCpuTemp(sensors: [Sensor]) -> Double {
        sensors.filter { $0.id.hasPrefix("Tp") }.map(\.temperature).max() ?? 0
    }

    private static func spawnBurner() -> Task<Void, Never> {
        Task.detached(priority: .userInitiated) {
            var x = 0.0001
            while !Task.isCancelled {
                for _ in 0..<200_000 { x = (x + 1.0000001).squareRoot() * 0.999999 }
                if x.isNaN { x = 0.0001 }
            }
        }
    }
}
