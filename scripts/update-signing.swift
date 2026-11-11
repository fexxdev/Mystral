// Ed25519 signing for Mystral update DMGs. Private keys are read from stdin, never argv.
//
//   swift scripts/update-signing.swift generate                     > raw private key (base64)
//   swift scripts/update-signing.swift public-key       < private   > public key (base64)
//   swift scripts/update-signing.swift sign <dmg> <ver>  < private   > signature (base64)
//   swift scripts/update-signing.swift verify <dmg> <ver> <sig-file> <public-key-base64>
//
// The signed message must stay identical to UpdateSignature.message in the app.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("update-signing: \(message)\n".utf8))
    exit(1)
}

func message(version: String, dmg: URL) -> Data {
    guard let data = try? Data(contentsOf: dmg, options: .mappedIfSafe) else { fail("cannot read \(dmg.path)") }
    let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    return Data("com.fexxdev.Mystral update v1\nversion=\(version)\nsha256=\(digest)\n".utf8)
}

func readPrivateKey() -> Curve25519.Signing.PrivateKey {
    let input = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let raw = Data(base64Encoded: input),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("stdin is not a base64 Ed25519 private key")
    }
    return key
}

let args = CommandLine.arguments.dropFirst()
switch (args.first, args.count) {
case ("generate", 1):
    print(Curve25519.Signing.PrivateKey().rawRepresentation.base64EncodedString())
case ("public-key", 1):
    print(readPrivateKey().publicKey.rawRepresentation.base64EncodedString())
case ("sign", 3):
    let a = Array(args)
    let key = readPrivateKey()
    guard let signature = try? key.signature(for: message(version: a[2], dmg: URL(fileURLWithPath: a[1]))) else {
        fail("signing failed")
    }
    print(signature.base64EncodedString())
case ("verify", 5):
    let a = Array(args)
    guard let sigText = try? String(contentsOfFile: a[3], encoding: .utf8),
          let signature = Data(base64Encoded: sigText.trimmingCharacters(in: .whitespacesAndNewlines)),
          let keyData = Data(base64Encoded: a[4]),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
        fail("malformed signature or public key")
    }
    guard publicKey.isValidSignature(signature, for: message(version: a[2], dmg: URL(fileURLWithPath: a[1]))) else {
        fail("signature does not verify")
    }
    print("signature ok")
default:
    fail("usage: generate | public-key | sign <dmg> <version> | verify <dmg> <version> <sig-file> <public-key>")
}
