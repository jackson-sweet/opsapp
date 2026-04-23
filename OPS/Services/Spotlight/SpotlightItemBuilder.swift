//
//  SpotlightItemBuilder.swift
//  OPS
//
//  Converts SwiftData entities into CSSearchableItem records for Spotlight.
//  Each builder sets display fields, keywords, thumbnailData, and native Spotlight
//  attributes (phoneNumbers, emailAddresses) where applicable.
//

import Foundation
import CoreSpotlight
import UniformTypeIdentifiers

enum SpotlightItemBuilder {

    // MARK: - Project

    static func buildProject(_ project: Project) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        attrs.title = project.title
        attrs.displayName = project.title

        let clientName = project.client?.name
        let trimmedAddress = shortAddress(project.address)
        attrs.contentDescription = [clientName, trimmedAddress, project.projectDescription]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " • ")

        var keywords: [String] = [project.title]
        if let address = project.address, !address.isEmpty { keywords.append(address) }
        if let clientName = clientName, !clientName.isEmpty { keywords.append(clientName) }
        keywords.append(project.status.displayName)
        attrs.keywords = keywords

        attrs.thumbnailData = SpotlightThumbnailRenderer.projectThumbnail(
            imageURLs: project.getProjectImages()
        )

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.project, id: project.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.project,
            attributeSet: attrs
        )
    }

    // MARK: - Client

    static func buildClient(_ client: Client) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        attrs.title = client.name
        attrs.displayName = client.name
        attrs.contentDescription = [client.phoneNumber, client.email, client.address]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " • ")

        var keywords: [String] = [client.name]
        if let address = client.address, !address.isEmpty { keywords.append(address) }
        if let notes = client.notes, !notes.isEmpty { keywords.append(notes) }
        attrs.keywords = keywords

        if let phone = client.phoneNumber, !phone.isEmpty {
            attrs.phoneNumbers = [phone]
        }
        if let email = client.email, !email.isEmpty {
            attrs.emailAddresses = [email]
        }

        attrs.thumbnailData = SpotlightThumbnailRenderer.clientThumbnail(
            avatarURL: client.profileImageURL
        )

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.client, id: client.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.client,
            attributeSet: attrs
        )
    }

    // MARK: - SubClient
    //
    // Bug G4 — site contacts / billing contacts attached to a client should
    // be searchable from Spotlight by name, phone, email, and title. We
    // include the parent client's name in the content description and
    // keywords so searches can find sub-clients by either side of the
    // relationship (e.g. "Mitchell Acme" or just "Mitchell").

    static func buildSubClient(_ subClient: SubClient, parentClientName: String?) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)

        // Display "Name — Title @ ParentClient" when all three are present;
        // degrade gracefully if any piece is missing.
        let displayTitle: String = {
            if let title = subClient.title, !title.isEmpty {
                return "\(subClient.name) — \(title)"
            }
            return subClient.name
        }()
        attrs.title = displayTitle
        attrs.displayName = displayTitle

        attrs.contentDescription = [parentClientName, subClient.phoneNumber, subClient.email]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " • ")

        var keywords: [String] = [subClient.name]
        if let title = subClient.title, !title.isEmpty { keywords.append(title) }
        if let parent = parentClientName, !parent.isEmpty { keywords.append(parent) }
        if let address = subClient.address, !address.isEmpty { keywords.append(address) }
        attrs.keywords = keywords

        if let phone = subClient.phoneNumber, !phone.isEmpty {
            attrs.phoneNumbers = [phone]
        }
        if let email = subClient.email, !email.isEmpty {
            attrs.emailAddresses = [email]
        }

        // SubClients don't carry their own avatar; we can leave thumbnail nil
        // rather than reuse the parent's (which would be misleading at a glance).

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.subClient, id: subClient.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.subClient,
            attributeSet: attrs
        )
    }

    // MARK: - Task

    static func buildTask(_ task: ProjectTask) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        let taskName = (task.customTitle?.isEmpty == false ? task.customTitle : nil)
            ?? task.taskType?.display
            ?? "Task"
        let projectTitle = task.project?.title
        let displayTitle: String = {
            if let projectTitle = projectTitle, !projectTitle.isEmpty {
                return "\(taskName), \(projectTitle)"
            }
            return taskName
        }()
        attrs.title = displayTitle
        attrs.displayName = displayTitle

        let clientName = task.project?.client?.name
        let trimmedAddress = shortAddress(task.project?.address)
        attrs.contentDescription = [clientName, trimmedAddress, task.taskNotes]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " • ")

        var keywords: [String] = [taskName]
        if let projectTitle = projectTitle, !projectTitle.isEmpty { keywords.append(projectTitle) }
        if let clientName = clientName, !clientName.isEmpty { keywords.append(clientName) }
        if let address = task.project?.address, !address.isEmpty { keywords.append(address) }
        if let notes = task.taskNotes, !notes.isEmpty { keywords.append(notes) }
        attrs.keywords = keywords

        let parentImages = task.project?.getProjectImages() ?? []
        attrs.thumbnailData = SpotlightThumbnailRenderer.taskThumbnail(
            parentProjectImageURLs: parentImages
        )

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.task, id: task.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.task,
            attributeSet: attrs
        )
    }

    // MARK: - Invoice

    static func buildInvoice(_ invoice: Invoice, clientName: String?) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        let title = invoice.invoiceNumber.isEmpty ? "Invoice" : invoice.invoiceNumber
        attrs.title = title
        attrs.displayName = title

        var descParts: [String] = []
        if let t = invoice.title, !t.isEmpty { descParts.append(t) }
        if let client = clientName, !client.isEmpty { descParts.append(client) }
        descParts.append(String(format: "$%.2f", invoice.total))
        attrs.contentDescription = descParts.joined(separator: " • ")

        var keywords: [String] = [title]
        if let t = invoice.title, !t.isEmpty { keywords.append(t) }
        if let client = clientName, !client.isEmpty { keywords.append(client) }
        attrs.keywords = keywords

        attrs.thumbnailData = SpotlightThumbnailRenderer.invoiceThumbnail()

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.invoice, id: invoice.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.invoice,
            attributeSet: attrs
        )
    }

    // MARK: - Estimate

    static func buildEstimate(_ estimate: Estimate, clientName: String?) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        let title = estimate.estimateNumber.isEmpty ? "Estimate" : estimate.estimateNumber
        attrs.title = title
        attrs.displayName = title

        var descParts: [String] = []
        if let t = estimate.title, !t.isEmpty { descParts.append(t) }
        if let client = clientName, !client.isEmpty { descParts.append(client) }
        descParts.append(String(format: "$%.2f", estimate.total))
        attrs.contentDescription = descParts.joined(separator: " • ")

        var keywords: [String] = [title]
        if let t = estimate.title, !t.isEmpty { keywords.append(t) }
        if let client = clientName, !client.isEmpty { keywords.append(client) }
        attrs.keywords = keywords

        attrs.thumbnailData = SpotlightThumbnailRenderer.estimateThumbnail()

        let itemId = SpotlightItemId.make(domain: SpotlightDomain.estimate, id: estimate.id)
        return CSSearchableItem(
            uniqueIdentifier: itemId,
            domainIdentifier: SpotlightDomain.estimate,
            attributeSet: attrs
        )
    }

    // MARK: - Address Formatting

    /// Trim a raw address down to the parts a field user scans for in a Spotlight result:
    /// street + area, dropping postal codes, province abbreviations, and country tokens.
    /// Returns the joined first two meaningful parts, or nil if nothing survives.
    private static func shortAddress(_ address: String?) -> String? {
        guard let raw = address?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        var cleaned = raw
        if let regex = try? NSRegularExpression(pattern: #"\b[A-Z]\d[A-Z]\s?\d[A-Z]\d\b"#) {
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
        }

        let dropTokens: Set<String> = [
            "AB", "BC", "MB", "NB", "NL", "NS", "NT", "NU", "ON", "PE", "QC", "SK", "YT",
            "CANADA", "USA", "CA"
        ]

        var parts = cleaned
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        while let last = parts.last, dropTokens.contains(last.uppercased()) {
            parts.removeLast()
        }

        parts = parts.map { part -> String in
            var words = part.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            while let last = words.last, dropTokens.contains(last.uppercased()) {
                words.removeLast()
            }
            return words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }

        let joined = parts.prefix(2).joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }
}
