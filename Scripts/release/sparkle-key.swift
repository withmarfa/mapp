// Sparkle's EdDSA keys, as the release workflow needs them.
//
//   swift sparkle-key.swift generate      prints a new private key (the base64 of its 32-byte seed), then its public key
//   swift sparkle-key.swift public        reads a private key on standard input and prints its public key
//
// `generate` is for a dry run's throwaway key; `public` lets a tag run check that the key it signs with is the one the
// app was built to trust.
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("::error::\(message)\n".utf8))
    exit(1)
}

switch CommandLine.arguments.dropFirst().first {
case "generate":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public":
    let input = (readLine(strippingNewline: true) ?? "").trimmingCharacters(in: .whitespaces)
    guard let seed = Data(base64Encoded: input), seed.count == 32 else { fail("The private key is not the base64 of 32 bytes.") }
    guard let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: seed) else { fail("The private key is not an Ed25519 seed.") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
default:
    fail("usage: sparkle-key.swift generate|public")
}
