//
//  Feedback.swift
//  OPS
//
//  Central catalog of every in-app feedback event. One place for all toast copy
//  (one ops-copywriter pass). Call sites reference these symbols, never inline
//  strings — so the voice stays consistent and the full event set is auditable.
//
//  Voice: terse, tactical, confident. Every word earns its place.
//  Contract (enforced by FeedbackCatalogTests): "// " prefix, UPPERCASE body.
//
//  Toasts fire ONCE, at the user-action boundary — never in loops or sync/merge
//  paths. Errors are tiered: FYI errors auto-dismiss; single-action errors hold
//  until tapped; multi-choice / destructive / critical stay modal (not here).
//

import Foundation

enum Feedback {

    // MARK: - Generic helpers (long tail)

    static func saved(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) SAVED", tone: .success) }
    static func deleted(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) DELETED", tone: .success) }
    static func created(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) CREATED", tone: .success) }
    static func updated(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) UPDATED", tone: .success) }

    // MARK: - Error labels (used by .errorToast). Tone is always .error.

    enum Err {
        static let operationFailed       = "// OPERATION FAILED"
        static let saveFailed            = "// SAVE FAILED"
        static let deleteFailed          = "// DELETE FAILED"
        static let settingsUpdateFailed  = "// SETTINGS UPDATE FAILED"
        static let categoryUpdateFailed  = "// CATEGORY UPDATE FAILED"
        static let batchUpdateFailed     = "// BATCH UPDATE FAILED"
        static let conversionFailed      = "// CONVERSION FAILED"
        static let voteFailed            = "// VOTE FAILED"
        static let requestFailed         = "// REQUEST FAILED"
        static let mergeFailed           = "// MERGE FAILED"
        static let reportFailed          = "// REPORT FAILED"
        static let restoreFailed         = "// RESTORE FAILED"
        static let featureNotAvailable   = "// FEATURE NOT AVAILABLE"
        static let uploadFailed          = "// UPLOAD FAILED"
        static let scaleRequired         = "// SET A SCALE FIRST"
        static let connectionsPreventDelete = "// CONNECTED — CAN'T DELETE"
        static let invalidCode           = "// CODE NOT RECOGNIZED"
        static let joinFailed            = "// JOIN FAILED"
        static let signInFailed          = "// SIGN IN FAILED"
        static let locationRequired      = "// LOCATION ACCESS REQUIRED"
        static let notificationsDisabled = "// NOTIFICATIONS OFF"
        static let paymentFailed         = "// PAYMENT FAILED"
        static let noDepth               = "// NO DEPTH HERE — AIM AT A SOLID SURFACE"

        /// Every error label — covered by the contract test.
        static let all: [String] = [
            operationFailed, saveFailed, deleteFailed, settingsUpdateFailed, categoryUpdateFailed,
            batchUpdateFailed, conversionFailed, voteFailed, requestFailed, mergeFailed, reportFailed,
            restoreFailed, featureNotAvailable, uploadFailed, scaleRequired, connectionsPreventDelete,
            invalidCode, joinFailed, signInFailed, locationRequired, notificationsDisabled, paymentFailed,
            noDepth,
        ]
    }

    // MARK: - Invoices

    enum Invoice {
        static let sent            = Toast(label: "// INVOICE SENT", tone: .success)
        static let voided          = Toast(label: "// INVOICE VOIDED", tone: .success)
        static let writtenOff      = Toast(label: "// WRITTEN OFF", tone: .success)
        static let paymentRecorded = Toast(label: "// PAYMENT IN", tone: .success)
        static let approved        = Toast(label: "// INVOICE APPROVED", tone: .success)
        static let reminderSent    = Toast(label: "// REMINDER SENT", tone: .success)
    }

    // MARK: - Estimates

