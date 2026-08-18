//
//  SiteVisitFormSemantics.swift
//  OPS
//
//  Deterministic section order for the primary site-visit form.
//

import Foundation

struct SiteVisitLeadSummaryPresentation: Equatable {
    /// Where the band's text came from. The band declares its own provenance:
    /// the agent tint is reserved for agent-written copy, so a lead's own
    /// inquiry text is shown in the neutral treatment rather than borrowing it.
    enum Source: Equatable {
        case agentSummary
        case leadDescription

        /// Panel eyebrow — uppercase, as every panel label on this screen is.
        var label: String {
            switch self {
            case .agentSummary:    return "LEAD SUMMARY"
            case .leadDescription: return "LEAD DETAILS"
            }
        }

        /// Sentence-case form for VoiceOver, which should not shout.
        var spokenLabel: String {
            switch self {
            case .agentSummary:    return "Lead summary"
            case .leadDescription: return "Lead details"
            }
        }
    }

    let text: String
    var source: Source = .agentSummary

    var accessibilityLabel: String {
        let spokenText = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return "\(source.spokenLabel). \(spokenText)"
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
    static func orderedSections(
        boundLeadSummary rawSummary: String?,
        leadDescription rawDescription: String? = nil
    ) -> [SiteVisitPrimaryFormSection] {
        var sections: [SiteVisitPrimaryFormSection] = [.identity]

        if let presentation = leadSummary(
            boundLeadSummary: rawSummary,
            leadDescription: rawDescription
        ) {
            sections.append(.leadSummary(presentation))
        }

        sections.append(contentsOf: [.checklist, .notes])
        return sections
    }

    /// What a linked lead has to say for itself, in priority order.
    ///
    /// Item 886f1a02 — the band used to be gated on the agent summary alone,
    /// so linking one of the many leads the agent has not written up yet put
    /// nothing above the checklist and the operator was back to remembering
    /// the job. The lead's own inquiry text answers the same question, so it
    /// is the fallback; only a lead with neither gets no band at all, because
    /// an empty band is chrome that says nothing.
    static func leadSummary(
        boundLeadSummary rawSummary: String?,
        leadDescription rawDescription: String?
    ) -> SiteVisitLeadSummaryPresentation? {
        if let summary = rawSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
           !summary.isEmpty {
            return SiteVisitLeadSummaryPresentation(text: summary, source: .agentSummary)
        }

        if let description = rawDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return SiteVisitLeadSummaryPresentation(text: description, source: .leadDescription)
        }

        return nil
    }
}
