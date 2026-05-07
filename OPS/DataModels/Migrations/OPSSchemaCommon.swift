//
//  OPSSchemaCommon.swift
//  OPS
//
//  Models whose persistent shape is identical across V2 and V3 — i.e.,
//  everything except `WizardState` (V1↔V2 boundary) and the inventory↔catalog
//  swap (V2↔V3 boundary). Each VersionedSchema appends its version-specific
//  model types on top of this list.
//

import Foundation
import SwiftData

enum OPSSchemaCommon {
    /// Models present in both V2 and V3 (and unchanged across the V2→V3
    /// boundary). The inventory entities live only in V2; the catalog/product-
    /// extension entities live only in V3. WizardState is appended per-version
    /// so V1's legacy shape stays scoped to V1.
    static let unchangedModels: [any PersistentModel.Type] = [
        // Core data models
        User.self,
        Project.self,
        Company.self,
        TeamMember.self,
        Client.self,
        SubClient.self,
        ProjectTask.self,
        TaskType.self,
        TaskStatusOption.self,
        SyncOperation.self,
        OpsContact.self,

        // Supabase-backed models
        Opportunity.self,
        Activity.self,
        FollowUp.self,
        StageTransition.self,
        Estimate.self,
        EstimateLineItem.self,
        Invoice.self,
        InvoiceLineItem.self,
        Payment.self,
        Product.self,
        SiteVisit.self,
        ProjectNote.self,
        PhotoAnnotation.self,
        CalendarUserEvent.self,

        // Offline-first sync models
        TimeEntry.self,
        SignatureCapture.self,
        FormSubmission.self,
        LocalPhoto.self,

        // Deck builder
        DeckDesign.self
    ]

    /// V2-only models: the legacy inventory entities. V3 drops these and
    /// replaces them with the catalog_* / product_* entities listed in
    /// `OPSSchemaV3.catalogModels`.
    static let v2InventoryModels: [any PersistentModel.Type] = [
        InventoryItem.self,
        InventoryTag.self,
        InventoryUnit.self,
        InventorySnapshot.self,
        InventorySnapshotItem.self
    ]

    /// V3-only models: catalog & variant model + configurable Products +
    /// the company-defaults adapter map. Replaces the V2 inventory entities.
    static let v3CatalogModels: [any PersistentModel.Type] = [
        CatalogCategory.self,
        CatalogItem.self,
        CatalogVariant.self,
        CatalogOption.self,
        CatalogOptionValue.self,
        CatalogVariantOptionValue.self,
        CatalogTag.self,
        CatalogItemTag.self,
        CatalogUnit.self,
        CatalogSnapshot.self,
        CatalogSnapshotItem.self,
        CatalogOrder.self,
        CatalogOrderItem.self,
        CompanyDefaultProduct.self,

        ProductOption.self,
        ProductOptionValue.self,
        ProductPricingModifier.self,
        ProductMaterial.self
    ]
}
