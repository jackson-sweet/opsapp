//
//  TaskMaterialDTOs.swift
//  OPS
//
//  Cut-list rows attached to a project_task. Inserted at install-task
//  creation by CutListMaterializer (Phase 11) once recipe rows are
//  resolved against the line item's configured_options snapshot.
//
//  Table shape (public.task_materials):
//    id                  uuid PK (default gen_random_uuid())
//    task_id             uuid FK project_tasks.id
//    inventory_item_id   uuid (legacy, nullable; pre-catalog material rows)
//    quantity            double precision
//    source              text (default 'stock')
//    catalog_variant_id  uuid FK catalog_variants.id (nullable for legacy rows)
//

import Foundation

struct TaskMaterialDTO: Codable, Identifiable {
    let id: String
    let taskId: String
    let inventoryItemId: String?
    let quantity: Double
    let source: String
    let catalogVariantId: String?

    enum CodingKeys: String, CodingKey {
        case id
        case taskId             = "task_id"
        case inventoryItemId    = "inventory_item_id"
        case quantity
        case source
        case catalogVariantId   = "catalog_variant_id"
    }
}

/// Insert payload — id and source default on the server side (gen_random_uuid /
/// 'stock'). We always emit `source = 'stock'` explicitly so we don't depend on
/// the column default in case it ever changes.
struct CreateTaskMaterialDTO: Codable {
    let taskId: String
    let catalogVariantId: String
    let quantity: Double
    let source: String

    enum CodingKeys: String, CodingKey {
        case taskId             = "task_id"
        case catalogVariantId   = "catalog_variant_id"
        case quantity
        case source
    }

    init(taskId: String, catalogVariantId: String, quantity: Double, source: String = "stock") {
        self.taskId = taskId
        self.catalogVariantId = catalogVariantId
        self.quantity = quantity
        self.source = source
    }
}
