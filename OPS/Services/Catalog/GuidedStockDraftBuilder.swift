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
}
