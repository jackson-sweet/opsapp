// Additive nullable form write-state and immutable outbox actor/receipt metadata.
// Released V1–V27 retain the exact frozen models from8553b1b4.
import Foundation
import SwiftData

enum OPSSchemaV28: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(28, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.v28CommonModels
            + OPSSchemaCommon.v19OpportunityModel
            + OPSSchemaCommon.v26DeckDesignModel
            + OPSSchemaCommon.v13ProjectNoteModel
            + OPSSchemaCommon.v18PhotoAnnotationModel
            + OPSSchemaCommon.v22ActivityModel
            + OPSSchemaCommon.v24SiteVisitModel
            + OPSSchemaCommon.v4CoreModels
            + OPSSchemaCommon.v4TaskModels
            + OPSSchemaCommon.v8CatalogModels
            + OPSSchemaCommon.v4ReminderModels
            + OPSSchemaCommon.v6ForecastModels
            + OPSSchemaCommon.v17VinylOrderModel
            + OPSSchemaCommon.v8CatalogSetupModels
            + OPSSchemaCommon.v27ProjectPhotoModel
            + OPSSchemaCommon.v10StockUnitEventModels
            + OPSSchemaCommon.v28SiteVisitCaptureModels
            + OPSSchemaCommon.v20SiteVisitIdentityModels
            + [
                WizardState.self,
                CalendarMirrorMap.self,
                ProjectPrimaryContactSelection.self
            ]
    }
}
