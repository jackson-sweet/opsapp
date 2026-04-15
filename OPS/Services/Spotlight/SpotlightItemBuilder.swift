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
        attrs.contentDescription = [project.address, project.projectDescription]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
            .joined(separator: " • ")

        var keywords: [String] = [project.title]
        if let address = project.address, !address.isEmpty { keywords.append(address) }
        if let clientName = project.client?.name, !clientName.isEmpty { keywords.append(clientName) }
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
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.contact)
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

    // MARK: - Task

    static func buildTask(_ task: ProjectTask) -> CSSearchableItem {
        let attrs = CSSearchableItemAttributeSet(contentType: UTType.content)
        let title = (task.customTitle?.isEmpty == false ? task.customTitle : nil)
            ?? task.taskType?.display
            ?? "Task"
        attrs.title = title
        attrs.displayName = title

        var descParts: [String] = []
        if let projectTitle = task.project?.title { descParts.append(projectTitle) }
        if let notes = task.taskNotes, !notes.isEmpty { descParts.append(notes) }
        attrs.contentDescription = descParts.joined(separator: " • ")

        var keywords: [String] = [title]
        if let projectTitle = task.project?.title { keywords.append(projectTitle) }
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
}
