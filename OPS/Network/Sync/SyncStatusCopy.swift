//
//  SyncStatusCopy.swift
//  OPS
//
//  Plain-language presentation for the notifications sync / "pending changes"
//  panel (bug dbada8f5). Pure + UI-free so the copy rules are unit-testable and
//  can't drift. A field user must NEVER see a raw database column name or a raw
//  Postgres error — every word the panel shows for a change comes from here.
//
//  Design intent: stay quiet and honest. Count every outstanding change so the
//  header can't disagree with the list, name changes like human actions, and
//  turn sync failures into calm, action-oriented lines.
//

import Foundation

/// The emotional register of a change's current state. The view maps each tone
/// to an OPSStyle token (`syncing`→accent, `waiting`→neutral, `attention`→tan,
/// `stuck`→rose) — this type carries no color so it stays UI-free and testable.
enum SyncStatusTone {
    case syncing    // actively saving right now
    case waiting    // queued, will send on its own
    case attention  // failed, still retrying automatically
    case stuck      // failed and out of automatic retries — needs the user
}

enum SyncStatusCopy {
    enum SiteVisitLogout {
        static let warningTitle = "Site visit not saved yet"
        static let warningBody = "This phone still has site visit work that has not reached OPS. Stay signed in to retry, or discard it and log out."
        static let stayAction = "Stay Signed In"
        static let discardAction = "Discard & Log Out"
        static let savingLabel = "SAVING VISIT..."
    }


    // MARK: - Collapsed header

    /// One calm line summarizing outstanding changes. The count is always
    /// `pending + failed` — the exact number of rows the expanded list shows —
    /// so the header can never say "1" over three rows again.
    static func header(pendingCount: Int, failedCount: Int, isSyncing: Bool) -> String {
        let total = pendingCount + failedCount
        if failedCount > 0 {
            return "\(total) \(changeWord(total)) \(needWord(total)) a look"
        }
        if isSyncing {
            return "Saving \(total) \(changeWord(total))…"
        }
        return "\(total) \(changeWord(total)) waiting to sync"
    }

    // MARK: - Row title

    /// A human, noun-phrase title for a queued change — entity + action, with a
    /// few semantic upgrades so the row reads like something the user did, not a
    /// table write. Never exposes raw column names.
    static func title(entityType: String, operationType: String, changedFields: [String]) -> String {
        if let semantic = semanticLabel(entityType: entityType, changedFields: changedFields) {
            return semantic
        }
        let entity = entityName(entityType)
        switch operationType {
        case "create": return "New \(entity.lowercased())"
        case "delete": return "\(entity) removed"
        default:       return "\(entity) update"
        }
    }

    // MARK: - Row status line

    /// The plain-language state of a change. Recognized failures become calm,
    /// action-oriented lines; anything unrecognized falls back to a reassuring
    /// "we'll keep trying" (or, once auto-retries are spent, a clear ask). Never
    /// echoes the raw Postgres / PostgREST error text.
    static func status(status: String, retryCount: Int, canRetry: Bool, rawError: String?) -> (text: String, tone: SyncStatusTone) {
        switch status {
        case "inProgress":
            return ("Saving…", .syncing)
        case "pending":
            return ("Waiting to sync", .waiting)
        case "parked":
            // A parked op never retries on its own. Saying "waiting to sync"
            // here — the old default — told the operator to keep waiting for
            // something that was never coming. Same three-way split as the
            // recovery screen so the panel and PENDING WORK cannot disagree
            // about what happened.
            if PendingWork.isClientRejected(rawError) {
                return (PendingWork.clientRejectedRow, .stuck)
            }
            return (
                PendingWork.isMissingRow(rawError)
                    ? PendingWork.missingRow
                    : PendingWork.parkedRow,
                .stuck
            )
        case "failed":
            if let specific = specificFailure(rawError) { return specific }
            // The retry / dismiss buttons sit right beside this line, so the
            // copy stays short — the buttons carry the "what to do".
            if !canRetry { return ("Still can't save", .stuck) }
            return ("Couldn't save yet", .attention)
        default:
            return ("Waiting to sync", .waiting)
        }
    }

