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

enum SiteVisitCompletionFailure: Equatable {
    case missingEvidence
    case requiredAnswers
    case persistence
}

enum SiteVisitCompletionResult: Equatable {
    case committed(SiteVisitPersistenceCoordinator.CommitResult)
    case notCommitted(SiteVisitCompletionFailure)

    var isCommitted: Bool {
        if case .committed = self { return true }
        return false
    }
}

enum SiteVisitSaveResult: Equatable {
    case committed
    case draftSaved
    case committedStageUpdatePending
    case committedStageUpdateFailed
    case notCommitted(SiteVisitCompletionFailure)

    var visitWasCommitted: Bool {
        switch self {
        case .committed, .draftSaved, .committedStageUpdatePending, .committedStageUpdateFailed: return true
        case .notCommitted: return false
        }
    }
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

    enum EntryIntent { case newVisit, resume(visitId: String) }
    private let entryIntent: EntryIntent
    @Published private(set) var pendingChecklistValues: [String: SiteVisitChecklistValue] = [:]
    private var checklistSaveTask: Task<Void, Never>?
    var flushIdentityEdits: (() -> Void)?

    private let companyId: String
    private let userId: String?
    /// The console, picker and deck editor inherit this same owned context.
    let modelContext: ModelContext
    private let persistenceCoordinator: SiteVisitPersistenceCoordinator
    var readStageSnapshot: SiteVisitStageTransport.ReadSnapshot = SiteVisitStageTransport.readSnapshot
    @Published private(set) var stageSnapshot: SiteVisitStageSnapshot?
    private var stageSnapshotGeneration = 0
    private var autosavedNoteArtifactId: String?
    private(set) var pendingDeckCreation: DeckDesign?
    var validateDeckSave: () throws -> Void = {}
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

    init(
        opportunity: Opportunity?,
        companyId: String,
        userId: String?,
        modelContext: ModelContext,
        persistenceCoordinator: SiteVisitPersistenceCoordinator? = nil,
        entryIntent: EntryIntent = .newVisit
    ) {
        self.entryIntent = entryIntent
        self.currentOpportunity = opportunity.map(Self.detachedOpportunitySnapshot)
        self.companyId = companyId
        self.userId = userId
        let baseCoordinator = persistenceCoordinator ?? SiteVisitPersistenceCoordinator(
                modelContext: modelContext,
                companyId: companyId
            )
        let captureCoordinator = baseCoordinator.isolatedSession()
        self.persistenceCoordinator = captureCoordinator
        self.modelContext = captureCoordinator.modelContext
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
        (SiteVisitCaptureCompletionPolicy.canComplete(artifacts) || hasAnsweredChecklistEvidence)
            && missingRequiredChecklistAnswers.isEmpty
    }