    enum Estimate {
        static let created         = Toast(label: "// ESTIMATE CREATED", tone: .success)
        static let updated         = Toast(label: "// ESTIMATE UPDATED", tone: .success)
        static let saved           = Toast(label: "// ESTIMATE SAVED", tone: .success)
        static let sent            = Toast(label: "// ESTIMATE SENT", tone: .success)
        static let converted       = Toast(label: "// CONVERTED TO INVOICE", tone: .success)
        static let progressInvoice = Toast(label: "// PROGRESS INVOICE OUT", tone: .success)
        static let lineItemAdded   = Toast(label: "// LINE ADDED", tone: .success)
        static let lineItemUpdated = Toast(label: "// LINE UPDATED", tone: .success)
        static let lineItemDeleted = Toast(label: "// LINE REMOVED", tone: .success)
        static let revisionsSent   = Toast(label: "// REVISIONS SENT", tone: .success)
    }

    // MARK: - Expenses

    enum Expense {
        static let saved           = Toast(label: "// EXPENSE SAVED", tone: .success)
        static let changesSaved    = Toast(label: "// CHANGES SAVED", tone: .success)
        static let submitted       = Toast(label: "// EXPENSE SUBMITTED", tone: .success)
        static let deleted         = Toast(label: "// EXPENSE DELETED", tone: .success)
        static let approved        = Toast(label: "// EXPENSE APPROVED", tone: .success)
        static let rejected        = Toast(label: "// EXPENSE REJECTED", tone: .warning)
        static let flagged         = Toast(label: "// FLAGGED", tone: .warning)
        static let flagCleared     = Toast(label: "// FLAG CLEARED", tone: .success)
        static let categoryCreated = Toast(label: "// CATEGORY ADDED", tone: .success)
        static let categoryUpdated = Toast(label: "// CATEGORY UPDATED", tone: .success)
        static let settingsSaved   = Toast(label: "// SETTINGS SAVED", tone: .success)
        static let allocationsSaved = Toast(label: "// ALLOCATIONS SAVED", tone: .success)
        static let ruleCreated     = Toast(label: "// RULE ADDED", tone: .success)
        static let ruleUpdated     = Toast(label: "// RULE UPDATED", tone: .success)
        static let ruleDeleted     = Toast(label: "// RULE DELETED", tone: .success)
    }

    // MARK: - Job board (projects, clients, task types)

    enum JobBoard {
        static let taskTypeCreated = Toast(label: "// TASK TYPE ADDED", tone: .success)
        static let taskTypeUpdated = Toast(label: "// TASK TYPE UPDATED", tone: .success)
        static let statusChanged   = Toast(label: "// STATUS CHANGED", tone: .success)
        static let teamUpdated     = Toast(label: "// CREW UPDATED", tone: .success)
        static let clientCreated   = Toast(label: "// CLIENT ADDED", tone: .success)
        static let clientUpdated   = Toast(label: "// CLIENT UPDATED", tone: .success)
        static let deleted         = Toast(label: "// DELETED", tone: .success)
        static let projectCompleted = Toast(label: "// PROJECT DONE", tone: .success)
        static let projectClosed   = Toast(label: "// PROJECT CLOSED", tone: .success)

        /// "No tasks to reschedule" — warning toast with a tap-through to create one.
        static func noTasksToReschedule(createTask: @escaping () -> Void) -> Toast {
            Toast(label: "// NO TASKS TO RESCHEDULE", tone: .warning, autoDismissAfter: 0,
                  action: ToastAction(label: "CREATE TASK", handler: createTask))
        }
    }

    // MARK: - Tasks

    enum Task {
        static let created       = Toast(label: "// TASK CREATED", tone: .success)
        static let deleted       = Toast(label: "// TASK DELETED", tone: .success)
        static let completed     = Toast(label: "// TASK DONE", tone: .success)
        static let cancelled     = Toast(label: "// TASK CANCELLED", tone: .success)
        static let rescheduled   = Toast(label: "// RESCHEDULED", tone: .success)
        static let scheduled     = Toast(label: "// SCHEDULED", tone: .success)
        static let datesCleared  = Toast(label: "// DATES CLEARED", tone: .success)
        static let statusUpdated = Toast(label: "// STATUS UPDATED", tone: .success)
        static let teamUpdated   = Toast(label: "// CREW UPDATED", tone: .success)
        static let subCreated    = Toast(label: "// SUB-TASK ADDED", tone: .success)
        static let subUpdated    = Toast(label: "// SUB-TASK UPDATED", tone: .success)
        static let subDeleted    = Toast(label: "// SUB-TASK DELETED", tone: .success)
        static let productAttached = Toast(label: "// PRODUCT ATTACHED", tone: .success)