    // MARK: - Internals

    /// High-value semantic upgrades so a row reads like a human action. Extend
    /// as real cases warrant; unknown combinations fall through to entity+action.
    static func semanticLabel(entityType: String, changedFields: [String]) -> String? {
        guard !changedFields.isEmpty else { return nil }
        if entityType == "project", changedFields.allSatisfy({ $0.hasPrefix("vinyl") }) {
            return "Vinyl order"
        }
        return nil
    }

    /// Maps a stored raw error string to a calm, plain line. Returns nil when
    /// nothing specific is recognized so the caller applies the generic copy.
    private static func specificFailure(_ rawError: String?) -> (text: String, tone: SyncStatusTone)? {
        guard let raw = rawError?.lowercased(), !raw.isEmpty else { return nil }
        if raw.contains("network") || raw.contains("offline") || raw.contains("connection")
            || raw.contains("timed out") || raw.contains("timeout") || raw.contains("internet") {
            return ("Waiting for signal", .waiting)
        }
        if raw.contains("jwt") || raw.contains("401") || raw.contains("unauthorized")
            || raw.contains("authentication") {
            return ("Sign in to save", .attention)
        }
        if raw.contains("duplicate key") {
            return ("Already saved", .waiting)
        }
        if PendingWork.isMissingRow(raw) {
            return (PendingWork.missingRow, .stuck)
        }
        return nil
    }

    /// Friendly, human name for a sync entity type. Centralized here (moved off
    /// the view) so the mapping is shared and testable.
    static func entityName(_ entityType: String) -> String {
        switch entityType {
        case "project": return "Project"
        case "projectTask": return "Task"
        case "projectNote": return "Note"
        case "user": return "User"
        case "client": return "Client"
        case "subClient": return "Sub-Client"
        case "company": return "Company"
        case "taskType": return "Task Type"
        case "expense": return "Expense"
        case "estimate": return "Estimate"
        case "invoice": return "Invoice"
        case "lineItem": return "Line Item"
        case "payment": return "Payment"
        case "photoAnnotation": return "Photo Annotation"
        case "calendarUserEvent": return "Calendar Event"
        case "catalogCategory": return "Catalog Category"
        case "catalogUnit": return "Catalog Unit"
        case "catalogTag": return "Catalog Tag"
        case "catalogItem": return "Catalog Item"
        case "catalogVariant": return "Catalog Variant"
        case "catalogOption": return "Catalog Option"
        case "catalogOptionValue": return "Catalog Option Value"
        case "catalogVariantOptionValue": return "Catalog Variant Option Value"
        case "catalogItemTag": return "Catalog Item Tag"
        case "catalogSnapshot": return "Catalog Snapshot"
        case "catalogSnapshotItem": return "Catalog Snapshot Item"
        case "catalogOrder": return "Catalog Order"
        case "catalogOrderItem": return "Catalog Order Item"
        case "companyDefaultProduct": return "Default Product"
        case "productOption": return "Product Option"
        case "productOptionValue": return "Product Option Value"
        case "productPricingModifier": return "Pricing Modifier"
        case "productMaterial": return "Product Material"
        case "timeEntry": return "Time Entry"
        case "signatureCapture": return "Signature"
        case "formSubmission": return "Form"
        case "siteVisit": return "Site Visit"
        case "siteVisitArtifact": return "Site Visit Capture"
        case "siteVisitChecklistAnswer": return "Site Visit Checklist"
        case "siteVisitIdentityDraft": return "Site Visit Identity"
        default: return entityType.capitalized
        }
    }

    /// Reconnect toast — raised once when connectivity returns with work still
    /// queued (never at zero; `DataController` gates on `hasPendingSyncs`).
    ///
    /// Says the event first, then what it means for the operator's work. It
    /// deliberately reuses `changeWord` so the toast, the panel header and the
    /// pending list all count the same things in the same words — the toast used
    /// to say "ITEMS" while every other sync surface said "changes".
    static func connectionRestored(pendingCount: Int) -> String {
        "// BACK ONLINE · SAVING \(pendingCount) \(changeWord(pendingCount).uppercased())"
    }

