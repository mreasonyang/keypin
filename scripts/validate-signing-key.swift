// CI only. This reads a temporary exported Sparkle key, never the login Keychain.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    fputs(message + "\n", stderr)
    exit(1)
}
guard CommandLine.arguments.count == 2,
      let encoded = try? String(contentsOfFile: CommandLine.arguments[1], encoding: .utf8),
      let secret = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
      let expectedString = ProcessInfo.processInfo.environment["SPARKLE_PUBLIC_KEY"],
      let expected = Data(base64Encoded: expectedString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
    fail("Invalid Sparkle key configuration")
}
let actual: Data
if secret.count == 32 {
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: secret) else {
        fail("Invalid Sparkle private seed")
    }
    actual = key.publicKey.rawRepresentation
} else if secret.count == 96 {
    // Sparkle's legacy export contains a 64-byte expanded private key and 32-byte public key.
    actual = secret.suffix(32)
} else {
    fail("Unsupported Sparkle exported-key format")
}
guard actual == expected else { fail("SPARKLE_PRIVATE_KEY does not match SPARKLE_PUBLIC_KEY") }
print("PASS: Sparkle private and public keys match")
