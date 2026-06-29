//
//  SiteVisitCaptureViewModel.swift
//  OPS
//
//  Local-first capture packet orchestration for field site visits.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

@MainActor
final class SiteVisitCaptureViewModel: ObservableObject {
    @Published private(set) var siteVisit: SiteVisit?
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

    private let companyId: String
    private let userId: String?
    private let modelContext: ModelContext
    private var autosavedNoteArtifactId: String?

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
            // Unlinked start (FAB): NEVER silently reopen a prior visit. Sweep
            // away empty abandoned unlinked visits, surface any that still hold
            // evidence so the operator can deliberately resume, and begin on a
            // clean visit. This kills the cross-site data-mixing bug.
            let priorUnlinked = openVisits().filter { $0.opportunityId == nil }
            let withContent = priorUnlinked.filter { visitHasContent($0) }
            let empties = priorUnlinked.filter { !visitHasContent($0) }
            resumableVisit = withContent.sorted { $0.createdAt > $1.createdAt }.first
            for empty in empties { hardDeleteVisit(empty) }
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
        return true
    }

    func projectPayload(projectTitle: String) -> SiteVisitProjectPayload? {
        guard let visit = siteVisit, let opportunityId = activeOpportunityId else { return nil }
        return SiteVisitProjectPayloadBuilder.payload(
            siteVisitId: visit.id,
            opportunityId: opportunityId,
            projectTitle: projectTitle,
            address: identityDraft?.address.trimmedNilIfEmpty ?? visit.address ?? currentOpportunity?.address,
            artifacts: artifacts,
            checklistAnswers: checklistAnswers
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
        if draft.clientName.trimmedNilIfEmpty == nil {
            draft.clientName = client.name
        }
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

    func createLeadFromIdentityDraft(dataController: DataController) async -> Opportunity? {
        if let currentOpportunity {
            return currentOpportunity
        }

        guard let draft = requireIdentityDraft() else { return nil }
        guard let clientName = draft.clientName.trimmedNilIfEmpty ?? draft.contactName.trimmedNilIfEmpty else {
            errorMessage = "CLIENT NAME REQUIRED"
            return nil
        }
        guard draft.preferredEmail.trimmedNilIfEmpty != nil || draft.phoneNumber.trimmedNilIfEmpty != nil else {
            errorMessage = "CONTACT REQUIRED"
            return nil
        }

        isCommittingIdentity = true
        defer { isCommittingIdentity = false }

        do {
            let client = try await upsertClientFromIdentityDraft(
                draft,
                clientName: clientName,
                dataController: dataController
            )
            try await createMissingSubContacts(
                from: draft,
                client: client,
                dataController: dataController
            )

            let contactName = draft.contactName.trimmedNilIfEmpty ?? clientName
            let dto = CreateOpportunityDTO(
                companyId: companyId,
                title: "\(contactName) site visit",
                contactName: contactName,
                contactEmail: draft.preferredEmail.trimmedNilIfEmpty,
                contactPhone: draft.phoneNumber.trimmedNilIfEmpty,
                description: draft.notes.trimmedNilIfEmpty,
                address: draft.address.trimmedNilIfEmpty,
                source: ClientLeadAutocreate.schemaAllowedSource,
                priority: ClientLeadAutocreate.schemaAllowedPriority,
                assignedTo: userId,
                clientId: client.id
            )
            let created = try await OpportunityRepository(companyId: companyId).create(dto)
            let opportunity = upsertLocalOpportunity(created.toModel())

            draft.opportunityId = opportunity.id
            draft.clientId = client.id
            draft.lastCommittedAt = Date()
            draft.touch()
            reassignVisit(to: opportunity)
            saveContext()
            return opportunity
        } catch {
            // The capture packet and identity draft are already persisted
            // locally — only the server-side lead create failed. Reassure
            // instead of alarm: the operator retries CREATE LEAD when signal
            // returns, with nothing re-entered and nothing lost. (Opportunity
            // has no offline write queue, so this cannot auto-retry on
            // reconnect — that would require opportunity sync infrastructure.)
            draft.touch()
            saveContext()
            errorMessage = isLikelyOfflineError(error)
                ? "NO SIGNAL · DRAFT SAVED · RETRY WHEN ONLINE"
                : "LEAD CREATE FAILED · DRAFT SAVED · RETRY"
            return nil
        }
    }

    private func isLikelyOfflineError(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost, .dataNotAllowed:
                return true
            default:
                break
            }
        }
        let text = String(describing: error).lowercased()
        return text.contains("offline")
            || text.contains("network")
            || text.contains("connection")
            || text.contains("timed out")
    }

    func updateIdentityDraft(
        searchText: String,
        clientName: String,
        contactName: String,
        preferredEmail: String,
        additionalEmailsText: String,
        phoneNumber: String,
        address: String,
        notes: String
    ) {
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
        draft.address = address
        draft.notes = notes
        draft.touch()

        if let normalizedAddress = address.trimmedNilIfEmpty {
            siteVisit?.address = normalizedAddress
            if currentOpportunity?.address?.trimmedNilIfEmpty == nil {
                currentOpportunity?.address = normalizedAddress
            }
        }
        saveContext()
        objectWillChange.send()
    }

    func updateVisitAddress(_ rawAddress: String, persistToLead: Bool) async {
        let trimmed = rawAddress.trimmingCharacters(in: .whitespacesAndNewlines)
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
            let patch = OpportunityAddressPatch(address: normalized)
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
            clientName: currentOpportunity?.displayContactName ?? "",
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
        if draft.clientName.trimmedNilIfEmpty == nil {
            draft.clientName = opportunity.displayContactName
        }
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
    ) async throws -> Client {
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
            return fetchClient(id: existing.id) ?? existing
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
            return created
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
        return fallback
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

    enum CodingKeys: String, CodingKey {
        case address
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(address, forKey: .address)
    }
}