    /// Tap-through on the reconnect toast — opens PENDING WORK.
    static let connectionRestoredAction = "VIEW"

    private static func changeWord(_ count: Int) -> String {
        count == 1 ? "change" : "changes"
    }

    private static func needWord(_ count: Int) -> String {
        count == 1 ? "needs" : "need"
    }

    // MARK: - PENDING WORK recovery screen (SYNC RECOVERY · T6)
    //
    // Every user-facing string on the PENDING WORK recovery screen (spec §4/§5)
    // lands HERE — the same chokepoint rule as the panel above, so a field user
    // never sees a raw column name or Postgres error, and the copy is unit-tested
    // like the panel's. Final wording is the plan's FINAL COPY BLOCK, verbatim.
    // The block stays clock-free: the view precomputes `secondsUntilRetry` from
    // `nextEligibleAt − now` (floored to 1s) and hands it in, so these functions
    // are deterministic and testable without a clock.
    enum PendingWork {

        // Screen + section headers (UPPERCASE authority; `//` prefix is the
        // section voice).
        static let screenTitle = "PENDING WORK"
        static let sectionAttention = "// NEEDS ATTENTION"
        static let sectionSending = "// SENDING"
        static let sectionDrafts = "// DRAFTS"
        static let sectionUnlinked = "// NOT LINKED"

        // Empty (zero) state — hero glyph + label (MOBILE.md §10).
        static let emptyHero = "—"
        static let emptyLabel = "// NOTHING PENDING · ALL CHANGES SAVED"

        // Row status lines (sentence case — the existing SyncStatusCopy register).
        static let parkedRow = "Server said no — held here"
        /// A park with a different cause and a different answer. The server did
        /// not reject the change; the record it belonged to is not in OPS any
        /// more. Retrying cannot help, so the line says what happened and the
        /// detail block below says what the operator still has.
        static let missingRow = "That record is gone from OPS — held here"
        /// A third cause, and the only one with a fix the operator can act on
        /// right here: the work is fine, but the customer it belongs to never
        /// reached OPS. Naming the customer — not the lead — is what points the
        /// operator at the row that actually needs retrying.
        static let clientRejectedRow = "Customer never reached OPS — held here"
        static let offlineRow = "Waiting for signal"
        static let orphanRow = "Not linked to a job or lead"
        static let draftRow = "Not sent yet — open to finish"
        static let quarantineTitle = "Site visit recovery"
        static let quarantineRow = "Protected on this phone"

        /// Reason-aware custody line. A parent-deleted packet is not an identity
        /// mystery — the office deleted the visit in OPS while this phone still
        /// held work for it. Say the event, then the guarantee; identity-review
        /// packets keep the generic custody line.
        static func quarantineRow(
            for reason: SiteVisitOrphanQuarantineReason?
        ) -> String {
            switch reason {
            case .parentDeleted:
                return "Deleted in OPS — kept on this phone"
            case .foreignCompany, .malformedIdentity, .ambiguousBinding, nil:
                return quarantineRow
            }
        }
        static let retryingRow = "Retrying…"
        static let retrySucceededRow = "Updated"
        static let retryFailedRow = "Retry failed — still here"

        /// Backoff countdown line. `n` is always a whole second, floored to 1 so
        /// the operator never sees "next in 0s". Rendered in mono at the call site.
        static func backoffRow(seconds: Int) -> String {
            "Retrying — next in \(max(1, seconds))s"
        }

        // Detail sheet — parked error block.
        static let parkedDetailLabel = "SYS :: REJECTED BY SERVER"
        static let parkedDetailBody = "Your copy is safe on this phone. Retry now or export it."

        // Detail sheet — the record behind the change no longer exists.
        static let missingRowDetailLabel = "SYS :: RECORD NOT FOUND"
        static let missingRowDetailBody = "Someone deleted this record in OPS, or it is no longer shared with you. Your copy is safe on this phone — export it before you stop the send."

