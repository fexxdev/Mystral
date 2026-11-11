import Foundation

/// Runs a shell command line as root through the standard administrator prompt.
/// Every value interpolated into a command must go through `quote`.
enum PrivilegedShell {
    enum Failure: Error, LocalizedError {
        case cancelled
        case failed(code: Int, message: String)

        var errorDescription: String? {
            switch self {
            case .cancelled: "Administrator authorization was cancelled"
            case .failed(_, let message): message
            }
        }
    }

    /// Single-quotes a value for /bin/sh.
    static func quote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// The AppleScript source that runs `commands` joined with `&&`. The shell line is
    /// escaped again for the AppleScript string literal that carries it.
    static func appleScriptSource(for commands: [String]) -> String {
        let line = commands.joined(separator: " && ")
        let literal = line
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "do shell script \"\(literal)\" with administrator privileges"
    }

    static func run(_ commands: [String]) throws {
        guard let script = NSAppleScript(source: appleScriptSource(for: commands)) else {
            throw Failure.failed(code: -1, message: "Failed to create AppleScript")
        }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        guard let error else { return }
        let code = error[NSAppleScript.errorNumber] as? Int ?? -1
        if code == -128 { throw Failure.cancelled }
        throw Failure.failed(code: code, message: error[NSAppleScript.errorMessage] as? String ?? "Unknown error")
    }
}
