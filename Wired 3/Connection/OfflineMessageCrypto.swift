//
//  OfflineMessageCrypto.swift
//  Wired 3
//
//  ECIES encryption for offline messages using X25519 + ChaCha20-Poly1305.
//
//  Threat model — what this provides:
//    - Confidentiality of message bodies at rest in the server database
//      against passive inspection by a server administrator.
//    - Integrity of the ciphertext (Poly1305 authentication tag).
//
//  Threat model — what this does NOT provide (yet):
//    - Sender authentication: messages are not signed. The server, which is
//      trusted to attribute the sender, could substitute one. Planned for
//      a future revision (Ed25519 signature over sender/recipient/plaintext).
//    - Recipient public-key authenticity / TOFU: the client refetches the
//      recipient public key on every send and trusts the server's response.
//      A malicious server can MITM new conversations transparently. Planned:
//      persist fingerprints client-side and warn on change.
//
//  In short: confidentiality holds against an honest-but-curious server,
//  not against an actively malicious one.
//
//  Blob format (Base64-encoded):
//    [0x01: 1 byte version]
//    [ephemeral X25519 public key: 32 bytes]
//    [ChaCha20-Poly1305 nonce: 12 bytes]
//    [ciphertext: variable]
//    [Poly1305 authentication tag: 16 bytes]
//
//  Key derivation: HKDF-SHA256(
//    ikm  = X25519(ephemeral_private, recipient_public),
//    salt = ephemeral_public_key_bytes,
//    info = "wired-offline-v1"
//  )
//

import CryptoKit
import Foundation

enum OfflineMessageCrypto {
    private static let blobVersion: UInt8 = 0x01
    private static let hkdfInfo = Data("wired-offline-v1".utf8)

    enum CryptoError: Error {
        case invalidKey
        case invalidBlob
        case unsupportedVersion
        case invalidPlaintext
    }

    static func encrypt(plaintext: String, recipientPublicKeyData: Data) throws -> String {
        guard let plaintextData = plaintext.data(using: .utf8) else {
            throw CryptoError.invalidPlaintext
        }
        let recipientKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: recipientPublicKeyData)

        let ephemeralKey = Curve25519.KeyAgreement.PrivateKey()
        let ephemeralPubBytes = ephemeralKey.publicKey.rawRepresentation
        let sharedSecret = try ephemeralKey.sharedSecretFromKeyAgreement(with: recipientKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPubBytes,
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )
        let sealed = try ChaChaPoly.seal(plaintextData, using: symmetricKey)

        var blob = Data([blobVersion])
        blob.append(ephemeralPubBytes)           // 32 bytes
        blob.append(contentsOf: sealed.nonce)    // 12 bytes
        blob.append(sealed.ciphertext)
        blob.append(sealed.tag)                  // 16 bytes

        return blob.base64EncodedString()
    }

    static func decrypt(blob: String, privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> String {
        guard let data = Data(base64Encoded: blob), data.count > 61 else {
            throw CryptoError.invalidBlob
        }
        guard data[0] == blobVersion else {
            throw CryptoError.unsupportedVersion
        }

        let ephemeralPubKeyData = data[1..<33]
        let nonceData = data[33..<45]
        let ciphertextAndTag = data[45...]
        guard ciphertextAndTag.count >= 16 else { throw CryptoError.invalidBlob }

        let ephemeralKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: ephemeralPubKeyData)
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralKey)
        let symmetricKey = sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: ephemeralPubKeyData,
            sharedInfo: hkdfInfo,
            outputByteCount: 32
        )

        let ciphertext = ciphertextAndTag.dropLast(16)
        let tag = ciphertextAndTag.suffix(16)
        let sealedBox = try ChaChaPoly.SealedBox(
            nonce: ChaChaPoly.Nonce(data: nonceData),
            ciphertext: ciphertext,
            tag: tag
        )
        let plainData = try ChaChaPoly.open(sealedBox, using: symmetricKey)

        guard let result = String(data: plainData, encoding: .utf8) else {
            throw CryptoError.invalidPlaintext
        }
        return result
    }
}