        // Detail sheet — the customer this work belongs to was refused.
        static let clientRejectedDetailLabel = "SYS :: CUSTOMER NOT SAVED"
        static let clientRejectedDetailBody = "This lead is waiting on a customer record the server refused. Both are safe on this phone. Retry the customer in this list — the lead follows on its own."

        /// The parked block's label + body for one item. Three causes, three
        /// answers: a refused customer is fixable right here, a missing record
        /// never will be, and every other park is a plain rejection.
        static func parkedDetail(
            lastError: String?
        ) -> (label: String, body: String) {
            if isClientRejected(lastError) {
                return (clientRejectedDetailLabel, clientRejectedDetailBody)
            }
            return isMissingRow(lastError)
                ? (missingRowDetailLabel, missingRowDetailBody)
                : (parkedDetailLabel, parkedDetailBody)
        }

        /// Our own zero-row PATCH verdict, recognized by the stable marker
        /// `SyncError.serverRowMissing` writes into every description. Matching
        /// the typed error's own phrase — not loose wording — is what keeps this
        /// from claiming a deletion that never happened.
        static func isMissingRow(_ raw: String?) -> Bool {
            guard let raw, !raw.isEmpty else { return false }
            return raw.lowercased().contains(SyncError.serverRowMissingMarker)
        }

        /// The lead-delivery queue's own ordering verdict, recognized by the
        /// marker `ClientLeadAutocreateQueue` stamps when it parks a delivery
        /// behind a refused customer. Same discipline as `isMissingRow`: match
        /// the writer's exact phrase, never loose wording.
        static func isClientRejected(_ raw: String?) -> Bool {
            guard let raw, !raw.isEmpty else { return false }
            return raw.lowercased()
                .contains(ClientLeadAutocreateError.clientCreateRejectedMarker)
        }

        // MARK: - DETAILS disclosure
        //
        // The sheet's DETAILS block used to print the stored error verbatim —
        // `String(describing:)` of a PostgrestError, struct label and all:
        //
        //     PostgrestError(detail: nil, hint: nil, code: Optional("PGRST116"),
        //     message: "Cannot coerce the result to a single JSON object")
        //
        // A business owner read that on his own phone. It is not a detail, it is
        // a stack trace, and it violates this file's founding rule: a field user
        // never sees a raw database error. `diagnostic` is the chokepoint that
        // turns one into a sentence. The raw text still travels — EXPORT carries
        // it verbatim, which is the surface built for handing evidence to
        // support.

        // The named causes. Each says what happened in one sentence a person can
        // act on, and none of them quotes the server.
        static let diagnosticClientRejected = "The customer record this lead belongs to was refused by the server."
        static let diagnosticMissingRow = "The record this change belongs to is no longer in OPS."
        static let diagnosticPermissionDenied = "The server would not let this account save that record."
        static let diagnosticNoMatchingRow = "The server had no matching record to return."
        static let diagnosticDuplicate = "A matching record already exists in OPS."
        static let diagnosticSignInExpired = "The sign-in had expired the last time this was tried."
        static let diagnosticOffline = "There was no connection the last time this was tried."

        /// Fallback for a cause this app has not seen before. Says the one true
        /// thing — the server refused it — and points at EXPORT rather than
        /// spilling the raw text onto a screen in a truck.
        static let diagnosticUnknown = "The server refused this change. Export it to send the full reason to support."

        /// One plain-language line for a stored error. Never echoes the raw
        /// text, and never returns nil for a non-empty error — an unrecognized
        /// cause still owes the operator a sentence.
        ///
        /// Ordering is precedence, and it is deliberate: a cause the operator can
        /// DO something about outranks the transport symptom it produced. A lead
        /// blocked behind a refused customer also carries PGRST116; naming the
        /// customer is what points at the row that needs retrying.
        static func diagnostic(_ raw: String?) -> String? {
            guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }
            let lowered = raw.lowercased()