        // Parameterized variants — preserve glanceable context in the review /
        // calendar flows where the operator needs to see WHICH task / WHAT dates.
        static func completedTask(_ name: String) -> Toast { Toast(label: "// COMPLETED — \(name.uppercased())", tone: .success) }
        static func alreadyComplete(_ name: String) -> Toast { Toast(label: "// ALREADY COMPLETE — \(name.uppercased())", tone: .success) }
        static func scheduledFor(start: Date, end: Date) -> Toast {
            let f = DateFormatter()
            f.dateFormat = "EEE MMM d"
            let s = f.string(from: start).uppercased()
            let range = Calendar.current.isDate(start, inSameDayAs: end)
                ? "FOR \(s)"
                : "FOR \(s) – \(f.string(from: end).uppercased())"
            return Toast(label: "// SCHEDULED \(range)", tone: .success)
        }
        /// Drag-reschedule with crew/dependency cascade — `count` = total jobs moved
        /// (the dropped job plus every cascaded one).
        static func scheduleUpdatedCascade(count: Int) -> Toast {
            Toast(label: "// SCHEDULE UPDATED — \(count) JOBS MOVED", tone: .success)
        }
    }

    // MARK: - Catalog

    enum Catalog {
        static let optionMoved        = Toast(label: "// OPTION MOVED", tone: .success)
        static let optionRemoved      = Toast(label: "// OPTION REMOVED", tone: .success)
        static let optionSaved        = Toast(label: "// OPTION SAVED", tone: .success)
        static let priceRuleSaved     = Toast(label: "// PRICE RULE SAVED", tone: .success)
        static let priceRuleRemoved   = Toast(label: "// PRICE RULE REMOVED", tone: .success)
        static let orderUpdated       = Toast(label: "// ORDER UPDATED", tone: .success)
        static let orderStatusChanged = Toast(label: "// ORDER STATUS CHANGED", tone: .success)
        static let orderCancelled     = Toast(label: "// ORDER CANCELLED", tone: .success)
        static let itemUpdated        = Toast(label: "// ITEM UPDATED", tone: .success)
        static let itemRemoved        = Toast(label: "// ITEM REMOVED", tone: .success)
        static let draftDeleted       = Toast(label: "// DRAFT DELETED", tone: .success)
        static let materialRemoved    = Toast(label: "// MATERIAL REMOVED", tone: .success)
        static let inventoryModeUpdated = Toast(label: "// TRACKING UPDATED", tone: .success)
        static let inventoryTrackingOff = Toast(label: "// TRACKING OFF", tone: .success)
        static let unitSaved          = Toast(label: "// UNIT SAVED", tone: .success)
        static let unitRemoved        = Toast(label: "// UNIT REMOVED", tone: .success)
        static let tagSaved           = Toast(label: "// TAG SAVED", tone: .success)
        static let tagRemoved         = Toast(label: "// TAG REMOVED", tone: .success)
        static let categorySaved      = Toast(label: "// CATEGORY SAVED", tone: .success)
        static let categoryRemoved    = Toast(label: "// CATEGORY REMOVED", tone: .success)
    }

    // MARK: - Inventory

    enum Inventory {
        static let tagRenamed   = Toast(label: "// TAG RENAMED", tone: .success)
        static let tagDeleted   = Toast(label: "// TAG DELETED", tone: .success)
        static let itemCreated  = Toast(label: "// ITEM ADDED", tone: .success)
        static let itemSaved    = Toast(label: "// ITEM SAVED", tone: .success)
        static let itemsDeleted = Toast(label: "// ITEMS DELETED", tone: .success)
    }

    // MARK: - Settings / team / permissions / subscription

