//
//  SiteVisitCaptureViewModel.swift
//  OPS
//
//  Local-first capture packet orchestration for field site visits.
//

import Contacts
import Foundation
import SwiftData
import SwiftUI
import UIKit
import CoreLocation

/// What a CREATE LEAD tap actually did. A failed server call is NOT
/// automatically a failure for the operator: when the client landed and the
/// durable queue took the lead, the work is safe and this visit binds itself on
/// delivery. That is `.queued` — and it must never render as an error
/// (bug 13c66762: the lead arrived seconds later, under a red toast).
enum SiteVisitLeadCreateOutcome {
    case created(Opportunity)
    case queued(offline: Bool)
    case failed
}

@MainActor
final class SiteVisitCaptureViewModel: ObservableObject {
    @Published private(set) var siteVisit: SiteVisit? {
        didSet { activeSiteVisitId = siteVisit?.id }
    }
    @Published private(set) var artifacts: [SiteVisitCaptureArtifact] = []
    @Published private(set) var siteVisitTypes: [SiteVisitType] = []
    @Published private(set) var selectedSiteVisitType: SiteVisitType?
    @Published private(set) var checklistAnswers: [SiteVisitChecklistAnswer] = []
    @Published private(set) var currentOpportunity: Opportunity?
    @Published private(set) var identityDraft: SiteVisitIdentityDraft?
    @Published var noteDraft = ""
    @Published var measurementDraft = ""
    @Published var errorMessage: String?
    @Published private(set) var isCompleting = false
    @Published private(set) var isCommittingIdentity = false
    /// A prior incomplete unlinked visit that still holds captured evidence.
    /// Surfaced so the operator can deliberately resume it instead of having it
    /// silently reopened underneath a brand-new visit (the old collision bug).
    @Published private(set) var resumableVisit: SiteVisit?
    /// Bumped when a device contact is imported into the identity draft. The
    /// identity panel mirrors the draft in local view state, and this is the
    /// ONLY signal that re-hydrates that mirror — so routine autosaves never
    /// fight the operator's keystrokes (bug 5d5df5b0).
    @Published private(set) var contactImportGeneration = 0

    private let companyId: String
    private let userId: String?
    private let modelContext: ModelContext
    private var autosavedNoteArtifactId: String?
    private var leadBoundObserver: NSObjectProtocol?

    /// The active visit's id, mirrored as a plain String.
    ///
    /// `SiteVisitLeadBound` is broadcast to every live view model, and a view
    /// model can outlive its store — a logout or company switch resets the
    /// context, and every console that was open still receives the post. Reading
    /// `siteVisit?.id` there traps ("model instance was destroyed by calling
    /// ModelContext.reset"), so the identity check that runs on EVERY delivery
    /// never touches a SwiftData instance. Only a match proceeds to the store,
    /// and a match means the delivery is for this view model's own live visit.
    private var activeSiteVisitId: String?

    // MARK: - Injectable seams
    //
    // Production wires the live repositories, the shared durable queue, and the
    // wall clock. Tests substitute doubles so the whole lead-create path —
    // visibility wait, guarded create, queue handoff — runs with no network and
    // without sleeping.

    /// Asks the server whether it can see a client yet. See
    /// `ClientServerVisibility` for why this exists at all.
    var probeClientVisibility: (String, String) async throws -> Void = ClientServerVisibility.liveProbe
    var clientVisibilityBackoff: (Int) async -> Void = ClientServerVisibility.liveBackoff
    var clientVisibilityAttempts = ClientServerVisibility.defaultAttempts
    var createOpportunityRemotely: (CreateOpportunityDTO, String) async throws -> OpportunityDTO = { dto, companyId in
        try await OpportunityRepository(companyId: companyId).create(dto)
    }
    var leadAutocreateQueue: ClientLeadAutocreateQueueing = ClientLeadAutocreateQueue.shared
    var currentDate: () -> Date = { Date() }

    /// How recently an abandoned unlinked visit must have been touched for
    /// re-entry to continue it instead of starting a clean one. See
    /// `loadOrCreateVisit`.
    static let autoResumeWindow: TimeInterval = 15 * 60

    init(
        opportunity: Opportunity?,
        companyId: String,
        userId: String?,
        modelContext: ModelContext
    ) {
        self.currentOpportunity = opportunity
        self.companyId = companyId
        self.userId = userId
        self.modelContext = modelContext

        // The durable queue writes the delivered lead's binding straight into
        // the store; this is how an OPEN console learns about it and flips to
        // LINKED without waiting for an unrelated redraw.
        leadBoundObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("SiteVisitLeadBound"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let visitId = notification.userInfo?["siteVisitId"] as? String
            MainActor.assumeIsolated {
                self?.adoptQueueDeliveredLead(forVisitId: visitId)
            }
        }
    }

    deinit {
        if let leadBoundObserver {
            NotificationCenter.default.removeObserver(leadBoundObserver)
        }
    }

    var summary: SiteVisitCaptureReviewSummary {
        SiteVisitCaptureReviewSummary.make(from: artifacts)
    }

    var activeArtifacts: [SiteVisitCaptureArtifact] {
        artifacts
            .filter(\.isActive)
            .sorted { $0.capturedAt > $1.capturedAt }
    }

    var canComplete: Bool {
        SiteVisitCaptureCompletionPolicy.canComplete(artifacts) || hasAnsweredChecklistEvidence
    }

    /// Anything the operator would lose if they closed without finishing —
    /// drives the "are you sure?" close confirmation.
    var hasCapturedAnything: Bool {
        !activeArtifacts.isEmpty
            || (identityDraft?.filledFieldCount ?? 0) > 0
            || checklistAnswers.contains { $0.isActive && $0.isAnswered }
    }

    var hasProjectEvidence: Bool {
        summary.canCreateProject || hasAnsweredChecklistEvidence
    }

    private var hasAnsweredChecklistEvidence: Bool {
        checklistAnswers.contains { $0.isActive && $0.isAnswered }
    }

