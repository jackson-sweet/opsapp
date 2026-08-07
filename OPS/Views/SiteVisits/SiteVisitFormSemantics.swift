//
//  SiteVisitFormSemantics.swift
//  OPS
//
//  Deterministic section order for the primary site-visit form.
//

import Foundation

struct SiteVisitLeadSummaryPresentation: Equatable {
    let text: String

    var accessibilityLabel: String {
        let spokenText = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "Lead summary. \(spokenText)"
    }
}

enum SiteVisitPrimaryFormSection: Equatable, Identifiable {
    case identity
    case leadSummary(SiteVisitLeadSummaryPresentation)
    case checklist
    case notes

    var id: String {
        switch self {
        case .identity: return "identity"
        case .leadSummary: return "lead-summary"
        case .checklist: return "checklist"
        case .notes: return "notes"
        }
    }
}

enum SiteVisitPrimaryFormSemantics {
    static func orderedSections(boundLeadSummary rawSummary: String?) -> [SiteVisitPrimaryFormSection] {
        var sections: [SiteVisitPrimaryFormSection] = [.identity]

        if let summary = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            sections.append(.leadSummary(.init(text: summary)))
        }

        sections.append(contentsOf: [.checklist, .notes])
        return sections
    }
}