    /// Anything the operator would lose if they closed without finishing —
    /// drives the "are you sure?" close confirmation.
    var hasCapturedAnything: Bool {
        SiteVisitContentPolicy.hasContent(visit: siteVisit, artifacts: artifacts,
            answers: checklistAnswers, drafts: identityDraft.map { [$0] } ?? [])
            || !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !measurementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pendingChecklistValues.values.contains { $0 != .empty }
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
        if let currentOpportunity {
            return currentOpportunity.deckDesignTitle
        }
        return "\(visitDisplayName == "Unlinked visit" ? "Site visit" : visitDisplayName) deck"
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

        let candidates = openVisits()
        if case .resume(let requestedId) = entryIntent,
           let exact = candidates.first(where: { $0.id.lowercased() == requestedId.lowercased() }) {
            siteVisit = exact
        } else if let opportunity = currentOpportunity {
            siteVisit = candidates.first { $0.opportunityId == opportunity.id } ?? createVisit()
        } else {
            // NEW VISIT is an intent, not a recency guess. Preserve prior work
            // and offer explicit resume even if it was captured seconds ago.
            let prior = candidates.filter { $0.opportunityId == nil }
            let summaries = visitContentSummaries(prior)
            // No automatic deletion: an apparently empty visit may still own
            // a recoverable camera journal that has not attached artifacts yet.
            resumableVisit = prior.filter { summaries[$0.id]?.hasContent == true }
                .max { (summaries[$0.id]?.lastActivity ?? $0.createdAt)
                    < (summaries[$1.id]?.lastActivity ?? $1.createdAt) }
            siteVisit = createVisit()
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

    /// Re-reads company templates after the Settings cover closes. A blank
    /// checklist can adopt the edited definition; once the operator has answered
    /// anything, the visit-time snapshot remains untouched.
    func refreshSiteVisitTypesAfterSettings() {
        let selectedId = selectedSiteVisitType?.id
        reloadSiteVisitTypes()

        guard let selectedId,
              let refreshedType = siteVisitTypes.first(where: { $0.id == selectedId }) else {
            if let fallback = siteVisitTypes.first(where: \.isDefault) ?? siteVisitTypes.first {
                selectSiteVisitType(fallback)
            }
            return
        }

        selectedSiteVisitType = refreshedType
        guard !checklistAnswers.contains(where: { $0.isActive && $0.isAnswered }),
              let visit = siteVisit else {
            return
        }

        let existing = fetchChecklistAnswers(siteVisitId: visit.id).filter(\.isActive)
        let replacements = SiteVisitChecklistAnswer.makeAnswers(
            for: refreshedType,
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            createdBy: userId
        )
        guard persistSiteVisitChanges({
            let now = Date()
            for answer in existing {
                answer.deletedAt = now
                answer.updatedAt = now
                answer.needsSync = true
            }
            for answer in replacements { modelContext.insert(answer) }
        }) else { return }
        reloadChecklistAnswers()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func selectSiteVisitType(_ type: SiteVisitType) {
        guard let visit = requireVisit(), flushChecklistEdits() else { return }

        let existing = fetchChecklistAnswers(siteVisitId: visit.id)
        let activeExisting = existing.filter(\.isActive)
        if activeExisting.contains(where: { $0.siteVisitTypeId == type.id }) {
            selectedSiteVisitType = type
            checklistAnswers = activeExisting.sortedByChecklistOrder()
            return
        }

        let answers = SiteVisitChecklistAnswer.makeAnswers(
            for: type,
            siteVisitId: visit.id,
            companyId: companyId,
            opportunityId: activeOpportunityId,
            createdBy: userId
        )
        guard persistSiteVisitChanges({
            let now = Date()
            for answer in activeExisting {
                answer.deletedAt = now
                answer.updatedAt = now
                answer.needsSync = true
            }
            for answer in answers {
                modelContext.insert(answer)
            }
        }) else {
            return
        }

        selectedSiteVisitType = type
        reloadChecklistAnswers()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func updateChecklistAnswer(
        _ answer: SiteVisitChecklistAnswer,
        value: SiteVisitChecklistValue
    ) {
        guard answer.answerValue != value else { return }
        guard persistSiteVisitChanges({
            answer.answerValue = value
            answer.updatedAt = Date()
            answer.needsSync = true
        }) else { return }
        reloadChecklistAnswers()
    }

    func checklistValue(for answer: SiteVisitChecklistAnswer) -> SiteVisitChecklistValue {
        pendingChecklistValues[answer.id] ?? answer.answerValue
    }

    func bufferChecklistAnswer(_ answer: SiteVisitChecklistAnswer, value: SiteVisitChecklistValue) {
        switch answer.kind {
        case .shortText, .longText, .measurement:
            pendingChecklistValues[answer.id] = value
            checklistSaveTask?.cancel()
            checklistSaveTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                guard !Task.isCancelled else { return }
                self?.flushChecklistEdits()
            }
        default: updateChecklistAnswer(answer, value: value)
        }
    }

    @discardableResult
    func flushChecklistEdits() -> Bool {
        checklistSaveTask?.cancel()
        guard !pendingChecklistValues.isEmpty else { return true }
        let pending = pendingChecklistValues
        let changes = checklistAnswers.compactMap { answer -> (SiteVisitChecklistAnswer, SiteVisitChecklistValue)? in
            guard answer.isActive, let value = pending[answer.id], value != answer.answerValue else { return nil }
            return (answer, value)
        }
        guard !changes.isEmpty else { pendingChecklistValues = [:]; return true }
        guard persistSiteVisitChanges({
            let now = Date()
            for (answer, value) in changes {
                answer.answerValue = value
                answer.updatedAt = now
                answer.needsSync = true
            }
        }) else { return false }
        pendingChecklistValues = [:]
        return true
    }

    /// Flush before navigation/backgrounding. A failed write retains buffers.
    @discardableResult
    func preserveDraft() -> Bool {
        errorMessage = nil
        flushIdentityEdits?()
        guard errorMessage == nil else { return false }
        guard flushChecklistEdits() else { return false }
        autosaveNote()
        guard errorMessage == nil else { return false }
        if !measurementDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { addMeasurement() }
        return errorMessage == nil
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
        guard persistSiteVisitChanges({
            modelContext.insert(answer)
        }) else { return }
        reloadChecklistAnswers()
    }

    var captureOwner: StagedCaptureOwner? {
        guard let visit = siteVisit, let userId, !userId.isEmpty else { return nil }
        return StagedCaptureOwner(companyID: companyId, userID: userId, contextID: visit.id)
    }

    /// Camera/recovery replay is keyed by stable staged-item identity. The
    /// journal keeps custody until this exact artifact + outbox save succeeds.
    func attachStagedPhotos(_ batch: StagedCaptureBatch) -> Bool {
        guard let owner = captureOwner, owner == batch.owner, let visit = siteVisit else {
            errorMessage = "PHOTO VISIT CHANGED"
            return false
        }
        do {
            let ids = batch.items.map { $0.id.lowercased() }
            let existing = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(
                predicate: #Predicate { ids.contains($0.id) }))
            guard existing.allSatisfy({ $0.companyId.lowercased() == companyId.lowercased()
                && $0.siteVisitId.lowercased() == visit.id.lowercased() }) else {
                errorMessage = "PHOTO VISIT CHANGED"
                return false
            }
            let savedIds = Set(existing.map { $0.id.lowercased() })
            let additions = batch.items.filter { !savedIds.contains($0.id.lowercased()) }
            if !additions.isEmpty {
                guard persistSiteVisitChanges({
                    for item in additions {
                        modelContext.insert(SiteVisitCaptureArtifact(id: item.id, siteVisitId: visit.id,
                            companyId: companyId, opportunityId: activeOpportunityId, kind: .photo,
                            source: .camera, title: "Site photo", localAssetURL: item.localURL,
                            capturedAt: item.capturedAt, createdBy: userId))
                    }
                }) else { return false }
            }
            reloadArtifacts()
            hydrateChecklistAnswersFromCapturedEvidence()
            return true
        } catch {
            errorMessage = "PHOTOS NOT SAVED · RETRY"
            return false
        }
    }

    func discoverInterruptedPhotoVisits() async {
        guard let userId else { return }
        let activeId = activeSiteVisitId
        do {
            let ids = try await DurableCaptureStore.shared.pendingContextIDs(companyID: companyId, userID: userId)
            guard !Task.isCancelled, activeSiteVisitId == activeId else { return }
            let candidates = openVisits().filter { ids.contains($0.id.lowercased()) && $0.id != activeId }
            if let latest = candidates.max(by: { ($0.updatedAt ?? $0.createdAt) < ($1.updatedAt ?? $1.createdAt) }) {
                if resumableVisit == nil || (latest.updatedAt ?? latest.createdAt)
                    >= (resumableVisit?.updatedAt ?? resumableVisit?.createdAt ?? .distantPast) {
                    resumableVisit = latest
                }
            }
        } catch {
            errorMessage = "PHOTO RECOVERY NEEDS ATTENTION · REOPEN VISIT"
        }
    }

    func recoverStagedPhotos() async {
        guard let owner = captureOwner else { return }
        do {
            let batches = try await DurableCaptureStore.shared.recover(owner: owner)
            for batch in batches {
                guard !Task.isCancelled, captureOwner == owner else { return }
                guard attachStagedPhotos(batch) else { return }
                try await DurableCaptureStore.shared.acknowledge(batchID: batch.id,
                    itemIDs: Set(batch.items.map(\.id)))
            }
        } catch {
            errorMessage = "PHOTO RECOVERY PENDING · REOPEN VISIT"
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
        guard persistSiteVisitChanges({
            modelContext.insert(artifact)
        }) else { return }
        noteDraft = ""
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
    }

    func autosaveNote(source: SiteVisitCaptureSource = .keyboard) {
        guard let visit = requireVisit() else { return }
        let trimmed = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty {
            if let artifact = autosavedNoteArtifact() {
                guard persistSiteVisitChanges({
                    artifact.deletedAt = Date()
                    artifact.updatedAt = Date()
                    artifact.needsSync = true
                }) else { return }
                autosavedNoteArtifactId = nil
                reloadArtifacts()
            }
            return
        }

        if let artifact = autosavedNoteArtifact(), artifact.isActive {
            guard artifact.body != trimmed else { return }
            guard persistSiteVisitChanges({
                artifact.body = trimmed
                artifact.updatedAt = Date()
                artifact.needsSync = true
            }) else { return }
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
        guard persistSiteVisitChanges({
            modelContext.insert(artifact)
        }) else { return }
        autosavedNoteArtifactId = artifact.id
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

        let existing = autosavedNoteArtifact()
        guard persistSiteVisitChanges({
            if let artifact = existing, artifact.isActive {
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
        }) else { return }

        autosavedNoteArtifactId = nil
        noteDraft = ""
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
        guard persistSiteVisitChanges({
            modelContext.insert(artifact)
        }) else { return }
        measurementDraft = ""
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

    @discardableResult
    func attachDeckDesign(_ deckDesign: DeckDesign) -> Bool {
        guard let visit = requireVisit() else { return false }

        // Idempotent on reopen: one active artifact per design. Continuing a
        // design (checklist EDIT, or a lead deck carried into the visit) must
        // not stack duplicate DECK artifacts, inflate the summary count, or
        // hand conversion the same design twice.
        let alreadyAttached = activeArtifacts.contains {
            $0.kind == .deckDesign && $0.deckDesignId == deckDesign.id
        }
        guard persistSiteVisitChanges({
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
            }), deckAnswer.answerValue != .deckDesign(deckDesign.id) {
                deckAnswer.answerValue = .deckDesign(deckDesign.id)
                deckAnswer.updatedAt = Date()
                deckAnswer.needsSync = true
            }
        }) else { return false }
        reloadArtifacts()
        reloadChecklistAnswers()
        hydrateChecklistAnswersFromCapturedEvidence()
        return true
    }

    /// Called by the actual picker host, before it opens the editor. A failed
    /// save keeps the pending design for the next DECK tap instead of opening
    /// an editor for an uncommitted row or discarding its captured geometry.
    func saveDeckForCapture(_ incoming: DeckDesign) -> DeckDesign? {
        let design: DeckDesign
        if let owner = incoming.modelContext, owner !== modelContext {
            let id = incoming.id
            guard let local = try? modelContext.fetch(FetchDescriptor<DeckDesign>(predicate: #Predicate { $0.id == id })).first else {
                errorMessage = "DECK NOT SAVED · RETRY"
                return nil
            }
            design = local
        } else { design = incoming }
        pendingDeckCreation = design
        if design.modelContext == nil { modelContext.insert(design) }
        // Blank/scan constructors default to needsSync=false. Once a visit
        // artifact references this row, its first delivery is required too.
        if design.lastSyncedAt == nil && !design.needsSync { design.markForSync() }
        do {
            try validateDeckSave()
            if modelContext.hasChanges { try modelContext.save() }
            guard attachDeckDesign(design) else { return nil }
            pendingDeckCreation = nil
            return design
        } catch {
            errorMessage = "DECK NOT SAVED · RETRY"
            return nil
        }
    }

    func setIncluded(_ artifact: SiteVisitCaptureArtifact, included: Bool) {
        guard artifact.includedInProjectReview != included else { return }
        guard persistSiteVisitChanges({
            artifact.includedInProjectReview = included
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }) else { return }
        reloadArtifacts()
    }

    /// Edits a committed note/transcript in place so its stable artifact id,
    /// capture order, project inclusion, and offline sync history are preserved.
    @discardableResult
    func updateNoteArtifact(
        _ artifact: SiteVisitCaptureArtifact,
        body: String
    ) -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              artifact.isActive,
              artifact.pipesToProjectNotes,
              artifacts.contains(where: { $0.id == artifact.id }) else {
            return false
        }

        if artifact.body == trimmed { return true }
        guard persistSiteVisitChanges({
            artifact.body = trimmed
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }) else { return false }
        reloadArtifacts()
        hydrateChecklistAnswersFromCapturedEvidence()
        return true
    }

    @discardableResult
    func saveMarkup(
        _ artifact: SiteVisitCaptureArtifact,
        renderedAssetURL: String
    ) -> Bool {
        // Markup writes can replace bytes at the same local URL. An explicit
        // render save is new media even when its URL has not changed.
        return persistSiteVisitChanges(revisedMediaArtifactIds: [artifact.id.lowercased()]) {
            artifact.kind = .annotatedPhoto
            artifact.renderedAssetURL = renderedAssetURL
            artifact.updatedAt = Date()
            artifact.needsSync = true
        }
    }

    func completeVisit(stageCommand: SiteVisitStageCommand? = nil) async -> SiteVisitCompletionResult {
        guard preserveDraft() else { return .notCommitted(.persistence) }
        guard missingRequiredChecklistAnswers.isEmpty else {
            errorMessage = "COMPLETE REQUIRED FIELDS"
            return .notCommitted(.requiredAnswers)
        }
        guard canComplete, let visit = requireVisit() else {
            errorMessage = "CAPTURE SOMETHING FIRST"
            return .notCommitted(.missingEvidence)
        }

        isCompleting = true
        defer { isCompleting = false }
        do {
            let result = try persistenceCoordinator.commit(completing: visit, stageCommand: stageCommand) {
                visit.status = .completed
                visit.completedAt = Date()
                visit.notes = combinedNotes()
                visit.updatedAt = Date()
                visit.needsSync = true
            }
            errorMessage = nil
            return .committed(result)
        } catch {
            errorMessage = "VISIT NOT SAVED"
            return .notCommitted(.persistence)
        }
    }

    /// Bug (site-visit report) — completing a visit must NOT convert the lead
    /// to WON. Save the visit (the server completion command owns its timeline
    /// activity) and,
    /// when a lead is bound, move it to the operator-chosen stage (defaulting
    /// to QUALIFYING via `SiteVisitStageDefault`). Conversion stays a separate,
    /// explicit CREATE PROJECT action. The typed result keeps a committed visit
    /// distinct from a later stage-move failure.
    func prepareStageSnapshot() async {
        stageSnapshotGeneration += 1
        let generation = stageSnapshotGeneration
        stageSnapshot = nil
        guard let opportunityId = currentOpportunity?.id else { return }
        do {
            let snapshot = try await readStageSnapshot(opportunityId)
            guard !Task.isCancelled, generation == stageSnapshotGeneration,
                  currentOpportunity?.id == opportunityId,
                  snapshot.isSupported, snapshot.opportunityId.lowercased() == opportunityId.lowercased(),
                  snapshot.actorId.lowercased() == userId?.lowercased(),
                  snapshot.companyId.lowercased() == companyId.lowercased() else { return }
            stageSnapshot = snapshot
        } catch {
            // Local save is independent. Missing capability/revision preserves
            // a parked command requiring a new deliberate stage decision.
        }
    }

    func saveVisit(movingLeadTo stage: PipelineStage) async -> SiteVisitSaveResult {
        var decision = makeStageDecision()
        decision?.targetStage = stage
        return await saveVisit(stageDecision: decision)
    }

    func makeStageDecision() -> SiteVisitStageDecision? {
        guard let opportunity = currentOpportunity else { return nil }
        let snapshot = stageSnapshot.flatMap { snapshot -> SiteVisitStageSnapshot? in
            guard snapshot.isSupported,
                  snapshot.opportunityId.lowercased() == opportunity.id.lowercased(),
                  snapshot.actorId.lowercased() == userId?.lowercased(),
                  snapshot.companyId.lowercased() == companyId.lowercased(),
                  PipelineStage(rawValue: snapshot.stage) != nil else { return nil }
            return snapshot
        }
        let current = snapshot.flatMap { PipelineStage(rawValue: $0.stage) } ?? opportunity.stage
        return SiteVisitStageDecision(opportunityId: opportunity.id.lowercased(), currentStage: current,
            snapshot: snapshot, targetStage: SiteVisitStageDefault.defaultStage(current: current))
    }

    func saveVisit(stageDecision decision: SiteVisitStageDecision?) async -> SiteVisitSaveResult {
        guard preserveDraft() else { return .notCommitted(.persistence) }
        guard canComplete else { return .draftSaved }
        var command: SiteVisitStageCommand?
        if let decision, let opportunity = currentOpportunity, let visit = siteVisit,
           decision.opportunityId == opportunity.id.lowercased(),
           !decision.currentStage.isTerminal, decision.targetStage != decision.currentStage,
           SiteVisitStageCommand.allowedStages.contains(decision.targetStage.rawValue) {
            command = SiteVisitStageCommand(commandId: UUID().uuidString.lowercased(),
                companyId: companyId.lowercased(), actorId: userId?.lowercased() ?? "",
                siteVisitId: visit.id.lowercased(), opportunityId: opportunity.id.lowercased(),
                targetStage: decision.targetStage.rawValue, snapshot: decision.snapshot)
        }
        let completion = await completeVisit(stageCommand: command)
        guard case .committed = completion else {
            if case .notCommitted(let failure) = completion { return .notCommitted(failure) }
            return .notCommitted(.persistence)
        }
        guard let command else { return .committed }
        return command.canDeliver ? .committedStageUpdatePending : .committedStageUpdateFailed
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
            // met on a teammate's device. The lead's VALUE is deliberately not
            // carried — the packet syncs to a column OPS-Web renders ungated,
            // so money is resolved at render time from the local opportunity.
            contactName: currentOpportunity?.displayContactName ?? identityDraft?.contactName.trimmedNilIfEmpty,
            companyName: identityDraft?.clientName.trimmedNilIfEmpty,
            recordedByUserId: visit.createdBy
        )
    }

    func reassignVisit(to opportunity: Opportunity, identityCommittedAt: Date? = nil) {
        guard opportunity.id != currentOpportunity?.id else { return }
        let opportunity = Self.detachedOpportunitySnapshot(opportunity)
        guard let visit = requireVisit() else { return }
        let priorAddress = currentOpportunity?.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visitAddress = visit.address?.trimmingCharacters(in: .whitespacesAndNewlines)
        let priorDraftAddress = identityDraft?.address.trimmingCharacters(in: .whitespacesAndNewlines)
        let previousOpportunity = currentOpportunity

        let completingVisit = visit.status == .completed ? visit : nil
        guard persistSiteVisitChanges(completing: completingVisit, {
            currentOpportunity = opportunity
            // Binding to a lead IS the commit, whether that lead was just
            // created from this draft or picked from search. Only the
            // auto-create path used to stamp it, so every draft an operator
            // attached to an EXISTING lead stayed permanently uncommitted —
            // and recovery, which reads that stamp, kept reporting finished
            // captures as unsent (bug fe497fb9). The parameter survives as the
            // clock seam the auto-create tests pin.
            bindIdentityDraft(
                to: opportunity,
                committedAt: identityCommittedAt ?? currentDate()
            )
            visit.opportunityId = opportunity.id
            if visitAddress == nil || visitAddress?.isEmpty == true || visitAddress == priorAddress {
                visit.address = opportunity.address
            }
            visit.updatedAt = Date()
            visit.needsSync = true

            // The identity draft's address is the highest-priority source for
            // `captureAddress`, so it must follow the reassignment too — but only
            // when it was empty or still matched the previous lead.
            if let draft = identityDraft,
               priorDraftAddress == nil || priorDraftAddress?.isEmpty == true || priorDraftAddress == priorAddress {
                draft.address = opportunity.address ?? ""
                draft.touch()
            }

            for artifact in childArtifacts(of: visit.id) {
                artifact.opportunityId = opportunity.id
                artifact.updatedAt = Date()
                artifact.needsSync = true
            }

            for answer in fetchChecklistAnswers(siteVisitId: visit.id) {
                answer.opportunityId = opportunity.id
                answer.updatedAt = Date()
                answer.needsSync = true
            }
        }) else {
            currentOpportunity = previousOpportunity
            return
        }

        reloadArtifacts()
        reloadChecklistAnswers()
    }

    func bindClient(_ client: Client) {
        guard let draft = requireIdentityDraft() else { return }
        guard persistSiteVisitChanges({
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
            if let visit = siteVisit {
                visit.address = draft.address.trimmedNilIfEmpty ?? visit.address
                visit.updatedAt = Date()
                visit.needsSync = true
            }
        }) else { return }
        objectWillChange.send()
    }

    /// Clears the linked lead/client and wipes the identity fields — the X on the
    /// search box. Captured photos/notes/measurements are kept; only identity and
    /// the binding are reset.
    func clearIdentitySelection() {
        guard let draft = requireIdentityDraft() else { return }
        let previousOpportunity = currentOpportunity
        guard persistSiteVisitChanges({
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
                visit.updatedAt = Date()
                visit.needsSync = true
                for answer in fetchChecklistAnswers(siteVisitId: visit.id) {
                    answer.opportunityId = nil
                    answer.updatedAt = Date()
                    answer.needsSync = true
                }
            }
            for artifact in artifacts {
                artifact.opportunityId = nil
                artifact.updatedAt = Date()
                artifact.needsSync = true
            }
        }) else {
            currentOpportunity = previousOpportunity
            return
        }
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
            let upserted = try upsertClientFromIdentityDraft(
                draft,
                clientName: clientName,
                dataController: dataController
            )
            let client = upserted.client
            upsertedClient = client
            // A retry can resolve a previously saved client whose create is
            // still pending or stopped. Local existence is not server proof.
            if upserted.createState == .rejected {
                return handOffLeadDelivery(client, draft: draft, offline: false)
            }
            if upserted.createState == .inFlight {
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

            // `reassignVisit` binds the draft to the new lead (opportunityId,
            // clientId), stamps `lastCommittedAt`, repoints the visit and every
            // child artifact/answer, and commits the whole thing through the
            // persistence coordinator in one transaction. The clock comes from
            // the injectable seam so the tests can pin it.
            reassignVisit(to: opportunity, identityCommittedAt: currentDate())
            errorMessage = nil
            return .created(opportunity)
        } catch {
            _ = persistSiteVisitChanges {
                draft.touch()
            }

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
            isOffline: ClientServerVisibility.isLikelyOfflineError
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
        _ = persistSiteVisitChanges {
            draft.clientId = client.id
            draft.touch()
        }
        errorMessage = nil
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
        let readContext = ModelContext(modelContext.container)
        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == visitId },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let draft = try? readContext.fetch(draftDescriptor).first,
              let opportunityId = draft.opportunityId?.trimmedNilIfEmpty else { return }

        let opportunityDescriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { $0.id == opportunityId }
        )
        guard let delivered = try? readContext.fetch(opportunityDescriptor).first else { return }
        // Transfer scalar lead/binding data; never move a registered row from
        // the reader into this capture's context or replace an unsaved buffer.
        reassignVisit(to: delivered, identityCommittedAt: draft.lastCommittedAt)
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
        // Canonicalize comma-less hand-typed addresses at the persistence
        // boundary ("972 Lyall St Esquimalt" → "972 Lyall St, Esquimalt") so
        // the server's comma-splitting derive_project_name produces the same
        // street-line project name iOS previews.
        let canonicalAddress = ProjectAutoNamer.canonicalizedAddress(address)
        let emails = additionalEmailsText
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == ";" })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard draft.searchText != searchText || draft.clientName != clientName
            || draft.contactName != contactName || draft.preferredEmail != preferredEmail
            || draft.additionalEmails != emails || draft.phoneNumber != phoneNumber
            || draft.address != canonicalAddress || draft.notes != notes else { return }
        guard persistSiteVisitChanges({
            draft.searchText = searchText
            draft.clientName = clientName
            draft.contactName = contactName
            draft.preferredEmail = preferredEmail
            draft.additionalEmails = emails
            draft.phoneNumber = phoneNumber
            draft.address = canonicalAddress
            draft.notes = notes
            draft.touch()

            if let normalizedAddress = canonicalAddress.trimmedNilIfEmpty {
                if let visit = siteVisit, visit.address != normalizedAddress {
                    visit.address = normalizedAddress
                    visit.updatedAt = Date()
                    visit.needsSync = true
                }
                if currentOpportunity?.address?.trimmedNilIfEmpty == nil {
                    currentOpportunity?.address = normalizedAddress
                }
            }
        }) else { return }
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
        let organization = contact.organizationName.trimmingCharacters(in: .whitespaces)
        let email = contact.emailAddresses.first
            .map { ($0.value as String).trimmingCharacters(in: .whitespaces) }
        let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespaces)
        // A picked postal address is a commit (like an autocomplete selection),
        // so it lands on the visit as well as the draft. No geocode here, so
        // coordinates stay nil.
        let composedAddress = Self.composeAddress(from: contact)

        // Every write goes through the coordinator so the visit's server row is
        // queued with the local change in one transaction — a bare context save
        // would leave the imported address stranded on this device.
        _ = persistSiteVisitChanges {
            if !fullName.isEmpty { draft.contactName = fullName }
            if !organization.isEmpty { draft.clientName = organization }
            if let email, !email.isEmpty { draft.preferredEmail = email }
            if let phone, !phone.isEmpty { draft.phoneNumber = phone }

            if let composedAddress {
                let canonical = ProjectAutoNamer.canonicalizedAddress(composedAddress)
                draft.address = canonical
                if let visit = siteVisit {
                    visit.address = canonical.trimmedNilIfEmpty
                    visit.updatedAt = Date()
                    visit.needsSync = true
                }
            }

            draft.touch()
        }
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
        guard persistSiteVisitChanges({
            visit.address = normalized
            visit.updatedAt = Date()
            visit.needsSync = true
            identityDraft?.address = normalized ?? ""
            identityDraft?.touch()
            currentOpportunity?.updatedAt = Date()
            if persistToLead, currentOpportunity != nil {
                currentOpportunity?.address = normalized
            }
        }) else { return }
        objectWillChange.send()

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
            _ = upsertLocalOpportunity(updated)
            currentOpportunity = Self.detachedOpportunitySnapshot(updated)
            objectWillChange.send()
            saveLocalContext()
        } catch {
            errorMessage = "ADDRESS SAVE FAILED"
        }
    }

    /// Open (not completed, not cancelled) visits for this company, newest first.
    private func openVisits() -> [SiteVisit] {
        let company = companyId.lowercased()
        let user = userId?.lowercased() ?? ""
        let isOpen = #Predicate<SiteVisit> {
            $0.companyId == company && $0.completedAt == nil && $0.deletedAt == nil
        }
        let isAssigned = #Predicate<SiteVisit> {
            $0.createdBy == user || $0.assignedTo == user || $0.assigneeIds.contains(user)
        }
        let predicate = #Predicate<SiteVisit> { isOpen.evaluate($0) && isAssigned.evaluate($0) }
        let descriptor = FetchDescriptor<SiteVisit>(predicate: predicate,
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? modelContext.fetch(descriptor)) ?? []).filter { $0.status != .cancelled }
    }

    private func createVisit() -> SiteVisit? {
        let visit = SiteVisit(
            opportunityId: currentOpportunity?.id,
            companyId: companyId,
            status: .scheduled,
            assigneeIds: userId.map { [$0] } ?? [],
            createdBy: userId
        )
        visit.address = currentOpportunity?.address
        visit.assignedTo = userId
        guard persistSiteVisitChanges({
            modelContext.insert(visit)
        }) else { return nil }
        return visit
    }

    private struct ContentSummary {
        let hasContent: Bool
        let lastActivity: Date
    }

    private func visitContentSummaries(_ visits: [SiteVisit]) -> [String: ContentSummary] {
        let ids = visits.map(\.id)
        guard !ids.isEmpty else { return [:] }
        do {
            let artifacts = try modelContext.fetch(FetchDescriptor<SiteVisitCaptureArtifact>(
                predicate: #Predicate { ids.contains($0.siteVisitId) }))
            let answers = try modelContext.fetch(FetchDescriptor<SiteVisitChecklistAnswer>(
                predicate: #Predicate { ids.contains($0.siteVisitId) }))
            let drafts = try modelContext.fetch(FetchDescriptor<SiteVisitIdentityDraft>(
                predicate: #Predicate { ids.contains($0.siteVisitId) }))
            let artifactsByVisit = Dictionary(grouping: artifacts, by: \.siteVisitId)
            let answersByVisit = Dictionary(grouping: answers, by: \.siteVisitId)
            let draftsByVisit = Dictionary(grouping: drafts, by: \.siteVisitId)
            return Dictionary(uniqueKeysWithValues: visits.map { visit in
                let captures = artifactsByVisit[visit.id] ?? []
                let checks = answersByVisit[visit.id] ?? []
                let identities = draftsByVisit[visit.id] ?? []
                let dates = [visit.updatedAt ?? visit.createdAt]
                    + captures.map { $0.updatedAt ?? $0.capturedAt }
                    + checks.map { $0.updatedAt ?? $0.createdAt }
                    + identities.map(\.updatedAt)
                return (visit.id, ContentSummary(hasContent: SiteVisitContentPolicy.hasContent(
                    visit: visit, artifacts: captures, answers: checks, drafts: identities),
                    lastActivity: dates.max() ?? visit.createdAt))
            })
        } catch {
            // An unreadable child table can never prove a packet empty.
            return Dictionary(uniqueKeysWithValues: visits.map {
                ($0.id, ContentSummary(hasContent: true, lastActivity: $0.updatedAt ?? $0.createdAt))
            })
        }
    }

    /// Operator-initiated discard of the ACTIVE visit. Soft-deletes captured
    /// artifacts and checklist answers (so the deletion syncs), marks the visit
    /// cancelled (excluded from future open-visit lookups), and clears state.
    func discardVisit() {
        guard let visit = siteVisit else { return }
        guard persistSiteVisitChanges({
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
            for draft in childDrafts(of: visit.id) where draft.deletedAt == nil {
                draft.deletedAt = now
                draft.touch()
            }
            visit.status = .cancelled
            visit.updatedAt = now
            visit.needsSync = true
        }) else { return }

        artifacts = []
        checklistAnswers = []
        noteDraft = ""
        measurementDraft = ""
        autosavedNoteArtifactId = nil
    }

    /// Switches the active visit to the surfaced resumable one, discarding the
    /// empty visit the console opened on.
    func resumeResumableVisit() {
        guard let resume = resumableVisit, preserveDraft() else { return }
        siteVisit = resume
        noteDraft = ""
        measurementDraft = ""
        autosavedNoteArtifactId = nil
        pendingChecklistValues = [:]
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
            address: currentOpportunity?.address ?? visit.address ?? "",
            createdBy: userId
        )
        guard persistSiteVisitChanges({
            modelContext.insert(draft)
        }) else { return }
        identityDraft = draft
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

    private func bindIdentityDraft(
        to opportunity: Opportunity,
        committedAt: Date
    ) {
        guard let draft = requireIdentityDraft() else { return }
        draft.opportunityId = opportunity.id
        draft.clientId = opportunity.clientId
        draft.lastCommittedAt = committedAt
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

    private func upsertClientFromIdentityDraft(
        _ draft: SiteVisitIdentityDraft,
        clientName: String,
        dataController: DataController
    ) throws -> SiteVisitIdentityClientStore.Result {
        var saved: SiteVisitIdentityClientStore.Result?
        try persistenceCoordinator.commit {
            saved = try SiteVisitIdentityClientStore.upsert(draft: draft,
                clientName: clientName, companyId: companyId, context: modelContext)
        }
        // Never return a newly inserted model after a transaction rollback.
        guard let saved else { throw SiteVisitCaptureViewModelError.localSaveFailed }
        if saved.queuedWork { dataController.syncEngine.notifyDurableOperationQueued() }
        return saved
    }


    private func upsertLocalOpportunity(_ incoming: Opportunity) -> Opportunity {
        let opportunityId = incoming.id
        let descriptor = FetchDescriptor<Opportunity>(
            predicate: #Predicate<Opportunity> { opportunity in
                opportunity.id == opportunityId
            }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.apply(incoming)
            return existing
        }
        modelContext.insert(incoming)
        return incoming
    }

    private static func detachedOpportunitySnapshot(_ incoming: Opportunity) -> Opportunity {
        let snapshot = Opportunity(id: incoming.id, companyId: incoming.companyId,
            contactName: incoming.contactName, stage: incoming.stage)
        snapshot.apply(incoming)
        return snapshot
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
                // The default is company-owned configuration. Reopening Site Visit
                // must never replace the administrator's selection with a built-in default.
                if existing.sortOrder != builtIn.sortOrder {
                    existing.sortOrder = builtIn.sortOrder
                    changedExisting = true
                }
                let reconciledFields = SiteVisitTypeTemplateReconciler.reconciledFields(
                    existing: existing.fields,
                    canonical: builtIn.fields
                )
                if existing.fields != reconciledFields {
                    existing.fields = reconciledFields
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
            saveLocalContext()
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
        var changes: [(SiteVisitChecklistAnswer, SiteVisitChecklistValue)] = []

        for answer in checklistAnswers where answer.isActive {
            guard shouldHydrateCapturedEvidence(for: answer) else { continue }
            guard let value = capturedEvidenceValue(for: answer) else { continue }
            guard value != answer.answerValue else { continue }
            changes.append((answer, value))
        }

        if !changes.isEmpty,
           persistSiteVisitChanges({
               for (answer, value) in changes {
                   answer.answerValue = value
                   answer.updatedAt = Date()
                   answer.needsSync = true
               }
           }) {
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

    @discardableResult
    private func persistSiteVisitChanges(
        completing visit: SiteVisit? = nil,
        revisedMediaArtifactIds: Set<String> = [],
        _ mutation: () throws -> Void
    ) -> Bool {
        do {
            _ = try persistenceCoordinator.commit(
                completing: visit,
                revisedMediaArtifactIds: revisedMediaArtifactIds,
                mutation: mutation
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = "SAVE FAILED"
            return false
        }
    }

    private func saveLocalContext() {
        do {
            try modelContext.save()
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
    case localSaveFailed
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
