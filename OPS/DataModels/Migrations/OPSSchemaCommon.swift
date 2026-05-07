//
//  OPSSchemaCommon.swift
//  OPS
//
//  Shared list of models whose persistent shape is identical across every
//  OPS schema version. Only models whose storage changes between versions
//  are redeclared per-version; everything else is referenced by its current
//  Swift type on both sides of the migration.
//

import Foundation
import SwiftData

enum OPSSchemaCommon {
    /// Every `@Model` in the OPS schema except `WizardState`.
    /// WizardState is the only model that differs between V1 and V2, so each
    /// VersionedSchema appends its own WizardState type to this list.
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

        // Catalog models (replaces old inventory models)
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

        // Product configurability
        ProductOption.self,
        ProductOptionValue.self,
        ProductPricingModifier.self,
        ProductMaterial.self,

        // Deck builder
        DeckDesign.self
    ]
}
