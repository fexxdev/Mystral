import AppKit
import os

private let logger = Logger(subsystem: "com.fexxdev.Mystral", category: "AppRelauncher")

/// Quits Mystral and opens it again once this process has exited.
enum AppRelauncher {
    /// Launch argument that opens the main window on the Settings section.
    static let openSettingsArgument = "--open-settings"

    /// Waits for this process to exit, then reopens the app bundle with `arguments`.
    /// The pid and paths are positional shell parameters, never parsed as shell code.
    /// Returns false, without quitting, when the relaunch script cannot start.
    @MainActor
    @discardableResult
    static func relaunch(arguments: [String] = []) -> Bool {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = #"while kill -0 "$1" 2>/dev/null; do sleep 0.2; done; shift; exec /usr/bin/open "$@""#
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "sh", String(pid), Bundle.main.bundlePath]
            + (arguments.isEmpty ? [] : ["--args"] + arguments)
        do {
            try process.run()
        } catch {
            logger.error("Relaunch script failed to start: \(error.localizedDescription, privacy: .public)")
            return false
        }
        logger.info("Relaunch script spawned, terminating")
        NSApp.terminate(nil)
        return true
    }
}
