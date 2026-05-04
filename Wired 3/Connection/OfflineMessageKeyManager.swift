//
//  OfflineMessageKeyManager.swift
//  Wired 3
//
//  Manages X25519 keypairs for E2E encrypted offline messages.
//  Private keys are stored in the macOS Keychain and never leave the device.
//

import CryptoKit
import Foundation
import Security

final class OfflineMessageKeyManager {
    static let shared = OfflineMessageKeyManager()

    private let service = "fr.read-write.Wired3"
    private let accountPrefix = "offline-key-"

    private init() {}

    /// Returns the existing keypair for the given account or generates a new one.
    ///
    /// `accountID` MUST disambiguate the user across servers — typically
    /// `"<host>|<login>"`. A bare login is unsafe because the same login on
    /// two different Wired servers would collide and overwrite each other.
    ///
    /// `legacyUsername`, when set, lets us upgrade users who previously stored
    /// a key under just their login. If a legacy key is found, it is copied to
    /// the new account-scoped slot so older messages remain decryptable.
    func loadOrCreateKeyPair(forAccount accountID: String,
                             legacyUsername: String? = nil) -> Curve25519.KeyAgreement.PrivateKey {
        if let existing = privateKey(forAccount: accountID) {
            return existing
        }
        if let legacy = legacyUsername,
           let migrated = privateKey(forAccount: legacy) {
            save(migrated, forAccount: accountID)
            return migrated
        }
        let newKey = Curve25519.KeyAgreement.PrivateKey()
        save(newKey, forAccount: accountID)
        return newKey
    }

    /// Returns the stored keypair without creating a new one.
    func privateKey(forAccount accountID: String) -> Curve25519.KeyAgreement.PrivateKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountPrefix + accountID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) else {
            return nil
        }
        return key
    }

    @discardableResult
    private func save(_ key: Curve25519.KeyAgreement.PrivateKey, forAccount accountID: String) -> Bool {
        let account = accountPrefix + accountID
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: key.rawRepresentation,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }
}
