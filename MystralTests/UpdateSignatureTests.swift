import XCTest
import CryptoKit
@testable import Mystral

final class UpdateSignatureTests: XCTestCase {
    // Produced by scripts/update-signing.swift with a throwaway key, so the script and
    // the app must agree on the signed message format.
    private let vectorPublicKey = "LhTuc4C7ZNS8GMu3Nty2aEHJkKOMgmtfnZJ29y5h62k="
    private let vectorSignature = "xagk9v0CAdZpxNh/IqzIijJFA3B1hKgy0YRdF3lVjUH+CKhF/jTe01nSyB1FrQtC06j22xVOwQ9EfUAL8QavBg=="
    private let vectorPayload = Data("Mystral test payload\n".utf8)

    func testAcceptsSignatureFromReleaseScript() {
        XCTAssertTrue(UpdateSignature.isValid(signature: vectorSignature, dmgData: vectorPayload,
                                              version: "9.9.9", publicKeyBase64: vectorPublicKey))
    }

    func testRejectsTamperedDMGWrongVersionAndWrongKey() {
        XCTAssertFalse(UpdateSignature.isValid(signature: vectorSignature, dmgData: vectorPayload + Data([0]),
                                               version: "9.9.9", publicKeyBase64: vectorPublicKey))
        XCTAssertFalse(UpdateSignature.isValid(signature: vectorSignature, dmgData: vectorPayload,
                                               version: "9.9.10", publicKeyBase64: vectorPublicKey))
        XCTAssertFalse(UpdateSignature.isValid(signature: vectorSignature, dmgData: vectorPayload, version: "9.9.9"),
                       "the embedded release key did not sign the test vector")
    }

    func testRejectsMalformedInput() {
        XCTAssertFalse(UpdateSignature.isValid(signature: "", dmgData: vectorPayload, version: "9.9.9",
                                               publicKeyBase64: vectorPublicKey))
        XCTAssertFalse(UpdateSignature.isValid(signature: "not base64!", dmgData: vectorPayload, version: "9.9.9",
                                               publicKeyBase64: vectorPublicKey))
        XCTAssertFalse(UpdateSignature.isValid(signature: vectorSignature, dmgData: vectorPayload, version: "9.9.9",
                                               publicKeyBase64: "AAAA"))
    }

    func testEmbeddedReleaseKeyIsAValidEd25519PublicKey() throws {
        let data = try XCTUnwrap(Data(base64Encoded: UpdateSignature.publicKeyBase64))
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: data))
    }

    func testAutomaticInstallRequiresMatchingSignatureAsset() {
        let base = "https://github.com/fexxdev/Mystral/releases/download/v2.0.0/"
        XCTAssertNil(UpdateChecker.signedDMGURL(in: [("Mystral-2.0.0.dmg", base + "Mystral-2.0.0.dmg")]))
        XCTAssertEqual(
            UpdateChecker.signedDMGURL(in: [
                ("Mystral-2.0.0.dmg", base + "Mystral-2.0.0.dmg"),
                ("Mystral-2.0.0.dmg.sig", base + "Mystral-2.0.0.dmg.sig")
            ])?.absoluteString,
            base + "Mystral-2.0.0.dmg"
        )
        XCTAssertNil(UpdateChecker.signedDMGURL(in: [
            ("Mystral-2.0.0.dmg", "https://evil.example/Mystral-2.0.0.dmg"),
            ("Mystral-2.0.0.dmg.sig", "https://evil.example/Mystral-2.0.0.dmg.sig")
        ]))
    }

    func testSignatureURLMustBelongToTheMystralRelease() {
        XCTAssertTrue(UpdateChecker.isTrustedSignatureURL(URL(string: "https://github.com/fexxdev/Mystral/releases/download/v2.0.0/Mystral-2.0.0.dmg.sig")!))
        XCTAssertFalse(UpdateChecker.isTrustedSignatureURL(URL(string: "https://github.com/fexxdev/Mystral/releases/download/v2.0.0/Mystral-2.0.0.dmg")!))
        XCTAssertFalse(UpdateChecker.isTrustedSignatureURL(URL(string: "https://github.com/other/Mystral/releases/download/v2.0.0/Mystral-2.0.0.dmg.sig")!))
    }

    func testBundleMustMatchTheSignedVersion() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MystralSigned-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: root) }
        let contents = root.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: NSDictionary = [
            "CFBundleIdentifier": "com.fexxdev.Mystral",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "2.0.0"
        ]
        XCTAssertTrue(info.write(to: contents.appendingPathComponent("Info.plist"), atomically: true))

        XCTAssertTrue(UpdateChecker.isValidBundleMetadata(at: root.path, currentVersion: "1.0.0", expectedVersion: "2.0.0"))
        XCTAssertFalse(UpdateChecker.isValidBundleMetadata(at: root.path, currentVersion: "1.0.0", expectedVersion: "2.0.1"))
    }
}