    enum Settings {
        static let betaRequestSent  = Toast(label: "// REQUEST SENT", tone: .success)
        static let voteCounted      = Toast(label: "// VOTE IN", tone: .success)
        static let defaultTypesCreated = Toast(label: "// DEFAULTS READY", tone: .success)
        static let loggedOut        = Toast(label: "// SIGNED OUT", tone: .success)
        static let mergeComplete    = Toast(label: "// MERGE DONE", tone: .success)
        static let profileUpdated   = Toast(label: "// PROFILE UPDATED", tone: .success)
        static let roleAssigned     = Toast(label: "// ROLE ASSIGNED", tone: .success)
        static let memberRemoved    = Toast(label: "// MEMBER REMOVED", tone: .success)
        static let invitationRevoked = Toast(label: "// INVITE PULLED", tone: .success)
        static let invitationsSent  = Toast(label: "// INVITES SENT", tone: .success)
        static let accountDeleted   = Toast(label: "// ACCOUNT DELETED", tone: .success)
        static let resetLinkSent    = Toast(label: "// RESET LINK SENT", tone: .success)
        static let issueReported    = Toast(label: "// ISSUE REPORTED", tone: .success)
        static let requestSubmitted = Toast(label: "// REQUEST SENT", tone: .success)
        static let featureInTesting = Toast(label: "// STILL IN TESTING", tone: .warning)
        static let spaceFreed       = Toast(label: "// SPACE FREED", tone: .success)
        static let photosRemoved    = Toast(label: "// PHOTOS CLEARED", tone: .success)
        static let photosPinned     = Toast(label: "// KEPT ON DEVICE", tone: .success)
        static let photosSaved      = Toast(label: "// SAVED TO DEVICE", tone: .success)
        static let roleUpdated      = Toast(label: "// ROLE UPDATED", tone: .success)
        static let permissionUpdated = Toast(label: "// PERMISSION UPDATED", tone: .success)
        static let permissionsSaved = Toast(label: "// PERMISSIONS SAVED", tone: .success)
        static let roleCreated      = Toast(label: "// ROLE ADDED", tone: .success)
        static let roleRenamed      = Toast(label: "// ROLE RENAMED", tone: .success)
        static let roleDuplicated   = Toast(label: "// ROLE COPIED", tone: .success)
        static let roleDeleted      = Toast(label: "// ROLE DELETED", tone: .success)
        static let seatsUpdated     = Toast(label: "// SEATS UPDATED", tone: .success)
        static let seatGranted      = Toast(label: "// SEAT GRANTED", tone: .success)
        static let seatRevoked      = Toast(label: "// SEAT PULLED", tone: .success)

        /// Premium-voice download prompt — info toast with a tap-through to Settings.
        static func premiumVoice(openSettings: @escaping () -> Void) -> Toast {
            Toast(label: "// GET A PREMIUM VOICE", tone: .warning, autoDismissAfter: 0,
                  action: ToastAction(label: "OPEN SETTINGS", handler: openSettings))
        }
    }

    // MARK: - Project detail / notes

    enum Project {
        static let titleSaved       = Toast(label: "// TITLE SAVED", tone: .success)
        static let descriptionSaved = Toast(label: "// DESCRIPTION SAVED", tone: .success)
        static let notePosted       = Toast(label: "// NOTE POSTED", tone: .success)
        static let commentPosted    = Toast(label: "// COMMENT POSTED", tone: .success)
    }

    // MARK: - Contacts / sub-clients

    enum Contact {
        static let subSaved   = Toast(label: "// CONTACT SAVED", tone: .success)
        static let subDeleted = Toast(label: "// CONTACT DELETED", tone: .success)
        static let fieldUpdated = Toast(label: "// UPDATED", tone: .success)
        static let roleUpdated  = Toast(label: "// ROLE UPDATED", tone: .success)
    }

    // MARK: - Photos / annotations

    enum Photo {
        static let added            = Toast(label: "// PHOTO ADDED", tone: .success)
        static let captured         = Toast(label: "// CAPTURED", tone: .success)
        static let uploaded         = Toast(label: "// PHOTO UPLOADED", tone: .success)
        static let removed          = Toast(label: "// PHOTO REMOVED", tone: .success)
        static let annotationSaved  = Toast(label: "// MARKUP SAVED", tone: .success)
        static let visibilityUpdated = Toast(label: "// VISIBILITY UPDATED", tone: .success)
    }

    // MARK: - Onboarding / auth

