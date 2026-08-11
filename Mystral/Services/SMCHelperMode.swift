import Foundation
import IOKit
import IOKit.pwr_mgt
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "SMCHelper")

enum SMCHelperMode {
    static let helperVersionEnvironmentKey = "MYSTRAL_HELPER_VERSION"
    static let helperRevisionEnvironmentKey = "MYSTRAL_HELPER_REVISION"
    static var dataPath: String { SMCIPC.dataPath }
    static var cmdDir: String { SMCIPC.commandDirectoryPath }
    static var pidPath: String { SMCIPC.pidPath }

    /// State the C system-power callback needs (it can't capture context). Set once in
    /// run(); read only from the callback, which runs on the helper's serial queue.
    nonisolated(unsafe) fileprivate static var rootPowerPort: io_connect_t = 0
    nonisolated(unsafe) fileprivate static var powerSMC: SMCServiceProtocol?

    static var appVersion: String {
        ProcessInfo.processInfo.environment[helperVersionEnvironmentKey]
            ?? Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0"
    }

    static var helperRevision: String {
        ProcessInfo.processInfo.environment[helperRevisionEnvironmentKey]
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? appVersion
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

        var isValid: Bool {
            switch action {
            case "heartbeat":
                return index == 0 && value == nil
            case "setFanSpeed":
                guard let value else { return false }
                return index >= 0 && index < 8 && value.isFinite && (0...100).contains(value)
            case "setFanMode":
                guard let value else { return false }
                return index >= 0 && index < 8 && value.isFinite && (value == 0 || value == 1)
            case "setForcedMode":
                guard let value else { return false }
                return index >= 1 && index <= 8 && value.isFinite && (value == 0 || value == 1)
            case "restart":
                return index == 0 && value == nil
            default:
                return false
            }
        }
    }

    static func shouldRestoreForHeartbeat(lastHeartbeat: Date?, now: Date, timeout: TimeInterval) -> Bool {
        guard let lastHeartbeat else { return false }
        return now.timeIntervalSince(lastHeartbeat) >= timeout
    }

    static func run() -> Never {
        fputs("SMCHelper: starting pid=\(getpid()) version=\(appVersion)\n", stderr)

        guard SMCIPC.validateForHelper() else {
            fputs("SMCHelper: refusing unsafe or missing IPC directory\n", stderr)
            exit(1)
        }

        logger.info("SMCHelper starting — pid=\(getpid()), version=\(appVersion)")
        fputs("SMCHelper: writing PID file\n", stderr)
        try? "\(getpid())".write(toFile: pidPath, atomically: true, encoding: .utf8)

        // Prevent macOS from throttling/coalescing our timer during display sleep
        let activityToken = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "SMC helper must update fan data without interruption"
        )
        logger.info("SMCHelper — activity assertion acquired")

        let smc: SMCService
        do {
            smc = try SMCService()
            logger.info("SMCHelper — SMC opened successfully")
        } catch {
            logger.error("SMCHelper — SMC open failed: \(error.localizedDescription)")
            fputs("SMC open failed: \(error)\n", stderr)
            exit(1)
        }

        // A helper restart must never inherit the previous forced setpoint.
        _ = restoreAutoMode(smc: smc)

        let queue = DispatchQueue(label: "com.fexxdev.Mystral.helper", qos: .userInitiated)

        signal(SIGHUP, SIG_IGN)

