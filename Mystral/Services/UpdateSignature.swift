import CryptoKit
import Foundation

/// Ed25519 check that an update DMG was signed with the release key, which lives only
/// in the maintainer's Keychain (scripts/update-key.sh). GitHub access alone is not enough.
enum UpdateSignature {
    /// Public half of the release key. build-dmg.sh refuses to sign with a key that does not match.
    static let publicKeyBase64 = "Ec4GpEOWuQNsZ+ikMelGAZVxY5lQfFruXlOMPVGaQXM="
    static let maxSignatureBytes = 512

    /// Must stay identical to `message` in scripts/update-signing.swift.
    static func message(version: String, dmgData: Data) -> Data {
        let digest = SHA256.hash(data: dmgData).map { String(format: "%02x", $0) }.joined()
        return Data("com.fexxdev.Mystral update v1\nversion=\(version)\nsha256=\(digest)\n".utf8)
    }

    static func isValid(
        signature signatureText: String,
        dmgData: Data,
        version: String,
        publicKeyBase64: String = publicKeyBase64
    ) -> Bool {
        guard let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let keyData = Data(base64Encoded: publicKeyBase64),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return false
        }
        return publicKey.isValidSignature(signature, for: message(version: version, dmgData: dmgData))
    }

    static func isValid(signature: String, dmgAt url: URL, version: String) -> Bool {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return false }
        return isValid(signature: signature, dmgData: data, version: version)
    }
}