    enum Onboarding {
        static let codeAccepted   = Toast(label: "// CODE ACCEPTED", tone: .success)
        static let joinedCrew     = Toast(label: "// JOINED CREW", tone: .success)
        static let accessGranted  = Toast(label: "// ACCESS GRANTED", tone: .success)
        static let accountCreated = Toast(label: "// ACCOUNT CREATED", tone: .success)
        static let companyCreated = Toast(label: "// COMPANY CREATED", tone: .success)
        static let switchedToCompanySetup = Toast(label: "// COMPANY SETUP", tone: .warning)
    }

    // MARK: - Deck builder

    enum Deck {
        static let designRenamed   = Toast(label: "// DESIGN RENAMED", tone: .success)
        static let designCleared   = Toast(label: "// DESIGN CLEARED", tone: .success)
        static let designSaved     = Toast(label: "// DESIGN SAVED", tone: .success)
        static let houseEdgeMaterialSet = Toast(label: "// EDGE MATERIAL SET", tone: .success)
        static let railingApplied  = Toast(label: "// RAILING ON", tone: .success)
        static let railingUpdated  = Toast(label: "// RAILING UPDATED", tone: .success)
        static let wallMaterialSet = Toast(label: "// WALL MATERIAL SET", tone: .success)
        static let itemRemoved     = Toast(label: "// ITEM REMOVED", tone: .success)
        static let surfacesLabeled = Toast(label: "// SURFACES LABELED", tone: .success)
        static let footprintLabeled = Toast(label: "// FOOTPRINT LABELED", tone: .success)
        static let edgeLabeled     = Toast(label: "// EDGE LABELED", tone: .success)
        static let surfacesMoved   = Toast(label: "// SURFACES MOVED", tone: .success)
        static let edgesMoved      = Toast(label: "// EDGES MOVED", tone: .success)
        static let levelCreatedSurfaces = Toast(label: "// LEVEL ADDED — SURFACES MOVED", tone: .success)
        static let levelCreatedEdges = Toast(label: "// LEVEL ADDED — EDGES MOVED", tone: .success)
        static let arWalkSaved     = Toast(label: "// AR WALK SAVED", tone: .success)
    }

    // MARK: - Measurement (LiDAR)

    enum Measure {
        static let pdfReady = Toast(label: "// PDF READY", tone: .success)
        static let devFlagOverride = "// DEV FLAG OVERRIDE · FLAG OFF"
        static let depthFileMissing = "// DEPTH FILE MISSING · RECAPTURE"
        static let visualCalibrateFirst = "// VISUAL MODE · CALIBRATE FIRST"
        static let hardwareRequired = "// NO AR DEPTH · HARDWARE REQUIRED"
        /// Dimensions saved to project — success toast with a tap-through to view.
        static func dimensionsSaved(view: @escaping () -> Void) -> Toast {
            Toast(label: "// DIMENSIONS SAVED", tone: .success, autoDismissAfter: 6,
                  action: ToastAction(label: "VIEW", handler: view))
        }
    }

    // MARK: - Leads (parity with the legacy LeadsToastSubscriber)

    enum Lead {
        static let archived      = Toast(label: "// LEAD ARCHIVED", tone: .warning)
        static let stageAdvanced = Toast(label: "// STAGE ADVANCED", tone: .success)
    }

    // MARK: - Sync

    enum Sync {
        static let restored = Toast(label: "// BACK ONLINE", tone: .success)
        static func failed(retry: @escaping () -> Void) -> Toast {
            Toast(label: "// SYNC FAILED", tone: .error, autoDismissAfter: 0,
                  action: ToastAction(label: "RETRY", handler: retry))
        }
    }

    // MARK: - Audit list

