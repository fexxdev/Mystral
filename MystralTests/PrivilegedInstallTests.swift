import XCTest
@testable import Mystral

final class PrivilegedInstallTests: XCTestCase {
    func testAppleScriptSourceEscapesQuotesAndBackslashesInShellLine() {
        let path = #"/Applications/My "odd" \ App's.app"#
        let source = PrivilegedShell.appleScriptSource(for: ["/bin/rm -rf \(PrivilegedShell.quote(path))", "/usr/bin/true"])
        XCTAssertEqual(
            source,
            #"do shell script "/bin/rm -rf '/Applications/My \"odd\" \\ App'\\''s.app' && /usr/bin/true" with administrator privileges"#
        )
    }

    func testShellQuoteNeutralisesCommandSubstitution() {
        XCTAssertEqual(PrivilegedShell.quote("a'$(id)'b"), #"'a'\''$(id)'\''b'"#)
    }

    func testElevatedUpdateInstallsRootOwnedBundle() {
        let commands = UpdateChecker.elevatedReplaceCommands(
            appPath: "/Applications/Mystral.app",
            sourcePath: "/private/tmp/mount/Mystral.app",
            backupPath: "/Applications/Mystral.app.old"
        )
        let copy = try! XCTUnwrap(commands.firstIndex { $0.hasPrefix("/bin/cp -R ") })
        let chown = try! XCTUnwrap(commands.firstIndex { $0 == "/usr/sbin/chown -R root:wheel '/Applications/Mystral.app'" })
        XCTAssertLessThan(copy, chown)
        XCTAssertTrue(commands.contains("/bin/chmod -R go-w '/Applications/Mystral.app'"))
    }

    func testHelperInstallLocksTheWholeAppBundle() {
        XCTAssertEqual(
            HelperDaemon.bundleLockCommands(executablePath: "/Applications/Mystral.app/Contents/MacOS/Mystral"),
            [
                "/usr/sbin/chown -R root:wheel '/Applications/Mystral.app'",
                "/bin/chmod -R go-w '/Applications/Mystral.app'"
            ]
        )
    }
}