    var missingRequiredChecklistAnswers: [SiteVisitChecklistAnswer] {
        checklistAnswers
            .filter { $0.isActive && $0.required && !$0.isAnswered }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var captureAddress: String {
        identityDraft?.address.trimmedNilIfEmpty
            ?? siteVisit?.address
            ?? currentOpportunity?.address
            ?? "NO SITE ADDRESS"
    }

    var editableCaptureAddress: String {
        let address = identityDraft?.address.trimmedNilIfEmpty
            ?? siteVisit?.address
            ?? currentOpportunity?.address
            ?? ""
        return address.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var activeOpportunityId: String? {
        currentOpportunity?.id ?? identityDraft?.opportunityId
    }

    var activeClientId: String? {
        currentOpportunity?.clientId ?? identityDraft?.clientId
    }

    var companyIdentifier: String {
        companyId
    }

    var visitDisplayName: String {
        currentOpportunity?.displayContactName
            ?? identityDraft?.displayName
            ?? "Unlinked visit"
    }

    var visitProjectTitle: String {
        currentOpportunity?.title
            ?? "\(visitDisplayName) Project"
    }

    /// The name the server's `projects_autoname` trigger will derive when this
    /// visit converts to a project. Shown in the review sheet so the operator
    /// sees the real outcome (the convert sheet that follows owns renaming).
    /// Mirrors `private.derive_project_name` via ProjectAutoNamer.
    var projectedProjectName: String {
        ProjectAutoNamer.derive(
            address: editableCaptureAddress.trimmedNilIfEmpty,
            clientName: currentOpportunity?.displayContactName ?? identityDraft?.displayName
        )
    }

    var deckDesignTitle: String {
        "\(visitDisplayName == "Unlinked visit" ? "Site visit" : visitDisplayName) deck"
    }

    var hasBoundOpportunity: Bool {
        activeOpportunityId?.trimmedNilIfEmpty != nil
    }

    var canCreateLeadFromIdentity: Bool {
        identityDraft?.isCompleteEnoughForProject == true
    }

    func loadOrCreateVisit() {
        if siteVisit != nil {
            reloadArtifacts()
            reloadSiteVisitTypes()
            loadSelectedTypeFromChecklist()
            hydrateChecklistAnswersFromCapturedEvidence()
            return
        }

        if let opportunity = currentOpportunity {
            // Linked start (opened from a lead): resume that lead's open visit,
            // or create one for it. Unambiguous — no collision possible.
            siteVisit = openVisits().first { $0.opportunityId == opportunity.id }
                ?? createVisit()
        } else {
            // Unlinked start (FAB). Sweep away empty abandoned unlinked visits,
            // then decide what to do with one that still holds evidence.
            //
            // The old rule NEVER reopened a prior visit, to kill a cross-site
            // data-mixing bug: a visit abandoned at one address must not be
            // silently reopened at the next. That intent is preserved — but it
            // punished the far more common case, where the console was torn
            // down seconds ago (a modal stealing the presentation, an
            // accidental close) and the operator is still standing at the SAME
            // site. Rebuilding a blank visit there loses the capture they just
            // made (bug 5d5df5b0).
            //
            // So: only an unlinked visit, only one that holds content, and only
            // one touched inside `autoResumeWindow`, is continued. Anything
            // older is a different site — it stays behind the resume banner,
            // exactly as before.
            let priorUnlinked = openVisits().filter { $0.opportunityId == nil }
            let withContent = priorUnlinked.filter { visitHasContent($0) }
            let empties = priorUnlinked.filter { !visitHasContent($0) }
            for empty in empties { hardDeleteVisit(empty) }

            let mostRecent = withContent
                .sorted { lastActivity(of: $0) > lastActivity(of: $1) }
                .first
            if let mostRecent,
               currentDate().timeIntervalSince(lastActivity(of: mostRecent)) < Self.autoResumeWindow {
                siteVisit = mostRecent
                resumableVisit = nil
            } else {
                resumableVisit = mostRecent
                siteVisit = createVisit()
            }
        }

        loadOrCreateIdentityDraft()
        reloadArtifacts()
        seedBuiltInSiteVisitTypesIfNeeded()
        reloadSiteVisitTypes()
        loadSelectedTypeFromChecklist()
        selectDefaultSiteVisitTypeIfNeeded()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func reloadArtifacts() {
        guard let siteVisitId = siteVisit?.id else {
            artifacts = []
            return
        }

        let descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { artifact in
                artifact.siteVisitId == siteVisitId
            },
            sortBy: [SortDescriptor(\.capturedAt, order: .reverse)]
        )
        artifacts = (try? modelContext.fetch(descriptor)) ?? []
    }

    func reloadSiteVisitTypes() {
        let targetCompanyId = companyId
        let descriptor = FetchDescriptor<SiteVisitType>(
            predicate: #Predicate<SiteVisitType> { type in
                type.companyId == targetCompanyId && type.deletedAt == nil
            },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.name)
            ]
        )
        siteVisitTypes = (try? modelContext.fetch(descriptor)) ?? []
    }

    func reloadChecklistAnswers() {
        guard let siteVisitId = siteVisit?.id else {
            checklistAnswers = []
            selectedSiteVisitType = nil
            return
        }

        let descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { answer in
                answer.siteVisitId == siteVisitId
            },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        checklistAnswers = ((try? modelContext.fetch(descriptor)) ?? [])
            .filter(\.isActive)
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func selectSiteVisitType(_ type: SiteVisitType) {
        guard let visit = requireVisit() else { return }
        selectedSiteVisitType = type

        let existing = fetchChecklistAnswers(siteVisitId: visit.id)
        let activeExisting = existing.filter(\.isActive)
        if activeExisting.contains(where: { $0.siteVisitTypeId == type.id }) {
            checklistAnswers = activeExisting.sortedByChecklistOrder()
            return
        }

        for answer in activeExisting {
            answer.deletedAt = Date()
            answer.updatedAt = Date()
            answer.needsSync = true
        }

        let answers = SiteVisitChecklistAnswer.makeAnswers(
            for: type,
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            createdBy: userId
        )
        for answer in answers {
            modelContext.insert(answer)
        }

        saveContext()
        reloadChecklistAnswers()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func updateChecklistAnswer(
        _ answer: SiteVisitChecklistAnswer,
        value: SiteVisitChecklistValue
    ) {
        answer.answerValue = value
        answer.updatedAt = Date()
        answer.needsSync = true
        saveContext()
        reloadChecklistAnswers()
    }

    func useCapturedEvidence(for answer: SiteVisitChecklistAnswer) {
        guard let value = capturedEvidenceValue(for: answer) else {
            errorMessage = "NO MATCHING CAPTURE"
            return
        }
        updateChecklistAnswer(answer, value: value)
    }

    func addAdHocChecklistQuestion(
        label rawLabel: String,
        kind: SiteVisitFieldKind
    ) {
        guard let visit = requireVisit() else { return }
        let label = rawLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { return }

        let nextSortOrder = ((checklistAnswers.map(\.sortOrder).max() ?? 0) + 10)
        let answer = SiteVisitChecklistAnswer(
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            siteVisitTypeId: selectedSiteVisitType?.id,
            fieldId: "ad-hoc-\(UUID().uuidString)",
            label: label,
            kind: kind,
            required: false,
            sortOrder: nextSortOrder,
            createdBy: userId
        )
        modelContext.insert(answer)
        saveContext()
        reloadChecklistAnswers()
    }

    func addPhotos(_ images: [UIImage]) {
        guard let visit = requireVisit() else { return }
        var savedCount = 0

        for image in images {
            guard let imageData = image.jpegData(compressionQuality: 0.78) else { continue }
            let localID = "site_visit_\(visit.id)_\(UUID().uuidString).jpg"
            let localAssetURL = "local://project_images/\(localID)"
            guard ImageFileManager.shared.saveImage(data: imageData, localID: localAssetURL) else { continue }

            let artifact = SiteVisitCaptureArtifact(
                siteVisitId: visit.id,
                companyId: companyId,
                opportunityId: activeOpportunityId,
                kind: .photo,
                source: .camera,
                title: "Site photo",
                localAssetURL: localAssetURL,
                capturedAt: Date(),
                createdBy: userId
            )
            modelContext.insert(artifact)
            savedCount += 1
        }

        if savedCount == 0 {
            errorMessage = "NO PHOTOS SAVED"
        } else {
            saveContext()
            reloadArtifacts()
            hydrateChecklistAnswersFromCapturedEvidence()
        }
    }

    func addNote(source: SiteVisitCaptureSource = .keyboard) {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let visit = requireVisit() else { return }

        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            kind: source == .microphone ? .transcript : .note,
            source: source,
            title: source == .microphone ? "Dictated note" : "Site note",
            body: trimmed,
            capturedAt: Date(),
            createdBy: userId
        )
        modelContext.insert(artifact)
        noteDraft = ""
        saveContext()
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func autosaveNote(source: SiteVisitCaptureSource = .keyboard) {
        guard let visit = requireVisit() else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let artifact = autosavedNoteArtifact() {
                artifact.deletedAt = Date()
                artifact.updatedAt = Date()
                artifact.needsSync = true
                autosavedNoteArtifactId = nil
                saveContext()
                reloadArtifacts()
            }
            return
        }

        if let artifact = autosavedNoteArtifact(), artifact.isActive {
            artifact.body = trimmed
            artifact.updatedAt = Date()
            artifact.needsSync = true
            saveContext()
            reloadArtifacts()
            return
        }

        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            kind: source == .microphone ? .transcript : .note,
            source: source,
            title: source == .microphone ? "Dictated note" : "Site note",
            body: trimmed,
            capturedAt: Date(),
            createdBy: userId
        )
        modelContext.insert(artifact)
        autosavedNoteArtifactId = artifact.id
        saveContext()
        reloadArtifacts()
    }

    /// Appends dictated text to the working note instead of overwriting it, so
    /// switching between typing and dictation never destroys what's already there.
    /// The combined text is autosaved to the single live draft artifact.
    func appendDictation(_ text: String) {
        let addition = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !addition.isEmpty else { return }
        let existing = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        noteDraft = existing.isEmpty ? addition : existing + "\n" + addition
        autosaveNote(source: existing.isEmpty ? .microphone : .keyboard)
    }

    /// Commits the working note as a discrete, finished artifact and clears the
    /// box so the next note starts fresh. The live autosaved draft is promoted in
    /// place (no duplicate) and detached so subsequent typing opens a new note.
    func commitNote() {
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let visit = requireVisit() else { return }

        if let artifact = autosavedNoteArtifact(), artifact.isActive {
            artifact.body = trimmed
            artifact.updatedAt = Date()
            artifact.needsSync = true
        } else {
            let artifact = SiteVisitCaptureArtifact(
                siteVisitId: visit.id,
                companyId: companyId,
                opportunityId: activeOpportunityId,
                kind: .note,
                source: .keyboard,
                title: "Site note",
                body: trimmed,
                capturedAt: Date(),
                createdBy: userId
            )
            modelContext.insert(artifact)
        }

        autosavedNoteArtifactId = nil
        noteDraft = ""
        saveContext()
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func addMeasurement(source: SiteVisitCaptureSource = .manual) {
        let trimmed = measurementDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let visit = requireVisit() else { return }

        let artifact = SiteVisitCaptureArtifact(
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            kind: .measurement,
            source: source,
            title: "Field measurement",
            body: trimmed,
            capturedAt: Date(),
            createdBy: userId
        )
        modelContext.insert(artifact)
        measurementDraft = ""
        saveContext()
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func addDimensionedCapture(
        assets: CapturedAssets,
        dimensions: DimensionsData
    ) throws {
        guard let visit = requireVisit() else {
            errorMessage = "SITE VISIT UNAVAILABLE"
            throw SiteVisitCaptureViewModelError.missingSiteVisit
        }
        _ = try SiteVisitDimensionedCaptureStore.persist(
            captured: assets,
            dimensions: dimensions,
            siteVisitId: visit.id,
            opportunityId: activeOpportunityId,
            companyId: companyId,
            createdBy: userId,
            modelContext: modelContext
        )
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func attachDeckDesign(_ deckDesign: DeckDesign) {
        guard let visit = requireVisit() else { return }

        // Idempotent on reopen: one active artifact per design. Continuing a
        // design (checklist EDIT, or a lead deck carried into the visit) must
        // not stack duplicate DECK artifacts, inflate the summary count, or
        // hand conversion the same design twice.
        let alreadyAttached = activeArtifacts.contains {
            $0.kind == .deckDesign && $0.deckDesignId == deckDesign.id
        }
        if !alreadyAttached {
            let artifact = SiteVisitCaptureArtifact(
                siteVisitId: visit.id,
                companyId: companyId,
                opportunityId: activeOpportunityId,
                kind: .deckDesign,
                source: .deckBuilder,
                title: deckDesign.title,
                deckDesignId: deckDesign.id,
                capturedAt: Date(),
                createdBy: userId
            )
            modelContext.insert(artifact)
        }
        if let deckAnswer = checklistAnswers.first(where: {
            $0.isActive && $0.kind == .deckDesign
        }) {
            deckAnswer.answerValue = .deckDesign(deckDesign.id)
            deckAnswer.updatedAt = Date()
            deckAnswer.needsSync = true
        }
        saveContext()
        reloadArtifacts()
        reloadChecklistAnswers()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func setIncluded(_ artifact: SiteVisitCaptureArtifact, included: Bool) {
        artifact.includedInProjectReview = included
        artifact.updatedAt = Date()
        artifact.needsSync = true
        saveContext()
        reloadArtifacts()
    }

    func completeVisit() -> Bool {
        guard canComplete, let visit = requireVisit() else {
            errorMessage = "CAPTURE SOMETHING FIRST"
            return false
        }

        isCompleting = true
        visit.status = .completed
        visit.completedAt = Date()
        visit.notes = combinedNotes()
        saveContext()
        isCompleting = false

        // Best-effort: post a "Site visit" activity to the timeline. Site visits
        // are LOCAL-ONLY (they never reach Supabase), so no DB trigger can fire —
        // this app-side insert is the ONLY path onto the timeline. Fire-and-forget
        // so completion never blocks or fails on the network; idempotent so a
        // re-completion can't double-post. Pass the id, not the instance — the
        // visit can be gone by the time this task runs (deleted meanwhile, or a
        // torn-down store), and SwiftData traps on touching a dead instance.
        let visitId = visit.id
        siteVisitActivityTask = Task { await postSiteVisitActivityIfNeeded(forVisitId: visitId) }

        return true
    }

    /// Bug (site-visit report) — completing a visit must NOT convert the lead
    /// to WON. Save the visit (which also posts the timeline activity) and,
    /// when a lead is bound, move it to the operator-chosen stage (defaulting
    /// to QUALIFYING via `SiteVisitStageDefault`). Conversion stays a separate,
    /// explicit CREATE PROJECT action. Returns whether the visit itself saved;
    /// a failed stage move is surfaced but does not fail the save.
    func saveVisit(movingLeadTo stage: PipelineStage) async -> Bool {
        guard completeVisit() else { return false }

        // Only touch the lead when one is bound, the stage actually changed,
        // and the target is non-terminal — a visit save never closes a lead.
        guard let opportunity = currentOpportunity,
              stage != opportunity.stage,
              !stage.isTerminal else {
            return true
        }

        let repo = OpportunityRepository(companyId: companyIdentifier)
        do {
            _ = try await repo.moveToStage(
                opportunityId: opportunity.id,
                to: stage,
                userId: userId
            )
            // Reflect the authoritative server move on the in-memory lead so
            // the UI (and any re-open) shows the new stage immediately.
            opportunity.stage = stage
            opportunity.stageEnteredAt = Date()
            opportunity.stageManuallySet = true
        } catch {
            errorMessage = "VISIT SAVED · STAGE NOT UPDATED"
        }
        return true
    }

    // MARK: - Timeline auto-post (app-side, local-only visit)

    /// The parent a completed visit's activity attaches to. Prefers the bound
    /// opportunity so the "Site visit" row lands on the LEAD timeline — the only
    /// activity timeline that renders today (client/job timelines are a deferred
    /// follow-on). Falls back to the client when no lead is bound. `nil` when the
    /// visit is fully unbound (no lead AND no client) — nothing to attach to, so
    /// no activity is posted.
    ///
    /// The site-visit flow's `currentOpportunity` is a synced server row — it
    /// comes from the pipeline, or from an inline lead create that round-trips
    /// through `OpportunityRepository.create` before `reassignVisit` binds it —
    /// so the `opportunity_id` FK is safe in practice. The post is best-effort
    /// and idempotent regardless, so a rare unsynced-lead FK rejection is
    /// absorbed and retried on the next completion rather than lost.
    var siteVisitActivityTarget: ActivityTarget? {
        if let opportunity = currentOpportunity {
            return .opportunity(opportunity)
        }
        if let clientId = activeClientId?.trimmedNilIfEmpty,
           let client = fetchClient(id: clientId) {
            return .client(client)
        }
        return nil
    }

    /// A terse human summary of what the visit captured — the operator's notes,
    /// then a one-line roll-up of how many checklist items were answered — used
    /// as the activity body. `nil` when nothing was captured (the DB trigger
    /// still backfills the "Site visit" subject, so the row is never blank).
    var siteVisitActivitySummary: String? {
        var lines: [String] = []
        if let notes = combinedNotes()?.trimmedNilIfEmpty {
            lines.append(notes)
        }
        let answered = checklistAnswers.filter { $0.isActive && $0.isAnswered }.count
        if answered > 0 {
            lines.append("\(answered) checklist item\(answered == 1 ? "" : "s") completed")
        }
        let joined = lines.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return joined.isEmpty ? nil : joined
    }

    /// Guards against a double-tap racing two posts before the first stamps
    /// `loggedActivityId` — set synchronously on the MainActor before the first
    /// `await`, so a second scheduled post sees it and bails.
    private var isPostingSiteVisitActivity = false
    /// The in-flight best-effort activity post, if any. Tests that call
    /// `completeVisit()` MUST `await siteVisitActivityTask?.value` before
    /// their model container goes away — a task left pending outlives the
    /// store and traps on the dead context. (In the app the container lives
    /// for the process, so the task may safely outlive any one screen.)
    private(set) var siteVisitActivityTask: Task<Void, Never>?

    /// Best-effort post of a completed visit's "Site visit" activity. Idempotent:
    /// no-ops when the visit already logged one (offline-retry safe), when a post
    /// is already in flight, or when the visit is unbound. Never throws — a failed
    /// post leaves `loggedActivityId` nil so a later re-completion retries without
    /// duplicating.
    func postSiteVisitActivityIfNeeded(forVisitId visitId: String) async {
        // Re-fetch by id: this task can outlive the completing visit (deleted
        // meanwhile, or the whole store torn down). A missed fetch skips the
        // post; the next completion retries.
        let descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.id == visitId }
        )
        guard let visit = (try? modelContext.fetch(descriptor))?.first else { return }
        guard visit.loggedActivityId == nil else { return }
        guard !isPostingSiteVisitActivity else { return }
        guard let target = siteVisitActivityTarget else { return }

        isPostingSiteVisitActivity = true
        defer { isPostingSiteVisitActivity = false }

        do {
            let activity = try await ActivityRepository(companyId: companyId).logActivity(
                target: target,
                type: .siteVisit,
                subject: nil,                       // trigger backfills "Site visit"
                body: siteVisitActivitySummary,
                siteVisitId: visit.id,
                createdBy: userId
            )
            visit.loggedActivityId = activity.id
            saveContext()
        } catch {
            // Swallow — best-effort. loggedActivityId stays nil so a re-completion
            // (e.g. once connectivity returns) retries without double-posting.
        }
    }

    func projectPayload() -> SiteVisitProjectPayload? {
        guard let visit = siteVisit, let opportunityId = activeOpportunityId else { return nil }
        return SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: visit.id,
            opportunityId: opportunityId,
            address: identityDraft?.address.trimmedNilIfEmpty ?? visit.address ?? currentOpportunity?.address,
            artifacts: artifacts,
            checklistAnswers: checklistAnswers,
            // Carried into the packet so the SITE VISIT RECORD can name who was
            // met on a teammate's device. The value rides along too and is
            // filtered at render for viewers without financial visibility.
            contactName: currentOpportunity?.displayContactName ?? identityDraft?.contactName.trimmedNilIfEmpty,
            companyName: identityDraft?.clientName.trimmedNilIfEmpty,
            estimatedValue: currentOpportunity?.estimatedValue
        )
    }

    func reassignVisit(to opportunity: Opportunity) {
        guard opportunity.id != currentOpportunity?.id else { return }
        let priorAddress = currentOpportunity?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visitAddress = siteVisit?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorDraftAddress = identityDraft?.address.trimmingCharacters(in: .whitespacesAndNewlines)

        currentOpportunity = opportunity
        bindIdentityDraft(to: opportunity)
        if let visit = requireVisit() {
            visit.opportunityId = opportunity.id
            if visitAddress == nil || visitAddress?.isEmpty == true || visitAddress == priorAddress {
                visit.address = opportunity.address
            }
        }

        // The identity draft's address is the highest-priority source for
        // `captureAddress`, so it must follow the reassignment too — but only
        // when it was empty or still matched the previous lead (never clobber an
        // address the operator typed by hand).
        if let draft = identityDraft,
           priorDraftAddress == nil || priorDraftAddress?.isEmpty == true || priorDraftAddress == priorAddress {
            draft.address = opportunity.address ?? ""
            draft.touch()
        }

        for artifact in artifacts {
            artifact.opportunityId = opportunity.id
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }

        let answerRecords = siteVisit.map { fetchChecklistAnswers(siteVisitId: $0.id) } ?? checklistAnswers
        for answer in answerRecords {
            answer.opportunityId = opportunity.id
            answer.updatedAt = Date()
            answer.needsSync = true
        }

        saveContext()
        reloadArtifacts()
        reloadChecklistAnswers()
    }

    func bindClient(_ client: Client) {
        guard let draft = requireIdentityDraft() else { return }
        draft.clientId = client.id
        // A selected client's name is the person/company you're capturing for →
        // NAME. COMPANY stays whatever the operator typed (usually empty).
        if draft.contactName.trimmedNilIfEmpty == nil {
            draft.contactName = client.name
        }
        if draft.preferredEmail.trimmedNilIfEmpty == nil {
            draft.preferredEmail = client.email ?? ""
        }
        if draft.phoneNumber.trimmedNilIfEmpty == nil {
            draft.phoneNumber = client.phoneNumber ?? ""
        }
        if draft.address.trimmedNilIfEmpty == nil {
            draft.address = client.address ?? ""
        }
        draft.touch()
        siteVisit?.address = draft.address.trimmedNilIfEmpty ?? siteVisit?.address
        saveContext()
        objectWillChange.send()
    }

    /// Clears the linked lead/client and wipes the identity fields — the X on the
    /// search box. Captured photos/notes/measurements are kept; only identity and
    /// the binding are reset.
    func clearIdentitySelection() {
        guard let draft = requireIdentityDraft() else { return }
        draft.opportunityId = nil
        draft.clientId = nil
        draft.subClientId = nil
        draft.searchText = ""
        draft.clientName = ""
        draft.contactName = ""
        draft.preferredEmail = ""
        draft.additionalEmails = []
        draft.phoneNumber = ""
        draft.address = ""
        draft.notes = ""
        draft.touch()

        currentOpportunity = nil
        if let visit = siteVisit {
            visit.opportunityId = nil
            visit.address = nil
        }
        for artifact in artifacts {
            artifact.opportunityId = nil
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }
        saveContext()
        objectWillChange.send()
    }

    func createLeadFromIdentityDraft(dataController: DataController) async -> SiteVisitLeadCreateOutcome {
        if let currentOpportunity {
            return .created(currentOpportunity)
        }

        guard let draft = requireIdentityDraft() else { return .failed }
        guard let clientName = draft.clientName.trimmedNilIfEmpty ?? draft.contactName.trimmedNilIfEmpty else {
            errorMessage = "CLIENT NAME REQUIRED"
            return .failed
        }
        guard draft.preferredEmail.trimmedNilIfEmpty != nil || draft.phoneNumber.trimmedNilIfEmpty != nil else {
            errorMessage = "CONTACT REQUIRED"
            return .failed
        }

        isCommittingIdentity = true
        defer { isCommittingIdentity = false }

        var upsertedClient: Client?
        do {
            let upserted = try await upsertClientFromIdentityDraft(
                draft,
                clientName: clientName,
                dataController: dataController
            )
            let client = upserted.client
            upsertedClient = client
            try await createMissingSubContacts(
                from: draft,
                client: client,
                dataController: dataController
            )

            // A client this draft just created exists LOCALLY first, and the
            // guarded RPC refuses a lead whose client the server cannot see
            // (`client_not_found_in_company`, 22023) — rolling the whole
            // transaction back. Wait for the parent before writing the child.
            // Clients we merely updated are already server-side.
            if upserted.isNew {
                switch await awaitClientServerVisibility(clientId: client.id) {
                case .visible:
                    break
                case .offline:
                    return handOffLeadDelivery(client, draft: draft, offline: true)
                case .notVisible:
                    return handOffLeadDelivery(client, draft: draft, offline: false)
                }
            }

            let contactName = draft.contactName.trimmedNilIfEmpty ?? clientName
            let dto = CreateOpportunityDTO(
                title: "\(contactName) site visit",
                contactName: contactName,
                contactEmail: draft.preferredEmail.trimmedNilIfEmpty,
                contactPhone: draft.phoneNumber.trimmedNilIfEmpty,
                description: draft.notes.trimmedNilIfEmpty,
                address: draft.address.trimmedNilIfEmpty,
                source: ClientLeadAutocreate.schemaAllowedSource,
                sourceThreadKey: ClientLeadAutocreate.sourceThreadKey(forClientId: client.id),
                priority: ClientLeadAutocreate.schemaAllowedPriority,
                clientId: client.id
            )
            let created = try await createOpportunityRemotely(dto, companyId)
            let opportunity = upsertLocalOpportunity(created.toModel())

            draft.opportunityId = opportunity.id
            draft.clientId = client.id
            draft.lastCommittedAt = currentDate()
            draft.touch()
            reassignVisit(to: opportunity)
            errorMessage = nil
            saveContext()
            return .created(opportunity)
        } catch {
            draft.touch()
            saveContext()

            // Only the server-side lead create failed — the capture packet, the
            // identity draft, and the client are all persisted locally. That is
            // a handoff, not a failure: `ClientLeadAutocreateQueue` retries the
            // delivery durably (classify → backoff → park) across app launches
            // and, on success, binds this draft + visit to the delivered lead.
            // The direct DTO above and the queued retry share a
            // `source_thread_key`, and the RPC is idempotent on
            // (company_id, source_thread_key), so they reconcile to ONE lead and
            // can never duplicate.
            if let client = upsertedClient {
                return handOffLeadDelivery(client, draft: draft, offline: isLikelyOfflineError(error))
            }

            // Nothing landed — there is no client to hang a lead on, so this is
            // a real failure the operator has to retry.
            errorMessage = isLikelyOfflineError(error)
                ? "NO SIGNAL · DRAFT SAVED · RETRY WHEN ONLINE"
                : "LEAD CREATE FAILED · DRAFT SAVED · RETRY"
            return .failed
        }
    }

    /// Bounded wait for a just-created client to become readable by this
    /// session. Mirrors the guard the durable queue has always had.
    private func awaitClientServerVisibility(clientId: String) async -> ClientServerVisibility.Outcome {
        await ClientServerVisibility.wait(
            clientId: clientId,
            companyId: companyId,
            attempts: clientVisibilityAttempts,
            probe: probeClientVisibility,
            backoff: clientVisibilityBackoff,
            isOffline: isLikelyOfflineError
        )
    }

    /// The client is saved and the lead's server insert has not happened yet.
    /// Hand delivery to the durable queue and report `.queued` — this is not an
    /// error and must never be rendered as one (bug 13c66762).
    private func handOffLeadDelivery(
        _ client: Client,
        draft: SiteVisitIdentityDraft,
        offline: Bool
    ) -> SiteVisitLeadCreateOutcome {
        draft.clientId = client.id
        draft.touch()
        errorMessage = nil
        saveContext()
        leadAutocreateQueue.enqueueAndDrainInBackground(client, companyId: companyId)
        return .queued(offline: offline)
    }

    /// The durable queue delivered a lead and wrote its binding into the store.
    /// Re-read it so an OPEN console flips to LINKED immediately instead of
    /// waiting for some unrelated redraw.
    func adoptQueueDeliveredLead(forVisitId visitId: String?) {
        guard let visitId, visitId == activeSiteVisitId else { return }
        guard currentOpportunity == nil else { return }

        // Re-read the draft the queue just wrote rather than trusting the cached
        // instance — the binding happened outside this view model.
        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let draft = try? modelContext.fetch(draftDescriptor).first,
              let opportunityId = draft.opportunityId?.trimmedNilIfEmpty else { return }

        let opportunityDescriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { $0.id == opportunityId }
        )
        guard let delivered = try? modelContext.fetch(opportunityDescriptor).first else { return }

        identityDraft = draft
        currentOpportunity = delivered

        let visitDescriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.id == visitId }
        )
        if let visit = try? modelContext.fetch(visitDescriptor).first {
            siteVisit = visit
            if visit.opportunityId == nil {
                visit.opportunityId = delivered.id
            }
        }
        saveContext()
        objectWillChange.send()
    }

    private func isLikelyOfflineError(_ error: Error) -> Bool {
        ClientServerVisibility.isLikelyOfflineError(error)
    }

    /// - Parameter isHydrated: whether the caller's field mirror has been filled
    ///   from this draft yet. A panel that has not hydrated holds empty strings,
    ///   not edits — committing them would erase a saved draft. That is the
    ///   form-wipe half of bug 5d5df5b0: the identity panel's `.task` awaited a
    ///   network fetch BEFORE hydrating, leaving a window in which autosave or
    ///   `onDisappear` could write the empty mirror back. Deliberate clears go
    ///   through `clearIdentityBinding()` and are unaffected.
    func updateIdentityDraft(
        searchText: String,
        clientName: String,
        contactName: String,
        preferredEmail: String,
        additionalEmailsText: String,
        phoneNumber: String,
        address: String,
        notes: String,
        isHydrated: Bool = true
    ) {
        guard isHydrated else { return }
        guard let draft = requireIdentityDraft() else { return }
        draft.searchText = searchText
        draft.clientName = clientName
        draft.contactName = contactName
        draft.preferredEmail = preferredEmail
        draft.additionalEmails = additionalEmailsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        draft.phoneNumber = phoneNumber
        // Canonicalize comma-less hand-typed addresses at the persistence
        // boundary ("972 Lyall St Esquimalt" → "972 Lyall St, Esquimalt") so
        // the server's comma-splitting derive_project_name produces the same
        // street-line project name iOS previews.
        let canonicalAddress = ProjectAutoNamer.canonicalizedAddress(address)
        draft.address = canonicalAddress
        draft.notes = notes
        draft.touch()

        if let normalizedAddress = canonicalAddress.trimmedNilIfEmpty {
            siteVisit?.address = normalizedAddress
            if currentOpportunity?.address?.trimmedNilIfEmpty == nil {
                currentOpportunity?.address = normalizedAddress
            }
        }
        saveContext()
        objectWillChange.send()
    }

    /// Fill the identity draft from a device contact the operator picked.
    ///
    /// This lives on the model, not in the panel, for two reasons: the picker is
    /// presented from the console root (so it survives the identity panel being
    /// scrolled out of existence), and an import must be durable the moment it
    /// happens — the panel's field mirror re-hydrates from the draft afterwards
    /// via `contactImportGeneration`.
    ///
    /// Each field is only overwritten when the contact actually carries a value,
    /// so a partly typed form is never wiped by an import.
    func applyImportedContact(_ contact: CNContact) {
        guard let draft = requireIdentityDraft() else { return }

        let given = contact.givenName.trimmingCharacters(in: .whitespaces)
        let family = contact.familyName.trimmingCharacters(in: .whitespaces)
        let fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
        if !fullName.isEmpty { draft.contactName = fullName }

        let organization = contact.organizationName.trimmingCharacters(in: .whitespaces)
        if !organization.isEmpty { draft.clientName = organization }

        if let email = contact.emailAddresses.first
            .map({ ($0.value as String).trimmingCharacters(in: .whitespaces) }),
           !email.isEmpty {
            draft.preferredEmail = email
        }

        if let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespaces), !phone.isEmpty {
            draft.phoneNumber = phone
        }

        // A picked postal address is a commit (like an autocomplete selection),
        // so it lands on the visit as well as the draft. No geocode here, so
        // coordinates stay nil.
        let composedAddress = Self.composeAddress(from: contact)
        if let composedAddress {
            let canonical = ProjectAutoNamer.canonicalizedAddress(composedAddress)
            draft.address = canonical
            siteVisit?.address = canonical.trimmedNilIfEmpty
        }

        draft.touch()
        saveContext()
        contactImportGeneration += 1
        objectWillChange.send()

        // Import is only offered on an unlinked visit, but if a lead IS bound,
        // push the address to its server row the same way an autocomplete
        // selection does.
        if composedAddress != nil, currentOpportunity != nil {
            applySelectedSiteAddress(draft.address, coordinate: nil)
        }
    }

    /// Single comma-separated line from the contact's first postal address,
    /// matching `AddressAutocompleteField`'s output shape.
    static func composeAddress(from contact: CNContact) -> String? {
        guard let postal = contact.postalAddresses.first?.value else { return nil }
        var components: [String] = []
        if !postal.street.isEmpty { components.append(postal.street) }
        if !postal.city.isEmpty { components.append(postal.city) }
        if !postal.state.isEmpty { components.append(postal.state) }
        if !postal.postalCode.isEmpty { components.append(postal.postalCode) }
        let joined = components.joined(separator: ", ")
        return joined.isEmpty ? nil : joined
    }

    /// An autocomplete selection is a deliberate commit (unlike keystrokes):
    /// persist it through to the visit, the draft, and the bound lead's
    /// server row immediately — coordinates included, so the converted
    /// project gets its map pin.
    func applySelectedSiteAddress(_ rawAddress: String, coordinate: CLLocationCoordinate2D?) {
        Task { await updateVisitAddress(rawAddress, persistToLead: true, coordinate: coordinate) }
    }

    func updateVisitAddress(
        _ rawAddress: String,
        persistToLead: Bool,
        coordinate: CLLocationCoordinate2D? = nil
    ) async {
        let trimmed = ProjectAutoNamer.canonicalizedAddress(rawAddress)
        let normalized = trimmed.isEmpty ? nil : trimmed

        guard let visit = requireVisit() else { return }
        objectWillChange.send()
        visit.address = normalized
        identityDraft?.address = normalized ?? ""
        identityDraft?.touch()
        currentOpportunity?.updatedAt = Date()
        if persistToLead, currentOpportunity != nil {
            currentOpportunity?.address = normalized
        }
        saveContext()

        guard persistToLead, let opportunity = currentOpportunity else { return }
        do {
            let patch = OpportunityAddressPatch(
                address: normalized,
                latitude: coordinate?.latitude,
                longitude: coordinate?.longitude
            )
            let updatedDTO = try await OpportunityRepository(companyId: companyId)
                .update(opportunity.id, patch: patch)
            let updated = updatedDTO.toModel()
            currentOpportunity?.address = updated.address
            currentOpportunity?.updatedAt = updated.updatedAt
            objectWillChange.send()
            saveContext()
        } catch {
            errorMessage = "ADDRESS SAVE FAILED"
        }
    }

    /// Open (not completed, not cancelled) visits for this company, newest first.
    private func openVisits() -> [SiteVisit] {
        let descriptor = FetchDescriptor<SiteVisit>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        return ((try? modelContext.fetch(descriptor)) ?? [])
            .filter { $0.companyId == companyId && $0.completedAt == nil && $0.status != .cancelled }
    }

    private func createVisit() -> SiteVisit {
        let visit = SiteVisit(
            opportunityId: currentOpportunity?.id,
            companyId: companyId,
            status: .scheduled
        )
        visit.address = currentOpportunity?.address
        visit.assignedTo = userId
        modelContext.insert(visit)
        saveContext()
        return visit
    }

    /// A visit "has content" if it carries any active capture artifact or an
    /// identity draft the operator has actually started filling in.
    private func visitHasContent(_ visit: SiteVisit) -> Bool {
        let visitId = visit.id
        let artifactDescriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == visitId }
        )
        let hasArtifacts = ((try? modelContext.fetch(artifactDescriptor)) ?? [])
            .contains { $0.deletedAt == nil }
        if hasArtifacts { return true }

        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId }
        )
        if let draft = try? modelContext.fetch(draftDescriptor).first, draft.filledFieldCount > 0 {
            return true
        }
        return false
    }

    /// The last moment the operator actually touched a visit. `SiteVisit` itself
    /// is local-only and carries no `updatedAt`, so recency is read off the work
    /// hanging from it — the identity draft and the capture artifacts — falling
    /// back to when the visit was opened.
    private func lastActivity(of visit: SiteVisit) -> Date {
        var latest = visit.createdAt
        for draft in childDrafts(of: visit.id) where draft.updatedAt > latest {
            latest = draft.updatedAt
        }
        for artifact in childArtifacts(of: visit.id) {
            let touched = max(artifact.capturedAt, artifact.updatedAt ?? artifact.capturedAt)
            if touched > latest { latest = touched }
        }
        return latest
    }

    /// Hard-removes an empty/abandoned visit and any stray children. Used only
    /// for visits with no captured evidence (the sweep in `loadOrCreateVisit`).
    private func hardDeleteVisit(_ visit: SiteVisit) {
        let visitId = visit.id
        for child in childArtifacts(of: visitId) { modelContext.delete(child) }
        for answer in childAnswers(of: visitId) { modelContext.delete(answer) }
        for draft in childDrafts(of: visitId) { modelContext.delete(draft) }
        modelContext.delete(visit)
        saveContext()
    }

    /// Operator-initiated discard of the ACTIVE visit. Soft-deletes captured
    /// artifacts and checklist answers (so the deletion syncs), marks the visit
    /// cancelled (excluded from future open-visit lookups), and clears state.
    func discardVisit() {
        guard let visit = siteVisit else { return }
        let now = Date()
        for artifact in childArtifacts(of: visit.id) where artifact.deletedAt == nil {
            artifact.deletedAt = now
            artifact.updatedAt = now
            artifact.needsSync = true
        }
        for answer in childAnswers(of: visit.id) where answer.deletedAt == nil {
            answer.deletedAt = now
            answer.updatedAt = now
            answer.needsSync = true
        }
        for draft in childDrafts(of: visit.id) { modelContext.delete(draft) }
        visit.status = .cancelled
        saveContext()

        artifacts = []
        checklistAnswers = []
        noteDraft = ""
        measurementDraft = ""
        autosavedNoteArtifactId = nil
    }

    /// Switches the active visit to the surfaced resumable one, discarding the
    /// empty visit the console opened on.
    func resumeResumableVisit() {
        guard let resume = resumableVisit else { return }
        if let current = siteVisit, current.id != resume.id, !visitHasContent(current) {
            hardDeleteVisit(current)
        }
        siteVisit = resume
        resumableVisit = nil
        loadOrCreateIdentityDraft()
        reloadArtifacts()
        reloadSiteVisitTypes()
        loadSelectedTypeFromChecklist()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func dismissResumePrompt() {
        resumableVisit = nil
    }

    private func childArtifacts(of visitId: String) -> [SiteVisitCaptureArtifact] {
        let descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == visitId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func childAnswers(of visitId: String) -> [SiteVisitChecklistAnswer] {
        let descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { $0.siteVisitId == visitId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func childDrafts(of visitId: String) -> [SiteVisitIdentityDraft] {
        let descriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// A short, human label for the resumable visit shown in the resume prompt.
    var resumableVisitSummary: String? {
        guard let resume = resumableVisit else { return nil }
        let visitId = resume.id
        let count = childArtifacts(of: visitId).filter { $0.deletedAt == nil }.count
        let draft = childDrafts(of: visitId).first
        let name = draft?.displayName
        let who = (name == nil || name == "Unlinked visit") ? nil : name
        switch (who, count) {
        case let (who?, n) where n > 0: return "\(who.uppercased()) · \(n) ITEMS"
        case let (who?, _): return who.uppercased()
        case let (nil, n) where n > 0: return "\(n) ITEMS CAPTURED"
        default: return "IN PROGRESS"
        }
    }

    private func loadOrCreateIdentityDraft() {
        guard let visit = siteVisit else {
            identityDraft = nil
            return
        }

        let siteVisitId = visit.id
        let descriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { draft in
                draft.siteVisitId == siteVisitId
            },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            identityDraft = existing
            return
        }

        let draft = SiteVisitIdentityDraft(
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: currentOpportunity?.id,
            clientId: currentOpportunity?.clientId,
            searchText: "",
            // NAME holds the person; COMPANY (clientName) stays empty unless the
            // operator types a business — never seed it with the contact's name.
            clientName: "",
            contactName: currentOpportunity?.displayContactName ?? "",
            preferredEmail: currentOpportunity?.contactEmail ?? "",
            phoneNumber: currentOpportunity?.contactPhone ?? "",
            address: currentOpportunity?.address ?? visit.address ?? ""
        )
        modelContext.insert(draft)
        identityDraft = draft
        saveContext()
    }

    private func requireIdentityDraft() -> SiteVisitIdentityDraft? {
        if identityDraft == nil {
            if siteVisit == nil {
                loadOrCreateVisit()
            } else {
                loadOrCreateIdentityDraft()
            }
        }
        return identityDraft
    }

    private func bindIdentityDraft(to opportunity: Opportunity) {
        guard let draft = requireIdentityDraft() else { return }
        draft.opportunityId = opportunity.id
        draft.clientId = opportunity.clientId
        if draft.contactName.trimmedNilIfEmpty == nil {
            draft.contactName = opportunity.displayContactName
        }
        if draft.preferredEmail.trimmedNilIfEmpty == nil {
            draft.preferredEmail = opportunity.contactEmail ?? ""
        }
        if draft.phoneNumber.trimmedNilIfEmpty == nil {
            draft.phoneNumber = opportunity.contactPhone ?? ""
        }
        if draft.address.trimmedNilIfEmpty == nil {
            draft.address = opportunity.address ?? ""
        }
        draft.touch()
    }

    /// A client the lead-create path resolved, and whether this call is what
    /// brought it into existence. Only a brand-new client needs the
    /// server-visibility wait — an updated one is already server-side.
    private struct UpsertedIdentityClient {
        let client: Client
        let isNew: Bool
    }

    private func upsertClientFromIdentityDraft(
        _ draft: SiteVisitIdentityDraft,
        clientName: String,
        dataController: DataController
    ) async throws -> UpsertedIdentityClient {
        if let clientId = draft.clientId?.trimmedNilIfEmpty,
           let existing = fetchClient(id: clientId) {
            try await dataController.updateClientContact(
                clientId: existing.id,
                name: clientName,
                email: draft.preferredEmail.trimmedNilIfEmpty,
                phone: draft.phoneNumber.trimmedNilIfEmpty,
                address: draft.address.trimmedNilIfEmpty
            )
            if let notes = draft.notes.trimmedNilIfEmpty {
                try await dataController.updateClientNotes(clientId: existing.id, notes: notes)
            }
            return UpsertedIdentityClient(client: fetchClient(id: existing.id) ?? existing, isNew: false)
        }

        let clientId = UUID().uuidString.lowercased()
        let dto = SupabaseClientDTO(
            id: clientId,
            bubbleId: nil,
            companyId: companyId,
            name: clientName,
            email: draft.preferredEmail.trimmedNilIfEmpty,
            phoneNumber: draft.phoneNumber.trimmedNilIfEmpty,
            address: draft.address.trimmedNilIfEmpty,
            latitude: nil,
            longitude: nil,
            notes: draft.notes.trimmedNilIfEmpty,
            profileImageUrl: nil,
            deletedAt: nil
        )
        _ = try await dataController.createClient(dto: dto)
        draft.clientId = clientId
        draft.touch()
        saveContext()

        if let created = fetchClient(id: clientId) {
            return UpsertedIdentityClient(client: created, isNew: true)
        }

        let fallback = Client(
            id: clientId,
            name: clientName,
            email: draft.preferredEmail.trimmedNilIfEmpty,
            phoneNumber: draft.phoneNumber.trimmedNilIfEmpty,
            address: draft.address.trimmedNilIfEmpty,
            companyId: companyId,
            notes: draft.notes.trimmedNilIfEmpty
        )
        fallback.needsSync = true
        modelContext.insert(fallback)
        saveContext()
        dataController.triggerBackgroundSync()
        return UpsertedIdentityClient(client: fallback, isNew: true)
    }

    private func createMissingSubContacts(
        from draft: SiteVisitIdentityDraft,
        client: Client,
        dataController: DataController
    ) async throws {
        let primaryEmail = draft.preferredEmail.trimmedNilIfEmpty?.lowercased()
        let existingEmails = Set(
            client.subClients
                .compactMap { $0.email?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        )
        let additionalEmails = draft.additionalEmails
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { $0.lowercased() != primaryEmail }
            .filter { !existingEmails.contains($0.lowercased()) }

        guard !additionalEmails.isEmpty else { return }
        let contactName = draft.contactName.trimmedNilIfEmpty ?? client.name
        for email in additionalEmails {
            _ = try await dataController.createSubClient(
                clientId: client.id,
                name: contactName,
                title: "Site contact",
                email: email,
                phone: nil,
                address: draft.address.trimmedNilIfEmpty,
                companyId: companyId
            )
        }
    }

    private func fetchClient(id: String) -> Client? {
        let clientId = id
        let descriptor = FetchDescriptor<Client>(
            predicate: #Predicate<Client> { client in
                client.id == clientId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func upsertLocalOpportunity(_ incoming: Opportunity) -> Opportunity {
        let opportunityId = incoming.id
        let descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { opportunity in
                opportunity.id == opportunityId
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            copyOpportunityFields(from: incoming, to: existing)
            return existing
        }
        modelContext.insert(incoming)
        return incoming
    }

    private func copyOpportunityFields(from incoming: Opportunity, to existing: Opportunity) {
        existing.companyId = incoming.companyId
        existing.title = incoming.title
        existing.contactName = incoming.contactName
        existing.contactEmail = incoming.contactEmail
        existing.contactPhone = incoming.contactPhone
        existing.descriptionText = incoming.descriptionText
        existing.address = incoming.address
        existing.stage = incoming.stage
        existing.stageEnteredAt = incoming.stageEnteredAt
        existing.stageManuallySet = incoming.stageManuallySet
        existing.assignedTo = incoming.assignedTo
        existing.priority = incoming.priority
        existing.source = incoming.source
        existing.quoteDeliveryMethod = incoming.quoteDeliveryMethod
        existing.estimatedValue = incoming.estimatedValue
        existing.actualValue = incoming.actualValue
        existing.winProbabilityOverride = incoming.winProbabilityOverride
        existing.expectedCloseDate = incoming.expectedCloseDate
        existing.actualCloseDate = incoming.actualCloseDate
        existing.nextFollowUpAt = incoming.nextFollowUpAt
        existing.lastActivityAt = incoming.lastActivityAt
        existing.projectId = incoming.projectId
        existing.clientId = incoming.clientId
        existing.lostReason = incoming.lostReason
        existing.lostNotes = incoming.lostNotes
        existing.deletedAt = incoming.deletedAt
        existing.archivedAt = incoming.archivedAt
        existing.tags = incoming.tags
        existing.sourceEmailId = incoming.sourceEmailId
        existing.correspondenceCount = incoming.correspondenceCount
        existing.outboundCount = incoming.outboundCount
        existing.inboundCount = incoming.inboundCount
        existing.lastInboundAt = incoming.lastInboundAt
        existing.lastOutboundAt = incoming.lastOutboundAt
        existing.lastMessageDirection = incoming.lastMessageDirection
        existing.createdAt = incoming.createdAt
        existing.updatedAt = incoming.updatedAt
    }

    private func requireVisit() -> SiteVisit? {
        if siteVisit == nil {
            loadOrCreateVisit()
        }
        return siteVisit
    }

    private func seedBuiltInSiteVisitTypesIfNeeded() {
        let builtIns = SiteVisitType.builtInTemplates(
            companyId: companyId,
            deckBuilderEnabled: PermissionStore.shared.isFeatureEnabled("deck_builder")
        )
        let existingTypes = siteVisitTypesForCompany()
        var existingBySlug: [String: SiteVisitType] = [:]
        for type in existingTypes {
            existingBySlug[type.slug] = type
        }

        var didChange = false
        for builtIn in builtIns {
            if let existing = existingBySlug[builtIn.slug], existing.isSystemTemplate {
                var changedExisting = false
                if existing.name != builtIn.name {
                    existing.name = builtIn.name
                    changedExisting = true
                }
                if existing.descriptionText != builtIn.descriptionText {
                    existing.descriptionText = builtIn.descriptionText
                    changedExisting = true
                }
                if existing.isDefault != builtIn.isDefault {
                    existing.isDefault = builtIn.isDefault
                    changedExisting = true
                }
                if existing.sortOrder != builtIn.sortOrder {
                    existing.sortOrder = builtIn.sortOrder
                    changedExisting = true
                }
                if existing.fields != builtIn.fields {
                    existing.fields = builtIn.fields
                    changedExisting = true
                }
                didChange = didChange || changedExisting
            } else if existingBySlug[builtIn.slug] == nil {
                modelContext.insert(builtIn)
                didChange = true
            }
        }

        // Retire system templates we no longer ship (renamed slugs, or the deck
        // type when the deck builder is off) so old/inappropriate defaults stop
        // appearing. User-created types (isSystemTemplate == false) are untouched.
        let builtInSlugs = Set(builtIns.map(\.slug))
        for existing in existingTypes where existing.isSystemTemplate
            && existing.deletedAt == nil
            && !builtInSlugs.contains(existing.slug) {
            existing.deletedAt = Date()
            existing.updatedAt = Date()
            didChange = true
        }

        if didChange {
            saveContext()
        }
    }

    private func selectDefaultSiteVisitTypeIfNeeded() {
        guard selectedSiteVisitType == nil,
              checklistAnswers.isEmpty,
              let defaultType = siteVisitTypes.first(where: \.isDefault) ?? siteVisitTypes.first else {
            return
        }
        selectSiteVisitType(defaultType)
    }

    private func loadSelectedTypeFromChecklist() {
        reloadChecklistAnswers()
        guard let selectedTypeId = checklistAnswers.first?.siteVisitTypeId else {
            selectedSiteVisitType = nil
            return
        }
        selectedSiteVisitType = siteVisitTypes.first { $0.id == selectedTypeId }
    }

    private func siteVisitTypesForCompany() -> [SiteVisitType] {
        let targetCompanyId = companyId
        let descriptor = FetchDescriptor<SiteVisitType>(
            predicate: #Predicate<SiteVisitType> { type in
                type.companyId == targetCompanyId && type.deletedAt == nil
            }
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchChecklistAnswers(siteVisitId: String) -> [SiteVisitChecklistAnswer] {
        let descriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { answer in
                answer.siteVisitId == siteVisitId
            },
            sortBy: [
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func hydrateChecklistAnswersFromCapturedEvidence() {
        guard !checklistAnswers.isEmpty else { return }
        var didChange = false

        for answer in checklistAnswers where answer.isActive {
            guard shouldHydrateCapturedEvidence(for: answer) else { continue }
            guard let value = capturedEvidenceValue(for: answer) else { continue }
            guard value != answer.answerValue else { continue }
            answer.answerValue = value
            answer.updatedAt = Date()
            answer.needsSync = true
            didChange = true
        }

        if didChange {
            saveContext()
            reloadChecklistAnswers()
        }
    }

    private func shouldHydrateCapturedEvidence(for answer: SiteVisitChecklistAnswer) -> Bool {
        if !answer.isAnswered { return true }
        switch answer.kind {
        case .photo, .photoMarkup:
            return true
        case .checkbox, .yesNoNA, .shortText, .longText, .measurement, .deckDesign:
            return false
        }
    }

    private func capturedEvidenceValue(for answer: SiteVisitChecklistAnswer) -> SiteVisitChecklistValue? {
        switch answer.kind {
        case .photo, .photoMarkup:
            let ids = activeArtifacts
                .filter(\.pipesToProjectPhotos)
                .map(\.id)
            return ids.isEmpty ? nil : .artifacts(ids)
        case .measurement:
            let measurementText = activeArtifacts
                .filter(\.pipesToProjectMeasurements)
                .sorted { $0.capturedAt < $1.capturedAt }
                .compactMap { $0.body?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: "\n")
            return measurementText.isEmpty ? nil : .text(measurementText)
        case .deckDesign:
            guard let deckDesignId = activeArtifacts
                .first(where: \.pipesToProjectDeckDesign)?
                .deckDesignId else { return nil }
            return .deckDesign(deckDesignId)
        case .checkbox, .yesNoNA, .shortText, .longText:
            return nil
        }
    }

    private func autosavedNoteArtifact() -> SiteVisitCaptureArtifact? {
        guard let autosavedNoteArtifactId else { return nil }
        if let artifact = artifacts.first(where: { $0.id == autosavedNoteArtifactId }) {
            return artifact
        }

        let targetId = autosavedNoteArtifactId
        let descriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { artifact in
                artifact.id == targetId
            }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func combinedNotes() -> String? {
        let noteBodies = artifacts
            .filter { $0.isActive && $0.pipesToProjectNotes }
            .sorted { $0.capturedAt < $1.capturedAt }
            .compactMap(\.body)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !noteBodies.isEmpty else { return nil }
        return noteBodies.joined(separator: "\n\n")
    }

    private func saveContext() {
        do {
            try modelContext.save()
            errorMessage = nil
        } catch {
            errorMessage = "SAVE FAILED"
        }
    }
}

private extension Array where Element == SiteVisitChecklistAnswer {
    func sortedByChecklistOrder() -> [SiteVisitChecklistAnswer] {
        sorted { lhs, rhs in
            if lhs.sortOrder == rhs.sortOrder {
                return lhs.createdAt < rhs.createdAt
            }
            return lhs.sortOrder < rhs.sortOrder
        }
    }
}

private extension String {
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SiteVisitCaptureViewModelError: Error {
    case missingSiteVisit
}

private struct OpportunityAddressPatch: Encodable {
    let address: String?
    var latitude: Double? = nil
    var longitude: Double? = nil

    enum CodingKeys: String, CodingKey {
        case address
        case latitude
        case longitude
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        // Address always encodes (null clears it); coordinates only ride
        // along when a geocoded selection supplied them — never null out a
        // pin the web side set.
        try container.encode(address, forKey: .address)
        try container.encodeIfPresent(latitude, forKey: .latitude)
        try container.encodeIfPresent(longitude, forKey: .longitude)
    }
}