            if isClientRejected(lowered) { return diagnosticClientRejected }
            if isMissingRow(lowered) { return diagnosticMissingRow }
            if lowered.contains("row-level security") || lowered.contains("42501") {
                return diagnosticPermissionDenied
            }
            if lowered.contains("pgrst116") || lowered.contains("coerce the result") {
                return diagnosticNoMatchingRow
            }
            if lowered.contains("duplicate key") { return diagnosticDuplicate }
            if lowered.contains("jwt") || lowered.contains("401")
                || lowered.contains("unauthorized") || lowered.contains("authentication") {
                return diagnosticSignInExpired
            }
            if isOffline(lowered) { return diagnosticOffline }
            return diagnosticUnknown
        }

        /// The DETAILS block's full text: one line per distinct cause, deduped
        /// so two members blocked by the same thing do not say it twice.
        static func diagnostics(_ rawErrors: [String]) -> [String] {
            var seen = Set<String>()
            return rawErrors.compactMap { raw in
                guard let line = diagnostic(raw), !seen.contains(line) else { return nil }
                seen.insert(line)
                return line
            }
        }

        // Actions, labels, confirms.
        static let linkAction = "LINK"
        static let linkPickerTitle = "LINK TO"
        static let exportAction = "EXPORT"
        static let deleteAction = "DELETE"
        /// Most rows here are queued SENDS, not records. Stopping one is not a
        /// deletion and must not be labelled like one.
        static let stopSendingAction = "STOP SENDING"
        static let cancelAction = "CANCEL"
        static let acknowledgeAction = "OK"
        static let discardConfirmTitle = "DESTRUCTIVE. NO UNDO."
        static let stopSendingConfirmTitle = "STOP SENDING?"
        static let discardConfirmBody = "Deletes this work from this phone. It was never sent."
        static let staleReviewTag = "STALE · 30D"
        static let staleReviewAccessibility = "Needs review. 30 days or older."
        static let discardFailure = "COULD NOT DELETE · WORK IS STILL HERE"
        static let discardFailureTitle = "WORK NOT DELETED"
        static let stopSendingFailure = "COULD NOT STOP THIS SEND · IT IS STILL QUEUED"
        static let stopSendingFailureTitle = "SEND NOT STOPPED"

        /// A failed action reports what it actually failed to do. Telling the
        /// operator "WORK NOT DELETED" after a stopped send implies a deletion
        /// was attempted — the exact over-promise that made bug f7431c17 read as
        /// catastrophic. Nothing here claims a deletion that was never on offer.
        static func failureTitle(for scope: RecoveryDiscardScope) -> String {
            scope.isDestructive ? discardFailureTitle : stopSendingFailureTitle
        }

        static func failureMessage(for scope: RecoveryDiscardScope) -> String {
            scope.isDestructive ? discardFailure : stopSendingFailure
        }
        static let deletingStatus = "DELETING…"

        /// The confirmation title for a scope — a destructive scope warns, a
        /// stopped send does not pretend to be one.
        static func discardConfirmationTitle(
            for scope: RecoveryDiscardScope
        ) -> String {
            scope.isDestructive ? discardConfirmTitle : stopSendingConfirmTitle
        }

        /// The row/sheet action label for a scope.
        static func discardActionLabel(
            for scope: RecoveryDiscardScope
        ) -> String {
            scope.isDestructive ? deleteAction : stopSendingAction
        }

        /// What the operator is about to change, said plainly. A stopped send
        /// names what STAYS; only a scope that erases the last copy says so.
        static func discardConfirmationBody(
            for scope: RecoveryDiscardScope
        ) -> String {
            switch scope {
            case .leadDeliveryRequest:
                return "Cancels this pending lead creation. The client stays on this phone."
            case .localPhotos(let count):
                return "Deletes \(count) unsent photo\(count == 1 ? "" : "s") from this phone. They never reached OPS — there is no other copy."
            case .queuedSends(let count):
                return "Stops \(count) queued send\(count == 1 ? "" : "s"). The visit and everything captured on it stay — nothing is deleted here or in OPS."
            case .quarantinedVisit(let capturedItemCount):
                return "Deletes the protected recovery packet — \(capturedItemCount) captured item\(capturedItemCount == 1 ? "" : "s") — from this phone. There is no other copy."
            }
        }

