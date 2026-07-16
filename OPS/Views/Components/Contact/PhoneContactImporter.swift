//
//  PhoneContactImporter.swift
//  OPS
//
//  Bug 388663d4 — one code path for turning a device `CNContact` into an OPS
//  client. Shared by the create-project client picker and the change-client
//  sheet so both create the client, upload any avatar, and seed the matching
//  pipeline lead identically. Mirrors `ClientSheet.createNewClient`.
//

import Foundation
import Contacts
import SwiftData
import UIKit

@MainActor
enum PhoneContactImporter {
    enum ImportError: LocalizedError {
        case missingName
        case reloadFailed

        var errorDescription: String? {
            switch self {
            case .missingName:
                return "Contact has no name. Edit the contact in iOS Contacts and try again."
            case .reloadFailed:
                return "Imported the contact, but couldn't load the new client. Try refreshing."
            }
        }
    }

    struct ImportResult {
        let client: Client
        let opportunityId: String?
    }

    /// Full path: create the client (+avatar, +pipeline lead) from a contact
    /// and return the saved model. Posts the same `ClientCreatedSuccess` toast
    /// the manual create path posts. Selection / wizard side-effects stay with
    /// the caller so each surface can react in its own way.
    @discardableResult
    static func createClient(
        from contact: CNContact,
        companyId: String,
        dataController: DataController,
        postSuccessToast: Bool = true
    ) async throws -> ImportResult {
        let name = composeName(from: contact)
        guard !name.isEmpty else { throw ImportError.missingName }

        let clientId = UUID().uuidString.lowercased()
        let profileImageUrl = await uploadAvatar(from: contact, clientId: clientId, companyId: companyId)
        let dto = makeClientDTO(from: contact, companyId: companyId, clientId: clientId, profileImageUrl: profileImageUrl)

        _ = try await dataController.createClient(dto: dto)
        guard let savedClient = dataController.getAllClients(for: companyId).first(where: { $0.id == clientId }) else {
            throw ImportError.reloadFailed
        }

        let opportunityId = try await createPipelineLead(for: savedClient, companyId: companyId, dataController: dataController)

        if postSuccessToast {
            NotificationCenter.default.post(
                name: Notification.Name("ClientCreatedSuccess"),
                object: nil,
                userInfo: [
                    "clientName": savedClient.name,
                    "clientId": savedClient.id,
                    "leadCreated": true,
                    "opportunityId": opportunityId
                ]
            )
        }

        return ImportResult(client: savedClient, opportunityId: opportunityId)
    }

    // MARK: - Building blocks (also used directly by ProjectFormSheet)

    /// Display name from given/family, falling back to organization. Empty
    /// result means the contact has no usable name and import should abort.
    static func composeName(from contact: CNContact) -> String {
        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)
        let full = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !full.isEmpty { return full }
        return contact.organizationName.trimmingCharacters(in: .whitespaces)
    }

    /// Single comma-separated address line from the contact's first postal
    /// address, matching the shape `AddressAutocompleteField` emits.
    static func composeAddress(from contact: CNContact) -> String? {
        guard contact.isKeyAvailable(CNContactPostalAddressesKey),
              let postal = contact.postalAddresses.first?.value else { return nil }
        var components: [String] = []
        if !postal.street.isEmpty { components.append(postal.street) }
        if !postal.city.isEmpty { components.append(postal.city) }
        if !postal.state.isEmpty { components.append(postal.state) }
        if !postal.postalCode.isEmpty { components.append(postal.postalCode) }
        let joined = components.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    static func makeClientDTO(
        from contact: CNContact,
        companyId: String,
        clientId: String,
        profileImageUrl: String?
    ) -> SupabaseClientDTO {
        let phoneRaw = contact.phoneNumbers.first?.value.stringValue
        let phone = (phoneRaw?.isEmpty ?? true) ? nil : phoneRaw
        let emailRaw: String? = contact.emailAddresses.first.map { $0.value as String }
        let email = (emailRaw?.isEmpty ?? true) ? nil : emailRaw

        return SupabaseClientDTO(
            id: clientId,
            bubbleId: nil,
            companyId: companyId,
            name: composeName(from: contact),
            email: email,
            phoneNumber: phone,
            address: composeAddress(from: contact),
            latitude: nil,
            longitude: nil,
            notes: nil,
            profileImageUrl: profileImageUrl,
            deletedAt: nil
        )
    }

    /// Best-effort avatar upload; a failure returns `nil` so client creation
    /// still proceeds (matches `ClientSheet.createNewClient`). `isKeyAvailable`
    /// guards against reading image data on a contact fetched without it.
    static func uploadAvatar(from contact: CNContact, clientId: String, companyId: String) async -> String? {
        guard contact.isKeyAvailable(CNContactImageDataKey),
              let imageData = contact.imageData,
              let image = UIImage(data: imageData) else {
            return nil
        }
        do {
            return try await PresignedURLUploadService.shared.uploadClientProfileImage(
                image,
                clientId: clientId,
                companyId: companyId
            )
        } catch {
            print("[CONTACT_IMPORT] ⚠️ Profile image upload failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates the matching pipeline lead so an imported client surfaces in the
    /// sales pipeline exactly like a manually-created one. Throws so the caller
    /// does not report a complete import when the lead is missing.
    @discardableResult
    static func createPipelineLead(for client: Client, companyId: String, dataController: DataController) async throws -> String {
        guard let dto = ClientLeadAutocreate.makeOpportunityDTO(for: client, companyId: companyId) else {
            throw ClientLeadAutocreateError.missingClientName
        }

        let repository = OpportunityRepository(companyId: companyId)
        do {
            let created = try await repository.create(dto)
            let model = created.toModel()
            if let context = dataController.modelContext {
                let oppId = created.id
                let descriptor = FetchDescriptor<Opportunity>(
                    predicate: #Predicate<Opportunity> { $0.id == oppId }
                )
                let existing = (try? context.fetch(descriptor)) ?? []
                if existing.isEmpty {
                    context.insert(model)
                    try? context.save()
                }
            }
            return created.id
        } catch {
            print("[CONTACT_IMPORT] ⚠️ Failed to create matching lead for client \(client.id): \(error)")
            throw ClientLeadAutocreateError.creationFailed
        }
    }
}
