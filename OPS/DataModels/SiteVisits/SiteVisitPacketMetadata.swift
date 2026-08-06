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

/// Additive checklist anatomy carried beside the legacy packet strings.
///
/// String raw values deliberately cross the packet boundary instead of the
/// app enum. A future client may author a kind this build does not know yet;
/// that row must still decode and render as text rather than invalidating the
/// entire visit record.
struct SiteVisitPacketChecklistItem: Codable, Equatable {
    let fieldId: String?
    let label: String?
    let value: String?
    let kind: String?
    let artifactCount: Int?

    enum CodingKeys: String, CodingKey {
        case fieldId = "field_id"
        case label
        case value
        case kind
        case artifactCount = "artifact_count"
    }

    init(
        fieldId: String?,
        label: String?,
        value: String?,
        kind: String?,
        artifactCount: Int?
    ) {
        self.fieldId = fieldId
        self.label = label
        self.value = value
        self.kind = kind
        self.artifactCount = artifactCount
    }
}

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
    let checklistItems: [SiteVisitPacketChecklistItem]?
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
        case checklistItems = "checklist_items"
        case address
        case contactName    = "contact_name"
        case companyName    = "company_name"
        case deckDesignId   = "deck_design_id"
    }

    init(
        siteVisitId: String?,
        photoCount: Int?,
        measurements: [Measurement]?,
        notes: [String]?,
        checklist: [String]?,
        checklistItems: [SiteVisitPacketChecklistItem]? = nil,
        address: String?,
        contactName: String?,
        companyName: String?,
        deckDesignId: String?
    ) {
        self.siteVisitId = siteVisitId
        self.photoCount = photoCount
        self.measurements = measurements
        self.notes = notes
        self.checklist = checklist
        self.checklistItems = checklistItems
        self.address = address
        self.contactName = contactName
        self.companyName = companyName
        self.deckDesignId = deckDesignId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        siteVisitId = try container.decodeIfPresent(String.self, forKey: .siteVisitId)
        photoCount = try container.decodeIfPresent(Int.self, forKey: .photoCount)
        measurements = try container.decodeIfPresent([Measurement].self, forKey: .measurements)
        notes = try container.decodeIfPresent([String].self, forKey: .notes)
        checklist = try container.decodeIfPresent([String].self, forKey: .checklist)

        // This key is additive. A future or partially-written item must not
        // invalidate the legacy packet fields that older clients still need.
        do {
            checklistItems = try container.decodeIfPresent(
                [SiteVisitPacketChecklistItem].self,
                forKey: .checklistItems
            )
        } catch {
            checklistItems = nil
        }

        address = try container.decodeIfPresent(String.self, forKey: .address)
        contactName = try container.decodeIfPresent(String.self, forKey: .contactName)
        companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        deckDesignId = try container.decodeIfPresent(String.self, forKey: .deckDesignId)
    }

    static func decode(from json: String?) -> SiteVisitPacketMetadata? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SiteVisitPacketMetadata.self, from: data)
    }
}
