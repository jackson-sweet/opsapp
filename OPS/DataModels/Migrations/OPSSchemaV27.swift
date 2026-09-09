//
//  OPSSchemaV27.swift
//  OPS
//
//  Schema version 27.0.0 — a photo may document a task.
//
//  Adds the nullable `ProjectPhoto.taskId` mirroring the server's new
//  `project_photos.task_id`. Every other entity keeps its V26 registration,
//  and V9–V26 keep the frozen `OPSSchemaLegacyProjectPhotoV26.ProjectPhoto`
//  so released fingerprints — and installed stores — stay recognizable.
//

import Foundation
import SwiftData

enum OPSSchemaV27: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(27, 0, 0) }

    static var models: [any PersistentModel.Type] {
        OPSSchemaCommon.unchangedModels
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
            + OPSSchemaCommon.v11SiteVisitCaptureModels
            + OPSSchemaCommon.v20SiteVisitIdentityModels
            + [
                WizardState.self,
                CalendarMirrorMap.self,
                ProjectPrimaryContactSelection.self
            ]
    }
}
