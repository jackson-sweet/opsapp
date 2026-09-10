import Foundation
import SwiftData

/// Called only inside the capture coordinator's owned transaction. Client,
/// contact, draft binding and standard outbox writes share its commit/rollback.
@MainActor
enum SiteVisitIdentityClientStore {
    enum SaveError: Error { case invalidIdentity }

    struct Result {
        let client: Client
        let createState: ClientCreateState
        let queuedWork: Bool
    }

    static func upsert(draft: SiteVisitIdentityDraft, clientName: String,
                       companyId: String, context: ModelContext) throws -> Result {
        let company = companyId.lowercased()
        guard draft.companyId.lowercased() == company else {
            throw SaveError.invalidIdentity
        }
        let linkedId = clean(draft.clientId)?.lowercased()
        let id = linkedId ?? UUID().uuidString.lowercased()
        let upper = id.uppercased()
        var descriptor = FetchDescriptor<Client>(predicate: #Predicate {
            $0.id == id || $0.id == upper
        })
        descriptor.fetchLimit = 1
        let existing = try context.fetch(descriptor).first
        if let existing {
            guard existing.companyId?.lowercased() == company, existing.deletedAt == nil else {
                throw SaveError.invalidIdentity
            }
        } else if linkedId != nil {
            // A missing linked parent must not silently become a duplicate.
            throw SaveError.invalidIdentity
        }

        let client = existing ?? Client(id: id, name: clientName, companyId: company)
        var operations = try fetchOperations(entityType: .client, entityId: id, context: context)
        var fields: [String: Any] = [:]
        if existing == nil {
            client.lastSyncedAt = nil
            client.createdAt = Date()
            context.insert(client)
            fields = ["id": id, "company_id": company, "name": clientName]
        }
        if client.name != clientName { client.name = clientName; fields["name"] = clientName }
        let email = clean(draft.preferredEmail)
        let phone = clean(draft.phoneNumber)
        let address = clean(draft.address)
        let notes = clean(draft.notes)
        if client.email != email { client.email = email; fields["email"] = email as Any? ?? NSNull() }
        if client.phoneNumber != phone { client.phoneNumber = phone; fields["phone_number"] = phone as Any? ?? NSNull() }
        if client.address != address { client.address = address; fields["address"] = address as Any? ?? NSNull() }
        // Blank capture notes never meant an explicit client-note clear. Older
        // resumed drafts can be blank beside a client with saved notes, so keep
        // the prior nonblank-only update contract without inventing clear intent.
        if let notes, client.notes != notes { client.notes = notes; fields["notes"] = notes }
        var queuedWork = false
        if !fields.isEmpty {
            client.needsSync = true
            try enqueue(entityType: .client, entityId: id,
                operationType: existing == nil ? "create" : "update",
                fields: fields, operations: &operations, context: context)
            queuedWork = true
        }

        var seenEmails = Set(client.subClients.filter { $0.deletedAt == nil }
            .compactMap { clean($0.email)?.lowercased() })
        if let email { seenEmails.insert(email.lowercased()) }
        for value in draft.additionalEmails {
            guard let email = clean(value), seenEmails.insert(email.lowercased()).inserted else { continue }
            let contact = SubClient(id: UUID().uuidString.lowercased(),
                name: clean(draft.contactName) ?? clientName, title: "Site contact",
                email: email, address: address)
            contact.needsSync = true
            context.insert(contact)
            contact.client = client
            if !client.subClients.contains(where: { $0.id == contact.id }) { client.subClients.append(contact) }
            var contactFields: [String: Any] = ["id": contact.id, "client_id": id,
                "company_id": company, "name": contact.name, "title": "Site contact", "email": email]
            if let address { contactFields["address"] = address }
            var contactOperations: [SyncOperation] = []
            try enqueue(entityType: .subClient, entityId: contact.id, operationType: "create",
                fields: contactFields, operations: &contactOperations, context: context)
            queuedWork = true
        }
        if draft.clientId != id { draft.clientId = id; draft.touch() }
        var createState = ClientLeadAutocreateQueue.clientCreateState(forClientId: id, in: operations)
        if createState == .landed,
           !operations.contains(where: { $0.operationType == "create" && $0.status == "completed" }),
           operations.contains(where: { $0.operationType == "create" && $0.status == "declined" }) {
            createState = .rejected
        }
        return Result(client: client, createState: createState, queuedWork: queuedWork)
    }

    private static func fetchOperations(entityType: SyncEntityType, entityId: String,
                                   context: ModelContext) throws -> [SyncOperation] {
        // SwiftData's first predicate fetch on a never-populated operation table
        // can trap. A count proves the table has rows without registering them.
        guard try context.fetchCount(FetchDescriptor<SyncOperation>()) > 0 else { return [] }
        let type = entityType.rawValue
        let upper = entityId.uppercased()
        return try context.fetch(FetchDescriptor<SyncOperation>(predicate: #Predicate {
            $0.entityType == type && ($0.entityId == entityId || $0.entityId == upper)
        }, sortBy: [SortDescriptor(\SyncOperation.createdAt)]))
    }

    private static func enqueue(entityType: SyncEntityType, entityId: String,
                                operationType: String, fields: [String: Any],
                                operations: inout [SyncOperation], context: ModelContext) throws {
        var protectedFields = Set(fields.keys)
        for (server, local) in [("phone_number", "phoneNumber"), ("company_id", "companyId"),
                                ("profile_image_url", "profileImageURL"), ("client_id", "client")] {
            if fields[server] != nil { protectedFields.insert(local) }
        }
        if let pending = operations.last(where: {
            ["pending", "failed"].contains($0.status) && ["create", "update"].contains($0.operationType)
        }) {
            guard var payload = try JSONSerialization.jsonObject(with: pending.payload) as? [String: Any] else {
                throw SaveError.invalidIdentity
            }
            payload.merge(fields) { _, new in new }
            pending.payload = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            protectedFields.formUnion(pending.getChangedFields())
            pending.changedFields = protectedFields.sorted().joined(separator: ",")
            pending.status = "pending"
            pending.retryCount = 0
            pending.lastAttemptedAt = nil
            pending.lastError = nil
            return
        }
        // Preserve frozen/stopped payloads. A later edit waits behind that exact
        // owner; editing a contact is not permission to revive a stopped send.
        let predecessor = operations.last(where: {
            ["inProgress", "parked", "declined", "quarantined"].contains($0.status)
        })
        let operation = SyncOperation(entityType: entityType.rawValue, entityId: entityId,
            operationType: operationType,
            payload: try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]),
            changedFields: protectedFields.sorted(), dependsOnId: predecessor?.id.uuidString.lowercased())
        context.insert(operation)
        operations.append(operation)
    }

    private static func clean(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
