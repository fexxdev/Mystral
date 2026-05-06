import Foundation
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SMCHelper")

enum SMCHelperMode {
    static let dataPath = "/tmp/mystral-smc-data.json"
    static let cmdDir = "/tmp/mystral-cmds"
    static let pidPath = "/tmp/mystral-helper.pid"

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    struct SMCData: Codable {
        struct SensorData: Codable {
            let key: String
            let name: String
            let temperature: Double
        }
        struct FanData: Codable {
            let id: Int
            let name: String
            let currentRPM: Int
            let targetRPM: Int
            let minRPM: Int
            let maxRPM: Int
            let mode: Int
        }
        var version: String?
        let sensors: [SensorData]
        let fans: [FanData]
    }

    struct Command: Codable {
        let action: String
        let index: Int
        let value: Double?
    }

    static func run() -> Never {
        // Root's cwd is / which is read-only on macOS — LLVM profiling (Debug builds)
        // crashes writing default.profraw there
        FileManager.default.changeCurrentDirectoryPath("/tmp")

        logger.info("SMCHelper starting — pid=\(getpid()), version=\(appVersion)")
        try? "\(getpid())".write(toFile: pidPath, atomically: true, encoding: .utf8)
        try? FileManager.default.createDirectory(atPath: cmdDir, withIntermediateDirectories: true)
        chmod(cmdDir, 0o777)

        let smc: SMCService
        do {
            smc = try SMCService()
            logger.info("SMCHelper — SMC opened successfully")
        } catch {
            logger.error("SMCHelper — SMC open failed: \(error.localizedDescription)")
            fputs("SMC open failed: \(error)\n", stderr)
            exit(1)
        }

        let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN)
        sigSource.setEventHandler {
            logger.info("SMCHelper — SIGTERM received, restoring auto mode and cleaning up")
            let count = (try? smc.getAllFans().count) ?? 2
            try? smc.setForcedMode(fanCount: count, forced: false)
            cleanup()
            exit(0)
        }
        sigSource.resume()

        dumpDiagnostics(smc: smc)

        let timer = DispatchSource.makeTimerSource(queue: .global())
        timer.schedule(deadline: .now(), repeating: 2.0)
        timer.setEventHandler {
            processCommands(smc: smc)
            do {
                let sensors = try smc.getAllSensors()
                let fans = try smc.getAllFans()
                let data = SMCData(
                    version: appVersion,
                    sensors: sensors.map { .init(key: $0.id, name: $0.name, temperature: $0.temperature) },
                    fans: fans.map { .init(id: $0.id, name: $0.name, currentRPM: $0.currentRPM,
                                           targetRPM: $0.targetRPM, minRPM: $0.minRPM,
                                           maxRPM: $0.maxRPM, mode: $0.mode.rawValue) }
                )
                let json = try JSONEncoder().encode(data)
                try json.write(to: URL(fileURLWithPath: dataPath), options: .atomic)
            } catch {
                fputs("SMC read error: \(error)\n", stderr)
            }
        }
        timer.resume()

        dispatchMain()
    }

    private static func dumpDiagnostics(smc: SMCService) {
        let diagPath = "/tmp/mystral-diagnostics.log"
        var log = "=== Mystral SMC Diagnostics ===\n"
        log += "Running as uid: \(getuid())\n"
        log += "Date: \(Date())\n\n"

        let sampleKeys = ["Tp01", "Tp09", "Tg0a", "TaLP", "Ts0S", "TB1T", "TCMb", "TAOL", "TaTP"]
        let smcKit = SMCKit()
        do {
            try smcKit.open()
            for key in sampleKeys {
                do {
                    let (bytes, dataType, dataSize) = try smcKit.readRawBytes(key: key)
                    let typeStr = SMCKit.fourCharString(dataType)
                    let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    let value = try smcKit.readFloat(key: key)
                    log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)] | decoded: \(value)\n"
                } catch {
                    log += "Key: \(key) | ERROR: \(error)\n"
                }
            }

            log += "\n--- First 10 temperature keys with non-zero bytes ---\n"
            let tempKeys = try smcKit.temperatureKeys()
            var found = 0
            for key in tempKeys where found < 10 {
                if let (bytes, dataType, dataSize) = try? smcKit.readRawBytes(key: key) {
                    let typeStr = SMCKit.fourCharString(dataType)
                    let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)]\n"
                    found += 1
                }
            }

            log += "\n--- Fan control keys ---\n"
            for key in ["FNum", "Ftst", "FS! ", "FS!!", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "F1Ac", "F1Mn", "F1Mx", "F1Tg", "F1Md"] {
                if let (bytes, dataType, dataSize) = try? smcKit.readRawBytes(key: key) {
                    let typeStr = SMCKit.fourCharString(dataType)
                    let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    let value = try? smcKit.readFloat(key: key)
                    log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)] | decoded: \(value ?? -1)\n"
                }
            }
            smcKit.close()
        } catch {
            log += "SMC open failed: \(error)\n"
        }

        try? log.write(toFile: diagPath, atomically: true, encoding: .utf8)
        fputs("Diagnostics written to \(diagPath)\n", stderr)
    }

    private static func processCommands(smc: SMCService) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: cmdDir) else { return }
        for file in files where file.hasSuffix(".json") {
            let path = "\(cmdDir)/\(file)"
            defer { try? fm.removeItem(atPath: path) }
            guard let data = fm.contents(atPath: path),
                  let cmd = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            do {
                switch cmd.action {
                case "setFanSpeed":
                    fputs("CMD: setFanSpeed fan=\(cmd.index) pct=\(cmd.value ?? 0)\n", stderr)
                    try smc.setFanSpeed(index: cmd.index, percentage: cmd.value ?? 0)
                    fputs("  OK\n", stderr)
                case "setFanMode":
                    fputs("CMD: setFanMode fan=\(cmd.index) mode=\(Int(cmd.value ?? 0))\n", stderr)
                    try smc.setFanMode(index: cmd.index, mode: FanMode(rawValue: Int(cmd.value ?? 0)) ?? .auto)
                    fputs("  OK\n", stderr)
                case "setForcedMode":
                    let forced = (cmd.value ?? 0) > 0
                    let count = cmd.index
                    fputs("CMD: setForcedMode forced=\(forced) fanCount=\(count)\n", stderr)
                    try smc.setForcedMode(fanCount: count, forced: forced)
                    fputs("  OK\n", stderr)
                default: break
                }
            } catch {
                fputs("  FAIL: \(error)\n", stderr)
            }
        }
    }

    private static func cleanup() {
        try? FileManager.default.removeItem(atPath: pidPath)
        try? FileManager.default.removeItem(atPath: dataPath)
        try? FileManager.default.removeItem(atPath: cmdDir)
    }
}
