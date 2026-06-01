import Foundation

/// Pure conversion of a confirmed GuidedStructuredGroup into the catalog setup
/// draft structs the existing engine (`CatalogSetupWorkflow`) consumes.
/// All ids are derived deterministically from the group so rebuilt payloads
/// fingerprint identically (idempotent retries in the commit phase).
enum GuidedStockDraftBuilder {

    /// Attribute drafts for a group. Empty when the group is a single item.
    static func attributeDrafts(for group: GuidedStructuredGroup) -> [CatalogSetupAttributeDraft] {
        guard !group.isSingleItem else { return [] }
        return group.attributes
            .filter { !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      && !$0.values.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
            .map { attribute in
                CatalogSetupAttributeDraft(
                    id: attribute.id,
                    serverId: nil,
                    name: attribute.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    values: attribute.values
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                        .map { value in
                            CatalogSetupAttributeValueDraft(id: "\(attribute.id)::\(value)", serverId: nil, value: value)
                        }
                )
            }
    }

    /// Variant drafts for a group. Single-item → one option-less variant; else the attribute matrix.
    static func variantDrafts(for group: GuidedStructuredGroup) -> [CatalogSetupVariantDraft] {
        let attributes = attributeDrafts(for: group)
        if attributes.isEmpty {
            return [CatalogSetupVariantDraft(id: "\(group.id)::single", optionValueIds: [])]
        }
        return CatalogSetupWorkflow.generateVariantDrafts(attributes: attributes, invalidCombinations: [])
    }

    /// How many variants the group will produce.
    static func variantCount(for group: GuidedStructuredGroup) -> Int {
        variantDrafts(for: group).count
    }

    // MARK: - Variant labelling

    /// Human label for a variant within a group, e.g. "black · 6ft". Empty group/single → familyName.
    static func variantLabel(for group: GuidedStructuredGroup, variant: CatalogSetupVariantDraft) -> String {
        guard !group.isSingleItem, !group.attributes.isEmpty else { return group.familyName }
        let valueById: [String: String] = group.attributes.reduce(into: [:]) { acc, attr in
            for v in attr.values where !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                acc["\(attr.id)::\(v)"] = v
            }
        }
        let parts = group.attributes.compactMap { attr -> String? in
            guard let vid = variant.optionValueIdsByAttributeId[attr.id] else { return nil }
            return valueById[vid]
        }
        return parts.isEmpty ? group.familyName : parts.joined(separator: " · ")
    }

    // MARK: - Stock-unit drafts

    /// Physical stock-unit drafts for one variant's stock answers.
    ///
    /// Piece: one `.each` row whose `quantityValue` is the on-hand count.
    ///
    /// Length / Area: one `.roll` (`.full`) row per full unit — each with `quantityValue == 1`
    /// and `remainingLengthValue` set to the full length — plus one `.offcut` (`.partial`) row
    /// per leftover length entry. The mirrored-quantity aggregator sums `remainingLengthValue`
    /// once per row, so multiple identical physical units MUST be separate rows.
    ///
    /// Zero or blank answers produce no row. Ids are derived deterministically from
    /// `entry.variantKey` + position so rebuilt payloads fingerprint identically.
    static func stockUnitDrafts(
        for group: GuidedStructuredGroup,
        entry: GuidedStockEntry
    ) -> [CatalogSetupStockUnitDraft] {
        guard let measurement = group.measurement else { return [] }

        switch measurement {

        case .piece:
            guard let count = entry.pieceCount, count > 0 else { return [] }
            return [CatalogSetupStockUnitDraft(
                id: "\(entry.variantKey)::each",
                unitKind: .each,
                quantityValue: count,
                status: .full
            )]

        case .length, .area:
            var drafts: [CatalogSetupStockUnitDraft] = []
            let width = (measurement == .area) ? entry.fullUnitWidth : nil

            if let length = entry.fullUnitLength, length > 0,
               let countDouble = entry.fullUnitCount, countDouble > 0 {
                let count = Int(countDouble.rounded())
                for i in 0..<count {
                    drafts.append(CatalogSetupStockUnitDraft(
                        id: "\(entry.variantKey)::roll::\(i)",
                        unitKind: .roll,
                        widthValue: width,
                        widthUnit: group.widthUnit,
                        originalLengthValue: length,
                        remainingLengthValue: length,
                        lengthUnit: group.lengthUnit,
                        quantityValue: 1,
                        status: .full
                    ))
                }
            }

            for (j, offcut) in entry.offcutLengths.enumerated() where offcut > 0 {
                drafts.append(CatalogSetupStockUnitDraft(
                    id: "\(entry.variantKey)::offcut::\(j)",
                    unitKind: .offcut,
                    widthValue: width,
                    widthUnit: group.widthUnit,
                    originalLengthValue: offcut,
                    remainingLengthValue: offcut,
                    lengthUnit: group.lengthUnit,
                    quantityValue: 1,
                    status: .partial
                ))
            }

            return drafts
        }
    }
}
