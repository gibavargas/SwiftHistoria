import Foundation
import OSLog
import Security

/// Keychain-backed storage for API keys and the Turso auth token.
///
/// Design: read-through with UserDefaults fallback.
/// 1. Reads prefer the Keychain (protected at rest by the OS).
/// 2. If the Keychain has no entry, UserDefaults is consulted — this keeps
///    pre-migration saves, test-injected suites, and unsigned development
///    builds (where SecItem may be unavailable) working unchanged.
/// 3. Migration moves a defaults value into the Keychain and deletes the
///    defaults copy ONLY when the Keychain write succeeds, so an unusable
///    Keychain can never strand a player's key.
///
/// The Settings/campaign-setup SecureFields write through `set(_:forKey:)`;
/// the underlying services read through `string(forKey:)`.
enum NativeSecretStore {
    private static let logger = Logger(
        subsystem: "com.gibavargas.SwiftHistoria",
        category: "SecretStore"
    )

    static let service = "com.gibavargas.SwiftHistoria"

    /// Keys that must live in the Keychain (migrated from UserDefaults).
    static let managedKeys = [
        "NVIDIA_API_KEY",
        "OPENROUTER_API_KEY",
        "ZAI_API_KEY",
        "TURSO_AUTH_TOKEN"
    ]

    /// Keychain availability gate. Inside test runners and unsigned dev
    /// launches, SecItem calls can block indefinitely, so the Keychain is
    /// bypassed and reads fall straight through to UserDefaults. This is an
    /// environment-availability gate, not a behavioral branch.
    static let isKeychainAvailable = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil

    // MARK: - Read

    static func string(forKey key: String, defaults: UserDefaults = .standard) -> String? {
        if isKeychainAvailable, let keychainValue = keychainString(forKey: key) {
            return keychainValue
        }
        return defaults.string(forKey: key)
    }

    // MARK: - Write / Delete

    static func set(_ value: String?, forKey key: String, defaults: UserDefaults = .standard) {
        guard let value, !value.isEmpty else {
            delete(forKey: key, defaults: defaults)
            return
        }
        guard isKeychainAvailable else {
            defaults.set(value, forKey: key)
            return
        }
        let status = keychainSet(value, forKey: key)
        if status == errSecSuccess {
            // Keychain is authoritative now; remove the plaintext copy.
            defaults.removeObject(forKey: key)
        } else {
            // Keychain unavailable (e.g. unsigned dev build): fall back to
            // defaults so the key still works, and say so in the log.
            logger.warning("Keychain write failed status=\(status) for \(key, privacy: .public); storing in UserDefaults")
            defaults.set(value, forKey: key)
        }
    }

    static func delete(forKey key: String, defaults: UserDefaults = .standard) {
        keychainDelete(forKey: key)
        defaults.removeObject(forKey: key)
    }

    // MARK: - Migration

    /// Moves any managed keys found in UserDefaults into the Keychain.
    /// Safe to call on every launch: idempotent, and it never deletes the
    /// defaults copy unless the Keychain write verifiably succeeded.
    static func migrateIfNeeded(defaults: UserDefaults = .standard) {
        guard isKeychainAvailable else { return }
        for key in managedKeys {
            guard let value = defaults.string(forKey: key),
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else { continue }
            let status = keychainSet(value, forKey: key)
            if status == errSecSuccess {
                defaults.removeObject(forKey: key)
                logger.info("Migrated \(key, privacy: .public) to Keychain")
            } else {
                logger.warning("Keychain migration skipped status=\(status) for \(key, privacy: .public)")
            }
        }
    }

    // MARK: - SecItem plumbing

    private static func baseQuery(forKey key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }

    private static func keychainString(forKey key: String) -> String? {
        var query = baseQuery(forKey: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func keychainSet(_ value: String, forKey key: String) -> OSStatus {
        let data = Data(value.utf8)
        // Update first; insert when the item does not exist yet.
        let update: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(baseQuery(forKey: key) as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return errSecSuccess
        }
        if updateStatus == errSecItemNotFound {
            var add = baseQuery(forKey: key)
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            return SecItemAdd(add as CFDictionary, nil)
        }
        return updateStatus
    }

    private static func keychainDelete(forKey key: String) {
        SecItemDelete(baseQuery(forKey: key) as CFDictionary)
    }
}