        /// Share-sheet summary title. `name` is the work's display name.
        static func exportTitle(name: String) -> String { "OPS EXPORT — \(name)" }

        /// Floating RETRY ALL CTA — matches the existing panel's `RETRY ALL (n)`.
        static func retryAllButton(count: Int) -> String { "RETRY ALL (\(count))" }

        /// Sync-pill attention badge — `<n> NEED A LOOK` (count in mono).
        static func pillBadge(count: Int) -> String { "\(count) NEED A LOOK" }

        // Row titles — the piece of WORK, named like a human action. The name
        // is data; the prefix is the copy (chokepoint rule).

        /// Loose lead-delivery row — "Lead · <name>" (falls back to "New lead"
        /// when the client carries no name).
        static func leadTitle(name: String) -> String {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "New lead" : "Lead · \(trimmed)"
        }

        /// Queued-photo row title — "N photo" / "N photos".
        static func photosTitle(count: Int) -> String {
            "\(count) photo\(count == 1 ? "" : "s")"
        }

        /// Site-visit bundle / draft title — the capture's display name, or a
        /// plain "Site visit" when the operator never named it.
        static func draftTitle(displayName: String) -> String {
            let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Site visit" : trimmed
        }

        /// Durable site-visit packet summary: one captured count plus the stage
        /// currently governing the chain. The status line below carries whether
        /// that stage is saving, waiting, or needs attention.
        static func siteVisitPacketSummary(
            capturedItemCount: Int,
            blockedStage: SiteVisitBlockedStage
        ) -> String {
            let stage: String
            switch blockedStage {
            case .visit: stage = "VISIT"
            case .media: stage = "MEDIA"
            case .completion: stage = "COMPLETION"
            }
            return "\(capturedItemCount) CAPTURED · \(stage)"
        }

        /// Orphan deck-design title — the design's title, or "Deck design".
        static func orphanTitle(title: String) -> String {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Deck design" : trimmed
        }

        /// Bundle member-strip glyph label — CLIENT / LEAD / DECK / PHOTOS.
        static func memberLabel(_ role: RecoveryMemberRole) -> String {
            switch role {
            case .client:        return "CLIENT"
            case .lead:          return "LEAD"
            case .deck:          return "DECK"
            case .photos:        return "PHOTOS"
            case .other(let s):  return s.uppercased()
            }
        }

        /// THE resolver: a recovery item's raw state → one plain line + tone.
        /// Ordering encodes precedence — a permanent rejection reads as held, a
        /// live save reads as saving, an offline error reads as waiting-for-signal
        /// (more honest than a countdown that can't fire), a non-offline backoff
        /// shows its countdown, then failed/queued fall through to their lines.
        /// `secondsUntilRetry` is nil unless the item is actively counting down.
        static func statusLine(
            statusRaw: String,
            lastError: String?,
            secondsUntilRetry: Int?
        ) -> (text: String, tone: SyncStatusTone) {
            switch statusRaw {
            case "parked":
                if isClientRejected(lastError) { return (clientRejectedRow, .stuck) }
                return (isMissingRow(lastError) ? missingRow : parkedRow, .stuck)
            case "inProgress": return ("Saving…", .syncing)
            default:           break
            }
            if isOffline(lastError) { return (offlineRow, .waiting) }
            if let seconds = secondsUntilRetry, seconds > 0 {
                return (backoffRow(seconds: seconds), .waiting)
            }
            switch statusRaw {
            case "failed": return ("Couldn't save yet", .attention)
            default:       return ("Waiting to sync", .waiting)   // pending / local
            }
        }

        /// Network-class error detection — the same vocabulary the panel's
        /// `specificFailure` uses so "Waiting for signal" reads identically here.
        private static func isOffline(_ raw: String?) -> Bool {
            guard let raw = raw?.lowercased(), !raw.isEmpty else { return false }
            return raw.contains("network") || raw.contains("offline")
                || raw.contains("connection") || raw.contains("timed out")
                || raw.contains("timeout") || raw.contains("internet")
        }
    }
}
