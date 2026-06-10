//
//  Feedback.swift
//  OPS
//
//  Central catalog of every in-app feedback event. One place for all toast copy
//  (one ops-copywriter pass). Call sites reference these symbols, never inline
//  strings — so the voice stays consistent and the full event set is auditable.
//
//  Labels are PROVISIONAL until the ops-copywriter pass locks them.
//  Voice contract (enforced by FeedbackCatalogTests): "// " prefix, UPPERCASE body.
//

import Foundation

enum Feedback {

    // MARK: - Generic helpers (long tail)

    static func saved(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) SAVED", tone: .success) }
    static func deleted(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) DELETED", tone: .success) }
    static func created(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) CREATED", tone: .success) }
    static func updated(_ noun: String) -> Toast { Toast(label: "// \(noun.uppercased()) UPDATED", tone: .success) }

    // MARK: - Error labels (used by .errorToast)

    enum Err {
        static let operationFailed = "// OPERATION FAILED"
        static let saveFailed      = "// SAVE FAILED"
        static let deleteFailed    = "// DELETE FAILED"
        // Domain tasks append their specific error labels here.
    }

    // MARK: - Invoices

    enum Invoice {
        static let sent            = Toast(label: "// INVOICE SENT", tone: .success)
        static let voided          = Toast(label: "// INVOICE VOIDED", tone: .success)
        static let writtenOff      = Toast(label: "// WRITTEN OFF", tone: .success)
        static let paymentRecorded = Toast(label: "// PAYMENT RECORDED", tone: .success)
        static let approved        = Toast(label: "// INVOICE APPROVED", tone: .success)
    }

    // MARK: - Estimates

    enum Estimate {
        static let created         = Toast(label: "// ESTIMATE CREATED", tone: .success)
        static let updated         = Toast(label: "// ESTIMATE UPDATED", tone: .success)
        static let saved           = Toast(label: "// ESTIMATE SAVED", tone: .success)
        static let sent            = Toast(label: "// ESTIMATE SENT", tone: .success)
        static let converted       = Toast(label: "// ESTIMATE CONVERTED", tone: .success)
        static let progressInvoice = Toast(label: "// PROGRESS INVOICE CREATED", tone: .success)
        static let lineItemAdded   = Toast(label: "// LINE ITEM ADDED", tone: .success)
        static let lineItemUpdated = Toast(label: "// LINE ITEM UPDATED", tone: .success)
        static let lineItemDeleted = Toast(label: "// LINE ITEM DELETED", tone: .success)
    }

    // MARK: - Sync

    enum Sync {
        static let restored = Toast(label: "// CONNECTION RESTORED", tone: .success)
        static func failed(retry: @escaping () -> Void) -> Toast {
            Toast(label: "// SYNC FAILED", tone: .error, autoDismissAfter: 0,
                  action: ToastAction(label: "RETRY", handler: retry))
        }
    }

    // MARK: - Audit list

    /// Every static event toast. Domain tasks append their entries so the
    /// label-contract test (FeedbackCatalogTests) covers the whole catalog.
    static let all: [Toast] = [
        Invoice.sent, Invoice.voided, Invoice.writtenOff, Invoice.paymentRecorded, Invoice.approved,
        Estimate.created, Estimate.updated, Estimate.saved, Estimate.sent, Estimate.converted,
        Estimate.progressInvoice, Estimate.lineItemAdded, Estimate.lineItemUpdated, Estimate.lineItemDeleted,
        Sync.restored,
    ]
}
