// Verifies a Sparkle EdDSA (ed25519) signature of a file against a base64
// public key, independently of generate_appcast. Used by
// Scripts/update-appcast.sh to check the new feed item against the SUPublicEDKey
// baked into the bundle, so a key mismatch is caught without relying on the
// text of Sparkle's warning.
//
// Usage: swift Scripts/verify-ed-signature.swift <public-key-b64> <signature-b64> <file>
// Exit 0 if valid, 1 if invalid, 2 on bad input.
import CryptoKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4,
      let pub = Data(base64Encoded: args[1]),
      let sig = Data(base64Encoded: args[2]),
      let file = FileManager.default.contents(atPath: args[3]),
      let key = try? Curve25519.Signing.PublicKey(rawRepresentation: pub)
else {
    FileHandle.standardError.write(Data("usage: verify-ed-signature <pubkey-b64> <sig-b64> <file>\n".utf8))
    exit(2)
}
exit(key.isValidSignature(sig, for: file) ? 0 : 1)