    /// Every static event toast + a representative of each action factory, so the
    /// label-contract test (FeedbackCatalogTests) covers the whole catalog.
    static let all: [Toast] = [
        Invoice.sent, Invoice.voided, Invoice.writtenOff, Invoice.paymentRecorded, Invoice.approved, Invoice.reminderSent,
        Estimate.created, Estimate.updated, Estimate.saved, Estimate.sent, Estimate.converted, Estimate.progressInvoice,
        Estimate.lineItemAdded, Estimate.lineItemUpdated, Estimate.lineItemDeleted, Estimate.revisionsSent,
        Expense.saved, Expense.changesSaved, Expense.submitted, Expense.deleted, Expense.approved, Expense.rejected,
        Expense.flagged, Expense.flagCleared, Expense.categoryCreated, Expense.categoryUpdated, Expense.settingsSaved,
        Expense.allocationsSaved, Expense.ruleCreated, Expense.ruleUpdated, Expense.ruleDeleted,
        JobBoard.taskTypeCreated, JobBoard.taskTypeUpdated, JobBoard.statusChanged, JobBoard.teamUpdated,
        JobBoard.clientCreated, JobBoard.clientUpdated, JobBoard.deleted, JobBoard.projectCompleted, JobBoard.projectClosed,
        JobBoard.noTasksToReschedule(createTask: {}),
        Task.created, Task.deleted, Task.completed, Task.cancelled, Task.rescheduled, Task.scheduled, Task.datesCleared,
        Task.statusUpdated, Task.teamUpdated, Task.subCreated, Task.subUpdated, Task.subDeleted, Task.productAttached,
        Task.completedTask("x"), Task.alreadyComplete("x"),
        Task.scheduledFor(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 0)),
        Catalog.optionMoved, Catalog.optionRemoved, Catalog.optionSaved, Catalog.priceRuleSaved, Catalog.priceRuleRemoved,
        Catalog.orderUpdated, Catalog.orderStatusChanged, Catalog.orderCancelled, Catalog.itemUpdated, Catalog.itemRemoved,
        Catalog.draftDeleted, Catalog.materialRemoved, Catalog.inventoryModeUpdated, Catalog.inventoryTrackingOff,
        Catalog.unitSaved, Catalog.unitRemoved, Catalog.tagSaved, Catalog.tagRemoved, Catalog.categorySaved, Catalog.categoryRemoved,
        Inventory.tagRenamed, Inventory.tagDeleted, Inventory.itemCreated, Inventory.itemSaved, Inventory.itemsDeleted,
        Settings.betaRequestSent, Settings.voteCounted, Settings.defaultTypesCreated, Settings.loggedOut, Settings.mergeComplete,
        Settings.profileUpdated, Settings.roleAssigned, Settings.memberRemoved, Settings.invitationRevoked, Settings.invitationsSent,
        Settings.accountDeleted, Settings.resetLinkSent, Settings.issueReported, Settings.requestSubmitted, Settings.featureInTesting,
        Settings.spaceFreed, Settings.photosRemoved, Settings.photosPinned, Settings.photosSaved, Settings.roleUpdated,
        Settings.permissionUpdated, Settings.permissionsSaved, Settings.roleCreated, Settings.roleRenamed, Settings.roleDuplicated,
        Settings.roleDeleted, Settings.seatsUpdated, Settings.seatGranted, Settings.seatRevoked, Settings.premiumVoice(openSettings: {}),
        Project.titleSaved, Project.descriptionSaved, Project.notePosted, Project.commentPosted,
        Contact.subSaved, Contact.subDeleted, Contact.fieldUpdated, Contact.roleUpdated,
        Photo.added, Photo.captured, Photo.uploaded, Photo.removed, Photo.annotationSaved, Photo.visibilityUpdated,
        Onboarding.codeAccepted, Onboarding.joinedCrew, Onboarding.accessGranted, Onboarding.accountCreated,
        Onboarding.companyCreated, Onboarding.switchedToCompanySetup,
        Deck.designRenamed, Deck.designCleared, Deck.designSaved, Deck.houseEdgeMaterialSet, Deck.railingApplied,
        Deck.railingUpdated, Deck.wallMaterialSet, Deck.itemRemoved, Deck.surfacesLabeled, Deck.footprintLabeled,
        Deck.edgeLabeled, Deck.surfacesMoved, Deck.edgesMoved, Deck.levelCreatedSurfaces, Deck.levelCreatedEdges, Deck.arWalkSaved,
        Measure.pdfReady, Measure.dimensionsSaved(view: {}),
        Lead.archived, Lead.stageAdvanced,
        Sync.restored, Sync.failed(retry: {}),
    ]
}
