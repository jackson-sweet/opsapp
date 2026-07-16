//
//  PhoneContactsProvider.swift
//  OPS
//
//  Bug 388663d4 — reads the device address book so contacts can be blended
//  into the client picker. Requests Contacts access lazily on first intent,
//  indexes a lightweight projection off the main thread, and re-fetches the
//  full `CNContact` (image + postal) only when a contact is imported.
//
//  Denied / restricted access degrades silently to an empty index — the picker
//  simply shows OPS clients, and the existing "import from contacts" button
//  (out-of-process, permission-free) remains as the manual path.
//

import Foundation
import Contacts
import Combine

@MainActor
final class PhoneContactsProvider: ObservableObject {
    @Published private(set) var authorizationStatus: CNAuthorizationStatus
    @Published private(set) var suggestions: [PhoneContactSuggestion] = []
    @Published private(set) var isLoading = false

    private let store = CNContactStore()
    private var hasLoaded = false
    private var didRequestAccess = false

    init() {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    /// True when the current status permits reading the address book.
    var canRead: Bool { Self.isReadable(authorizationStatus) }

    /// Call on first intent to use the client picker. Requests access when
    /// undetermined, then loads the index. Safe to call repeatedly — the load
    /// runs at most once.
    func prepare() async {
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)

        if authorizationStatus == .notDetermined {
            await requestAccess()
        }
        if Self.isReadable(authorizationStatus) {
            await loadIfNeeded()
        }
    }

    private func requestAccess() async {
        guard !didRequestAccess else { return }
        didRequestAccess = true
        _ = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            store.requestAccess(for: .contacts) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        authorizationStatus = CNContactStore.authorizationStatus(for: .contacts)
    }

    private func loadIfNeeded() async {
        guard !hasLoaded, !isLoading else { return }
        await load()
    }

    private func load() async {
        isLoading = true
        let indexed = await Task.detached(priority: .userInitiated) { () -> [PhoneContactSuggestion] in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactIdentifierKey as CNKeyDescriptor,
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor
            ]
            let request = CNContactFetchRequest(keysToFetch: keys)
            request.sortOrder = .givenName
            var result: [PhoneContactSuggestion] = []
            do {
                try store.enumerateContacts(with: request) { contact, _ in
                    if let suggestion = PhoneContactSuggestion(contact: contact) {
                        result.append(suggestion)
                    }
                }
            } catch {
                // Access revoked mid-flight or a store error → leave empty.
            }
            return result
        }.value

        suggestions = indexed
        hasLoaded = true
        isLoading = false
    }

    /// Re-fetches the complete contact (image data + postal address) needed to
    /// create a client. Runs off the main thread; returns `nil` if the contact
    /// vanished or access was revoked.
    func fullContact(identifier: String) async -> CNContact? {
        let box = await Task.detached(priority: .userInitiated) { () -> UncheckedContactBox in
            let store = CNContactStore()
            let keys: [CNKeyDescriptor] = [
                CNContactGivenNameKey as CNKeyDescriptor,
                CNContactFamilyNameKey as CNKeyDescriptor,
                CNContactOrganizationNameKey as CNKeyDescriptor,
                CNContactJobTitleKey as CNKeyDescriptor,
                CNContactPhoneNumbersKey as CNKeyDescriptor,
                CNContactEmailAddressesKey as CNKeyDescriptor,
                CNContactPostalAddressesKey as CNKeyDescriptor,
                CNContactImageDataAvailableKey as CNKeyDescriptor,
                CNContactImageDataKey as CNKeyDescriptor
            ]
            return UncheckedContactBox(try? store.unifiedContact(withIdentifier: identifier, keysToFetch: keys))
        }.value
        return box.contact
    }

    /// Fetches the full contact for a suggestion and creates the OPS client in
    /// one call — used by surfaces that only hold the `PhoneContactSuggestion`
    /// (e.g. the change-client sheet) and never touch `CNContact` directly.
    func importClient(
        from suggestion: PhoneContactSuggestion,
        companyId: String,
        dataController: DataController
    ) async throws -> PhoneContactImporter.ImportResult {
        guard let contact = await fullContact(identifier: suggestion.id) else {
            throw PhoneContactImporter.ImportError.reloadFailed
        }
        return try await PhoneContactImporter.createClient(
            from: contact,
            companyId: companyId,
            dataController: dataController
        )
    }

    private static func isReadable(_ status: CNAuthorizationStatus) -> Bool {
        if status == .authorized { return true }
        if #available(iOS 18.0, *) {
            return status == .limited
        }
        return false
    }
}

/// `CNContact` is not `Sendable`; this box carries one result back across the
/// detached-task boundary without tripping concurrency checking.
private struct UncheckedContactBox: @unchecked Sendable {
    let contact: CNContact?
    init(_ contact: CNContact?) { self.contact = contact }
}