        let sigSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: queue)
        signal(SIGTERM, SIG_IGN)
        sigSource.setEventHandler {
            logger.info("SMCHelper — SIGTERM received, restoring auto mode and cleaning up")
            restoreAutoMode(smc: smc)
            cleanup()
            exit(0)
        }
        sigSource.resume()

        dumpDiagnostics(smc: smc)

        var consecutiveErrors = 0
        var lastHeartbeat: Date?
        var restoredAfterReadFailure = false
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: 2.0, leeway: .milliseconds(100))
        timer.setEventHandler {
            processCommands(smc: smc, lastHeartbeat: &lastHeartbeat)
            if shouldRestoreForHeartbeat(lastHeartbeat: lastHeartbeat, now: Date(), timeout: 8) {
                logger.warning("SMCHelper — app heartbeat timed out; restoring automatic fan control")
                purgeCommandFiles()
                _ = restoreAutoMode(smc: smc)
                lastHeartbeat = nil
            }
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
                if consecutiveErrors > 0 {
                    logger.info("SMCHelper — recovered after \(consecutiveErrors) errors")
                    consecutiveErrors = 0
                }
                restoredAfterReadFailure = false
            } catch {
                consecutiveErrors += 1
                logger.error("SMCHelper — SMC read error (#\(consecutiveErrors)): \(error.localizedDescription)")
                fputs("SMC read error (#\(consecutiveErrors)): \(error)\n", stderr)
                if consecutiveErrors >= 3 && !restoredAfterReadFailure {
                    purgeCommandFiles()
                    _ = restoreAutoMode(smc: smc)
                    lastHeartbeat = nil
                    restoredAfterReadFailure = true
                }
            }
        }
        timer.resume()

        registerForSleepNotifications(smc: smc, queue: queue)

        withExtendedLifetime(activityToken) {
            dispatchMain()
        }
    }

    /// Registers the helper for system-power notifications so it restores auto fan mode
    /// just before the Mac sleeps (issue #2). Delivery is bound to the helper's serial
    /// `queue`, so the callback never races the polling timer's SMC access.
    private static func registerForSleepNotifications(smc: SMCServiceProtocol, queue: DispatchQueue) {
        powerSMC = smc
        var notifyPort: IONotificationPortRef?
        var notifier: io_object_t = 0
        let port = IORegisterForSystemPower(nil, &notifyPort, mystralSleepWakeCallback, &notifier)
        guard port != 0, let notifyPort else {
            logger.error("SMCHelper — IORegisterForSystemPower failed; sleep auto-restore disabled")
            return
        }
        rootPowerPort = port
        IONotificationPortSetDispatchQueue(notifyPort, queue)
        logger.info("SMCHelper — registered for system sleep/wake power notifications")
    }

    /// Hand fan control back to macOS auto mode (releases the forced setpoint the SMC
    /// otherwise holds). Used both on SIGTERM and when the system is about to sleep so
    /// the firmware idles the fans instead of whining at the last forced RPM (issue #2).
    @discardableResult
    static func restoreAutoMode(smc: SMCServiceProtocol) -> Bool {
        do {
            let count = try smc.getAllFans().count
            try smc.setForcedMode(fanCount: max(1, count), forced: false)
            return true
        } catch {
            logger.error("SMCHelper — failed to restore automatic fan control: \(error.localizedDescription)")
            return false
        }
    }

    /// Routes a system-power message to its fan action: on "will sleep" it hands fans
    /// back to macOS auto so the firmware idles them (issue #2); other messages leave
    /// fans alone (wake re-apply is the app's `handleWake`). Returns whether the message
    /// is a sleep query/notification the caller must acknowledge with `IOAllowPowerChange`
    /// — failing to ack stalls sleep ~30s. IOKit-free so it's unit-testable.
    @discardableResult
    static func handlePowerMessage(_ messageType: UInt32, smc: SMCServiceProtocol?) -> Bool {
        switch messageType {
        case kMystralMsgSystemWillSleep:
            logger.info("SMCHelper — system will sleep, restoring auto fan mode")
            if let smc { restoreAutoMode(smc: smc) }
            return true
        case kMystralMsgCanSystemSleep:
            return true // never veto idle sleep; ack only
        default:
            return false // e.g. kIOMessageSystemHasPoweredOn — app's handleWake re-applies
        }
    }

    private static func dumpDiagnostics(smc: SMCService) {
        let diagPath = SMCIPC.diagnosticPath
        var log = "=== Mystral SMC Diagnostics ===\n"
        log += "Running as uid: \(getuid())\n"
        log += "Date: \(Date())\n\n"

        let sampleKeys = ["Tp01", "Tp09", "Tg0a", "TaLP", "Ts0S", "TB1T", "TCMb", "TAOL", "TaTP"]
        for key in sampleKeys {
            do {
                let (bytes, dataType, dataSize) = try smc.readRawBytes(key: key)
                let typeStr = SMCKit.fourCharString(dataType)
                let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                let value = try smc.readTemperature(key: key)
                log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)] | decoded: \(value)\n"
            } catch {
                log += "Key: \(key) | ERROR: \(error)\n"
            }
        }

        log += "\n--- First 10 temperature keys with non-zero bytes ---\n"
        if let tempKeys = try? smc.temperatureKeys() {
            var found = 0
            for key in tempKeys where found < 10 {
                if let (bytes, dataType, dataSize) = try? smc.readRawBytes(key: key) {
                    let typeStr = SMCKit.fourCharString(dataType)
                    let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                    log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)]\n"
                    found += 1
                }
            }
        }

        log += "\n--- Fan control keys ---\n"
        for key in ["FNum", "Ftst", "FS! ", "FS!!", "F0Ac", "F0Mn", "F0Mx", "F0Tg", "F0Md", "F1Ac", "F1Mn", "F1Mx", "F1Tg", "F1Md"] {
            if let (bytes, dataType, dataSize) = try? smc.readRawBytes(key: key) {
                let typeStr = SMCKit.fourCharString(dataType)
                let bytesHex = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
                let value = try? smc.readTemperature(key: key)
                log += "Key: \(key) | type: \(typeStr) | size: \(dataSize) | bytes: [\(bytesHex)] | decoded: \(value ?? -1)\n"
            }
        }

        try? log.write(toFile: diagPath, atomically: true, encoding: .utf8)
        fputs("Diagnostics written to \(diagPath)\n", stderr)
    }

    private static func processCommands(smc: SMCService, lastHeartbeat: inout Date?) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: cmdDir) else { return }
        for file in files where file.hasSuffix(".json") {
            let path = "\(cmdDir)/\(file)"
            defer { try? fm.removeItem(atPath: path) }
            guard isTrustedCommandFile(path: path) else { continue }
            guard let data = fm.contents(atPath: path),
                  let cmd = try? JSONDecoder().decode(Command.self, from: data) else { continue }
            guard cmd.isValid else {
                fputs("CMD: rejected invalid command\n", stderr)
                continue
            }
            do {
                switch cmd.action {
                case "heartbeat":
                    lastHeartbeat = Date()
                case "setFanSpeed":
                    let pct = cmd.value ?? 0
                    guard cmd.index >= 0 && cmd.index < 8 && pct >= 0 && pct <= 100 else {
                        fputs("CMD: setFanSpeed REJECTED — out of range fan=\(cmd.index) pct=\(pct)\n", stderr)
                        continue
                    }
                    fputs("CMD: setFanSpeed fan=\(cmd.index) pct=\(pct)\n", stderr)
                    try smc.setFanSpeed(index: cmd.index, percentage: pct)
                    fputs("  OK\n", stderr)
                case "setFanMode":
                    let mode = Int(cmd.value ?? 0)
                    guard cmd.index >= 0 && cmd.index < 8 && (mode == 0 || mode == 1) else {
                        fputs("CMD: setFanMode REJECTED — out of range fan=\(cmd.index) mode=\(mode)\n", stderr)
                        continue
                    }
                    fputs("CMD: setFanMode fan=\(cmd.index) mode=\(mode)\n", stderr)
                    try smc.setFanMode(index: cmd.index, mode: FanMode(rawValue: mode) ?? .auto)
                    fputs("  OK\n", stderr)
                case "setForcedMode":
                    let forced = (cmd.value ?? 0) > 0
                    let count = cmd.index
                    guard count >= 1 && count <= 8 else {
                        fputs("CMD: setForcedMode REJECTED — out of range fanCount=\(count)\n", stderr)
                        continue
                    }
                    fputs("CMD: setForcedMode forced=\(forced) fanCount=\(count)\n", stderr)
                    try smc.setForcedMode(fanCount: count, forced: forced)
                    fputs("  OK\n", stderr)
                case "restart":
                    // App asked us to recycle (e.g. to load a newer binary after an
                    // app update, or via the manual restart button). Just exit — the
                    // launchd daemon's KeepAlive relaunches us from the on-disk binary.
                    fputs("CMD: restart — exiting for launchd to relaunch\n", stderr)
                    logger.info("SMCHelper — restart command received, exiting for launchd relaunch")
                    cleanup()
                    exit(0)
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
        purgeCommandFiles()
    }

    private static func purgeCommandFiles() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: cmdDir) else { return }
        for file in files where file.hasSuffix(".json") {
            try? fm.removeItem(atPath: URL(fileURLWithPath: cmdDir).appendingPathComponent(file).path)
        }
    }

    private static func isTrustedCommandFile(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard url.path == url.resolvingSymlinksInPath().path,
              let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              (attributes[.type] as? FileAttributeType) == .typeRegular else {
            return false
        }
        let expectedUID = UInt32(ProcessInfo.processInfo.environment[SMCIPC.uidEnvironmentKey] ?? "")
        let ownerUID = (attributes[.ownerAccountID] as? NSNumber)?.uint32Value
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0o777
        return ownerUID == expectedUID && (permissions & 0o022) == 0
    }
}

