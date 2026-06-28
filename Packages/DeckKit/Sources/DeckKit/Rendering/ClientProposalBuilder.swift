import Foundation

public struct ClientProposalDeck: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct ProposalBranding: Codable, Equatable, Sendable {
    public var companyName: String
    public var logoURL: URL?
    public var accentHex: String

    public init(
        companyName: String,
        logoURL: URL?,
        accentHex: String
    ) {
        self.companyName = companyName
        self.logoURL = logoURL
        self.accentHex = accentHex
    }
}

public struct ClientProposalLineItem: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var description: String?
    public var quantity: Double
    public var unit: String
    public var unitPrice: Double
    public var lineTotal: Double
    public var formattedLineTotal: String
    public var isOptional: Bool
    public var sortOrder: Int

    public init(
        id: String,
        name: String,
        description: String?,
        quantity: Double,
        unit: String,
        unitPrice: Double,
        lineTotal: Double,
        formattedLineTotal: String,
        isOptional: Bool,
        sortOrder: Int
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.quantity = quantity
        self.unit = unit
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
        self.formattedLineTotal = formattedLineTotal
        self.isOptional = isOptional
        self.sortOrder = sortOrder
    }
}

public struct ClientProposalSection: Codable, Equatable, Identifiable, Sendable {
    public var id: String { category }
    public var category: String
    public var lineItems: [ClientProposalLineItem]
    public var subtotal: Double
    public var optionalTotal: Double
    public var formattedSubtotal: String
    public var formattedOptionalTotal: String

    public init(
        category: String,
        lineItems: [ClientProposalLineItem],
        subtotal: Double,
        optionalTotal: Double,
        formattedSubtotal: String,
        formattedOptionalTotal: String
    ) {
        self.category = category
        self.lineItems = lineItems
        self.subtotal = subtotal
        self.optionalTotal = optionalTotal
        self.formattedSubtotal = formattedSubtotal
        self.formattedOptionalTotal = formattedOptionalTotal
    }
}

public struct ClientProposal: Codable, Equatable, Sendable {
    public var title: String
    public var headline: String
    public var callToAction: String
    public var deck: ClientProposalDeck
    public var branding: ProposalBranding
    public var sections: [ClientProposalSection]
    public var subtotal: Double
    public var optionalTotal: Double
    public var total: Double
    public var formattedSubtotal: String
    public var formattedOptionalTotal: String
    public var formattedTotal: String

    public init(
        title: String,
        headline: String,
        callToAction: String,
        deck: ClientProposalDeck,
        branding: ProposalBranding,
        sections: [ClientProposalSection],
        subtotal: Double,
        optionalTotal: Double,
        total: Double,
        formattedSubtotal: String,
        formattedOptionalTotal: String,
        formattedTotal: String
    ) {
        self.title = title
        self.headline = headline
        self.callToAction = callToAction
        self.deck = deck
        self.branding = branding
        self.sections = sections
        self.subtotal = subtotal
        self.optionalTotal = optionalTotal
        self.total = total
        self.formattedSubtotal = formattedSubtotal
        self.formattedOptionalTotal = formattedOptionalTotal
        self.formattedTotal = formattedTotal
    }

    public var allText: String {
        var parts = [
            title,
            headline,
            callToAction,
            branding.companyName,
            formattedSubtotal,
            formattedOptionalTotal,
            formattedTotal,
        ]

        for section in sections {
            parts.append(section.category)
            parts.append(section.formattedSubtotal)
            parts.append(section.formattedOptionalTotal)
            for lineItem in section.lineItems {
                parts.append(lineItem.name)
                if let description = lineItem.description {
                    parts.append(description)
                }
                parts.append(lineItem.unit)
                parts.append(lineItem.formattedLineTotal)
            }
        }

        return parts.joined(separator: " ")
    }
}

public enum ClientProposalBuilder {
    public static func build(
        deck: ClientProposalDeck,
        lineItems: [EstimateGeneratorService.GeneratedLineItem],
        branding: ProposalBranding
    ) -> ClientProposal {
        let grouped = Dictionary(grouping: lineItems, by: \.category)
        let sections = orderedCategories(from: grouped.keys).map { category in
            buildSection(category: category, lineItems: grouped[category] ?? [])
        }

        let subtotal = sections.reduce(0) { $0 + $1.subtotal }
        let optionalTotal = sections.reduce(0) { $0 + $1.optionalTotal }

        return ClientProposal(
            title: "\(deck.title) proposal",
            headline: "Build price",
            callToAction: "Review proposal",
            deck: deck,
            branding: branding,
            sections: sections,
            subtotal: subtotal,
            optionalTotal: optionalTotal,
            total: subtotal,
            formattedSubtotal: formatCurrency(subtotal),
            formattedOptionalTotal: formatCurrency(optionalTotal),
            formattedTotal: formatCurrency(subtotal)
        )
    }

    private static func buildSection(
        category: String,
        lineItems: [EstimateGeneratorService.GeneratedLineItem]
    ) -> ClientProposalSection {
        let proposalItems = lineItems
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.name < rhs.name
                }
                return lhs.sortOrder < rhs.sortOrder
            }
            .map { item in
                let lineTotal = item.quantity * item.unitPrice
                return ClientProposalLineItem(
                    id: "\(item.category)-\(item.sortOrder)-\(item.name)",
                    name: item.name,
                    description: item.description,
                    quantity: item.quantity,
                    unit: item.unit,
                    unitPrice: item.unitPrice,
                    lineTotal: lineTotal,
                    formattedLineTotal: formatCurrency(lineTotal),
                    isOptional: item.isOptional,
                    sortOrder: item.sortOrder
                )
            }

        let subtotal = proposalItems
            .filter { !$0.isOptional }
            .reduce(0) { $0 + $1.lineTotal }
        let optionalTotal = proposalItems
            .filter(\.isOptional)
            .reduce(0) { $0 + $1.lineTotal }

        return ClientProposalSection(
            category: category,
            lineItems: proposalItems,
            subtotal: subtotal,
            optionalTotal: optionalTotal,
            formattedSubtotal: formatCurrency(subtotal),
            formattedOptionalTotal: formatCurrency(optionalTotal)
        )
    }

    private static func orderedCategories(from categories: Dictionary<String, [EstimateGeneratorService.GeneratedLineItem]>.Keys) -> [String] {
        let knownOrder = [
            "Surface",
            "Substructure",
            "Framing",
            "Railing",
            "Connecting Stairs",
            "Stairs",
            "Other",
        ]
        let known = knownOrder.filter { categories.contains($0) }
        let unknown = categories
            .filter { !knownOrder.contains($0) }
            .sorted()

        return known + unknown
    }

    private static func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        return formatter.string(from: NSNumber(value: value)) ?? "$\(String(format: "%.2f", value))"
    }
}
