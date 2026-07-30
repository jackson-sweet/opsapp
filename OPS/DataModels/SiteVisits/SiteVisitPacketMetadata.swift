//
//  SiteVisitPacketMetadata.swift
//  OPS
//
//  Decoded `project_notes.content_metadata` for `event_kind == "site_visit"`,
//  written by `SiteVisitPacketNote.build`.
//
//  This is the visit's travelling record: it is authored once, on the
//  capturing device, and then read by every teammate's phone — so the site
//  visit renders for people who were never there and hold none of its local
//  artifacts. Every field is optional so partial, legacy, and future shapes
//  all decode; new keys are additive only, for the same reason.
//
//  NOTHING DENOMINATED IN CURRENCY BELONGS HERE. This blob syncs into
//  `project_notes.content_metadata`, which OPS-Web renders with no financial
//  gate of its own — a figure written here is a figure published past
//  `finances.view` to every web viewer of the project's activity feed. Money
//  is resolved at render time from the local opportunity instead
//  (`SiteVisitRecord.assemble`), where the gate actually applies.
//

import Foundation

struct SiteVisitPacketMetadata: Decodable, Equatable {
    struct Measurement: Decodable, Equatable {
        let label: String
        let value: String
    }

    let siteVisitId: String?
    let photoCount: Int?
    let measurements: [Measurement]?
    let notes: [String]?
    let checklist: [String]?
    /// Where the visit happened. Additive — packets written before the record
    /// carry nil and simply render no ADDRESS line.
    let address: String?
    /// Who the operator met, and the business when there is one. Additive.
    let contactName: String?
    let companyName: String?
    /// Set when the visit produced or continued a deck design. Additive.
    let deckDesignId: String?

    enum CodingKeys: String, CodingKey {
        case siteVisitId    = "site_visit_id"
        case photoCount     = "photo_count"
        case measurements
        case notes
        case checklist
        case address
        case contactName    = "contact_name"
        case companyName    = "company_name"
        case deckDesignId   = "deck_design_id"
    }

    static func decode(from json: String?) -> SiteVisitPacketMetadata? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SiteVisitPacketMetadata.self, from: data)
    }
}