// IOKit's kIOMessage* power constants are nested function-like C macros
// (`iokit_common_msg(x)` = `(UInt32)(sys_iokit | x)`, with `sys_iokit = 0x38 << 26`)
// that Swift's importer can't translate, so reconstruct the two we handle.
// See <IOKit/IOMessage.h>.
private let kMystralMsgCanSystemSleep: UInt32 = (0x38 << 26) | 0x270  // 0xE0000270
private let kMystralMsgSystemWillSleep: UInt32 = (0x38 << 26) | 0x280 // 0xE0000280

/// C-compatible (`@convention(c)`) system-power callback — captures nothing, so it reads
/// the SMC handle and root port from `SMCHelperMode`'s static storage and delegates the
/// (unit-tested) routing to `handlePowerMessage`. Its only job here is the IOKit ack.
private func mystralSleepWakeCallback(_ refcon: UnsafeMutableRawPointer?,
                                      _ service: io_service_t,
                                      _ messageType: UInt32,
                                      _ messageArgument: UnsafeMutableRawPointer?) {
    if SMCHelperMode.handlePowerMessage(messageType, smc: SMCHelperMode.powerSMC) {
        IOAllowPowerChange(SMCHelperMode.rootPowerPort, Int(bitPattern: messageArgument))
    }
}
