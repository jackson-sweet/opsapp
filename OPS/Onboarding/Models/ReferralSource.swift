//
//  ReferralSource.swift
//  OPS
//
//  "How'd you find us" option set (Unified Attribution P2).
//
//  This is the only acquisition signal that survives an App Store install — no
//  ad click id crosses that boundary — and iOS is where the majority of OPS
//  signups happen, so it is asked here as well as on web.
//
//  The SLUG is what gets persisted to `companies.referral_method`, never the
//  label: copy is expected to change, slugs are not, so historical aggregation
//  survives a rewording.
//
//  ⚠️ Keep this list identical to `ops-web/src/lib/data/referral-sources.ts`.
//  If the two vocabularies drift, the platforms' answers stop aggregating and
//  the signal is silently split in two.
//
//  Note: seven Bubble-era companies carry free-text values ("Instagram",
//  "Word of Mouth (Onsite)", "Internet Advertisement", "Other"). Those are
//  deliberately NOT migrated — normalize at read time in the attribution
//  dashboard rather than rewriting self-reported customer data on a guess.
//

import Foundation

enum ReferralSource: String, CaseIterable, Identifiable, Sendable {
    case instagram
    case facebook
    case youtube
    case google
    case appStore = "app_store"
    case wordOfMouth = "word_of_mouth"
    case other

    var id: String { rawValue }

    /// The stored value. Mirrors the web slug exactly.
    var slug: String { rawValue }

    /// Chip copy. Sentence case, Mohave chip voice — matches the trade chips.
    var label: String {
        switch self {
        case .instagram:   return "Instagram"
        case .facebook:    return "Facebook"
        case .youtube:     return "YouTube"
        case .google:      return "Google"
        case .appStore:    return "App Store"
        case .wordOfMouth: return "Someone told me"
        case .other:       return "Other"
        }
    }

    /// Resolve a stored slug back to a case. Returns nil for legacy free-text
    /// values, which are intentionally left un-migrated.
    static func from(slug: String?) -> ReferralSource? {
        guard let slug else { return nil }
        return ReferralSource(rawValue: slug)
    }
}
