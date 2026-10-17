import Foundation
import Combine
import QModel
import QNetwork
import QData
#if canImport(Contacts)
import Contacts
#endif

/// The contacts calls the screen needs. `ContactsRepository` conforms; tests use a fake.
public protocol ContactsService: Sendable {
    func findable() async throws -> ContactsFindableResponse
    func setFindable(_ value: Bool) async throws -> ContactsFindableResponse
    func match(_ hashes: [String]) async throws -> [ContactMatchResponse]
}

extension ContactsRepository: ContactsService {}

/// Reads the email addresses in the address book. The system one needs the contacts permission;
/// tests inject a fake so no real contact is touched.
public protocol ContactEmailReading: Sendable {
    /// Asks for (or confirms) permission to read contacts; false when the person declined.
    func requestAccess() async throws -> Bool
    /// Every email address on every contact. Raw addresses never leave the device; callers hash them.
    func emails() async throws -> [String]
}

#if canImport(Contacts)
/// CNContactStore behind `ContactEmailReading`. The permission prompt is a device check.
public struct SystemContactEmails: ContactEmailReading {
    public init() {}

    public func requestAccess() async throws -> Bool {
        try await CNContactStore().requestAccess(for: .contacts)
    }

    public func emails() async throws -> [String] {
        try await Task.detached(priority: .userInitiated) { () throws -> [String] in
            let store = CNContactStore()
            let request = CNContactFetchRequest(keysToFetch: [CNContactEmailAddressesKey as CNKeyDescriptor])
            var found: [String] = []
            try store.enumerateContacts(with: request) { contact, _ in
                for address in contact.emailAddresses {
                    found.append(address.value as String)
                }
            }
            return found
        }.value
    }
}
#endif

/// State for "find friends from contacts" on the Friends screen. Everything is gated on the
/// findable opt-in (off by default), and only SHA-256 hashes of emails are ever sent.
@MainActor
public final class ContactsMatchingModel: ObservableObject {
    /// The person's own opt-in; false until the server says otherwise.
    @Published public private(set) var findable = false
    /// False for an account with no email on file (Google-only): turning the switch on can never match them.
    @Published public private(set) var canBeFound = true
    @Published public private(set) var loaded = false
    @Published public private(set) var working = false
    /// nil until a search has run.
    @Published public private(set) var matches: [ContactMatchResponse]?
    @Published public private(set) var truncated = false
    @Published public private(set) var message: String?

    private let service: ContactsService?
    private let reader: ContactEmailReading?
    private let onUnauthorized: (@Sendable () -> Void)?

    public init(service: ContactsService?, reader: ContactEmailReading?, onUnauthorized: (@Sendable () -> Void)? = nil) {
        self.service = service
        self.reader = reader
        self.onUnauthorized = onUnauthorized
    }

    /// Reads the opt-in. Safe on every appearance.
    public func load() async {
        guard let service = service else { return }
        do {
            apply(try await service.findable())
            loaded = true
            message = nil
        } catch {
            message = failureMessage(error, fallback: "Couldn't load your contacts setting.")
        }
    }

    /// Turns the opt-in on or off. Turning it off also clears what a search found.
    public func setFindable(_ value: Bool) async {
        guard let service = service, !working else { return }
        working = true
        message = nil
        do {
            apply(try await service.setFindable(value))
            if !findable {
                matches = nil
                truncated = false
            }
        } catch {
            message = failureMessage(error, fallback: "Couldn't change that setting.")
        }
        working = false
    }

    /// Hashes the address book's emails and asks the server who is on Qamooscheh. Does nothing unless opted in.
    public func findFriends() async {
        guard let service = service, let reader = reader, findable, !working else { return }
        working = true
        message = nil
        defer { working = false }
        do {
            guard try await reader.requestAccess() else {
                message = "Allow Contacts access in Settings to find friends."
                return
            }
            let emails = try await reader.emails()
            let prepared = ContactHashing.hashes(emails: emails, limit: ContactsRepository.maxHashesPerDay)
            truncated = prepared.truncated
            guard !prepared.hashes.isEmpty else {
                matches = []
                message = "No email addresses found in your contacts."
                return
            }
            var found: [String: ContactMatchResponse] = [:]
            var index = 0
            let size = ContactsRepository.maxHashesPerCall
            while index < prepared.hashes.count {
                let chunk = Array(prepared.hashes[index ..< min(index + size, prepared.hashes.count)])
                for match in try await service.match(chunk) { found[match.userId] = match }
                index += size
            }
            matches = Self.sorted(Array(found.values))
        } catch {
            message = failureMessage(error, fallback: "Couldn't check your contacts right now.")
        }
    }

    /// Display name then user id, as the server sorts, so the order never reflects the contacts' order.
    static func sorted(_ list: [ContactMatchResponse]) -> [ContactMatchResponse] {
        list.sorted { a, b in
            let an = a.displayName ?? ""
            let bn = b.displayName ?? ""
            if an != bn { return an < bn }
            return a.userId < b.userId
        }
    }

    private func apply(_ response: ContactsFindableResponse) {
        findable = response.findable
        canBeFound = response.canBeFound
    }

    private func failureMessage(_ error: Error, fallback: String) -> String {
        if (error as? ApiError)?.status == 401 || error is SessionExpiredError { onUnauthorized?() }
        return AuthRules.message(for: error, fallback: fallback)
    }
}
