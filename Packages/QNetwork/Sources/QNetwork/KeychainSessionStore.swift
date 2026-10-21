import Foundation
import Security

/// Minimal blob storage the session store needs. The real implementation wraps SecItem*.
public protocol KeychainClient: Sendable {
    /// Returns nil when no item exists.
    func get() throws -> Data?
    /// Adds or replaces the item.
    func set(_ data: Data) throws
    /// Deleting a missing item is not an error.
    func delete() throws
}

/// A Keychain failure. Carries only the OSStatus, never item contents.
public struct KeychainError: Error, Equatable, CustomStringConvertible, Sendable {
    public let status: Int32
    public init(status: Int32) { self.status = status }
    public var description: String { "Keychain error \(status)" }
}

/// SessionStore backed by one Keychain item holding the JSON-encoded session.
public actor KeychainSessionStore: SessionStore {
    private struct Blob: Codable {
        var userId: String
        var accessToken: String
        var accessTokenExpiresAt: Double
        var refreshToken: String
    }

    /// errSecDiskFull
    private static let diskFullStatus: Int32 = -34
    private static let writeAttempts = 3

    private let client: KeychainClient
    private let freeBytes: @Sendable () -> Int64?
    private let notice: StorageNotice?

    public init(
        client: KeychainClient = SecItemKeychainClient(),
        freeBytes: @escaping @Sendable () -> Int64? = { StorageNotice.freeBytes() },
        notice: StorageNotice? = StorageNotice.shared
    ) {
        self.client = client
        self.freeBytes = freeBytes
        self.notice = notice
    }

    public func load() async -> StoredSession? {
        let data: Data?
        do {
            data = try client.get()
        } catch {
            return nil
        }
        guard let data = data else { return nil }
        guard let blob = try? JSONDecoder().decode(Blob.self, from: data) else {
            try? client.delete()
            return nil
        }
        return StoredSession(
            userId: blob.userId,
            accessToken: blob.accessToken,
            accessTokenExpiresAt: Date(timeIntervalSince1970: blob.accessTokenExpiresAt),
            refreshToken: blob.refreshToken
        )
    }

    public func save(_ session: StoredSession) async {
        _ = await saveChecked(session)
    }

    /// Writes with a few retries. A write that never lands deletes the item (a rotated-out refresh
    /// token left behind would trip reuse detection at the next launch and revoke every session).
    public func saveChecked(_ session: StoredSession) async -> SessionSaveResult {
        let blob = Blob(
            userId: session.userId,
            accessToken: session.accessToken,
            accessTokenExpiresAt: session.accessTokenExpiresAt.timeIntervalSince1970,
            refreshToken: session.refreshToken
        )
        guard let data = try? JSONEncoder().encode(blob) else { return .failed }
        var lastStatus: Int32?
        for _ in 0..<KeychainSessionStore.writeAttempts {
            do {
                try client.set(data)
                return .saved
            } catch let error as KeychainError {
                lastStatus = error.status
            } catch {
                lastStatus = nil
            }
        }
        try? client.delete()
        if isLowStorage(status: lastStatus) {
            notice?.post()
            return .lowStorage
        }
        return .failed
    }

    /// Out of space, not just any failure: a full disk, or under the threshold left.
    private func isLowStorage(status: Int32?) -> Bool {
        if status == KeychainSessionStore.diskFullStatus { return true }
        if let free = freeBytes() { return free < StorageNotice.lowBytes }
        return false
    }

    public func clear() async {
        try? client.delete()
    }
}

/// Thin Security framework implementation (generic password item).
public struct SecItemKeychainClient: KeychainClient {
    public static let defaultService = "com.qamooscheh.session"
    private let service: String
    private let account: String

    public init(service: String = SecItemKeychainClient.defaultService, account: String = "session") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    public func get() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    public func set(_ data: Data) throws {
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else { throw KeychainError(status: status) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}
