import AppKit
import Foundation
import IOKit.ps
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "ProfileAutoSwitcher")

@Observable
@MainActor
final class ProfileAutoSwitcher {
    private let profileManager: ProfileManager
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var isStarted = false
    private static let enabledKey = "autoSwitchEnabled"

    var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            if enabled { evaluate() }
        }
    }

    init(profileManager: ProfileManager) {
        self.profileManager = profileManager
        if UserDefaults.standard.object(forKey: Self.enabledKey) == nil {
            self.enabled = true
        } else {
            self.enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        }
    }

    func start() {
        guard !isStarted else {
            logger.info("start() called but already started — no-op")
            return
        }
        isStarted = true
        logger.info("start() — enabled=\(self.enabled, privacy: .public)")

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleThermalChange),
            name: ProcessInfo.thermalStateDidChangeNotification, object: nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(handleAppChange),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )

        startPowerSourceMonitor()
        evaluate()
    }

    private func startPowerSourceMonitor() {
        let context = Unmanaged.passRetained(self).toOpaque()
        guard let source = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let switcher = Unmanaged<ProfileAutoSwitcher>.fromOpaque(ctx).takeUnretainedValue()
            Task { @MainActor in switcher.evaluate() }
        }, context)?.takeRetainedValue() else {
            Unmanaged<ProfileAutoSwitcher>.fromOpaque(context).release()
            return
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
    }

    func stop() {
        guard isStarted else { return }
        isStarted = false

        if let source = powerSourceRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            powerSourceRunLoopSource = nil
            Unmanaged.passUnretained(self).release()
        }

        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    @objc private func handleThermalChange() { Task { @MainActor in self.evaluate() } }
    @objc private func handleAppChange() { Task { @MainActor in self.evaluate() } }

    func evaluate() {
        guard enabled else {
            logger.debug("evaluate() — disabled, skipping")
            return
        }
        let state = currentState()
        logger.debug("evaluate() — power=\(state.powerSource.rawValue, privacy: .public), thermal=\(state.thermalLevel.rawValue, privacy: .public), frontApp=\(state.frontmostBundleId ?? "nil", privacy: .public)")
        let candidates = profileManager.allProfiles.compactMap { profile -> (Profile, Int)? in
            guard let triggers = profile.triggers, !triggers.isEmpty else { return nil }
            var bestPriority = -1
            for trigger in triggers {
                if matches(trigger: trigger, state: state) {
                    bestPriority = max(bestPriority, priority(of: trigger))
                }
            }
            return bestPriority >= 0 ? (profile, bestPriority) : nil
        }
        guard let winner = candidates.max(by: { $0.1 < $1.1 })?.0 else { return }
        if profileManager.activeProfileId != winner.id {
            logger.info("Auto-switching to profile \(winner.name, privacy: .public)")
            profileManager.activeProfileId = winner.id
        }
    }

    private struct EnvironmentState {
        let powerSource: ProfileTrigger.PowerSource
        let thermalLevel: ProfileTrigger.ThermalLevel
        let frontmostBundleId: String?
    }

    private func currentState() -> EnvironmentState {
        let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue()
        let onAC: Bool
        if let snapshot, let providing = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() as String? {
            onAC = (providing == kIOPMACPowerKey)
        } else {
            onAC = true
        }
        let thermal: ProfileTrigger.ThermalLevel
        switch ProcessInfo.processInfo.thermalState {
        case .nominal: thermal = .nominal
        case .fair: thermal = .fair
        case .serious: thermal = .serious
        case .critical: thermal = .critical
        @unknown default: thermal = .nominal
        }
        let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        return EnvironmentState(
            powerSource: onAC ? .ac : .battery,
            thermalLevel: thermal,
            frontmostBundleId: frontmost
        )
    }

    private func matches(trigger: ProfileTrigger, state: EnvironmentState) -> Bool {
        switch trigger {
        case .powerSource(let p): return p == state.powerSource
        case .thermalState(let t): return t == state.thermalLevel
        case .frontmostApp(let bid): return bid == state.frontmostBundleId
        }
    }

    private func priority(of trigger: ProfileTrigger) -> Int {
        switch trigger {
        case .frontmostApp: return 3
        case .thermalState: return 2
        case .powerSource: return 1
        }
    }
}
