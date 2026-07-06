//
//  UnifiedLogActivityViewModel.swift
//  OPS
//
//  State + save path for the ONE Log Activity capture that replaces
//  LogActivityViewModel, LeadLogActivitySheet's inline state, and
//  LogCallViewModel. Merges three behaviors that must not regress:
//
//   1. Target resolution (LogActivityViewModel) — an ActivityTarget the
//      operator picks from ActivityTargetLoader, or a brand-new lead created
//      inline when nothing matches.
//   2. Call-capture provenance + phone dedup (LogCallViewModel) — a locked
//      lead when the entry point already knows one (post-call), or a live
//      phone-number dedup against the candidate set (FAB / App Shortcut
//      capture), plus call_source/caller_number/call_started_at threaded
//      into the write.
//   3. Conditional field visibility (LeadLogActivitySheet) — direction only
//      for call/email, duration only for call/meeting, outcome for everything
//      but note — resolved to nil (not just hidden) when the section doesn't
//      apply, mirroring the exact show-rules the three legacy sheets used.
//
//  Every write goes through ActivityRepository.logActivity — the single
//  `activities` write path — never OpportunityRepository.logActivity
//  directly. Follow-up suggestions are surfaced from VoiceActivityParser but
//  NEVER auto-persisted; the operator must tap SET.
//

import Foundation
import SwiftData
import Speech
import Combine
import UIKit

@MainActor
final class UnifiedLogActivityViewModel: ObservableObject {

    // MARK: - Entry point

    /// Where the capture was opened from. Determines the initial target,
    /// lock state, default type, and (for `.postCall`) call provenance.
    enum Entry {
        /// Generic "Log Activity" FAB item — no target yet, operator picks
        /// one from the unified lead/client/job picker (or creates a lead).
        case genericFAB
        /// Opened from a lead's detail screen — target is fixed to that lead
        /// for the whole capture; the operator cannot repick it.
        case leadDetail(Opportunity)
        /// Operator returned to OPS after placing an in-app call to a known
        /// lead — target + call provenance are both fixed by the intent.
        case postCall(PendingOutboundCall)
        /// FAB "Log a call" / Siri / App Shortcut — no lead yet; the number
        /// dialed/received dedups against the candidate set as it's typed.
        case capture(CallCaptureSource)
    }

    let entry: Entry

    // MARK: - Target

    /// The current attach point. Starts at the entry point's resolved value
    /// and — when `isTargetLocked == false` — can be repicked via
    /// `ActivityTargetPickerView` or resolved from live phone dedup.
    @Published var target: ActivityTarget

    /// True when the operator must not repick the target (leadDetail,
    /// postCall — the entry point already knows the exact lead).
    let isTargetLocked: Bool

    /// The full candidate list for the unbound/FAB target picker.
    @Published var availableTargets: [ActivityTarget] = []

    // MARK: - Form state

    @Published var selectedType: ActivityType
    @Published var notesText: String = ""
    @Published var subject: String = ""
    @Published var direction: String = "outbound"   // "inbound" | "outbound"
    @Published var outcome: String = ""
    @Published var durationMinutes: Int = 0

    // MARK: - Call-capture facet (phone dedup + provenance)

    /// Contact name typed/auto-filled while resolving an unbound call target.
    @Published var contactName: String = ""
    /// Phone number typed/known for the call being logged.
    @Published var phoneNumber: String = ""
    /// The live-dedup match against the candidate set, when one exists.
    @Published var matchedLead: LeadPhoneMatch?
    @Published var isResolvingCandidates = false

    /// Authoritative lead id for the post-call path — carried straight from
    /// the recorded intent, independent of dedup, so the save always attaches
    /// to the exact lead that was called.
    private(set) var knownOpportunityId: String?
    /// Call start time captured by the entry point (post-call only). Threaded
    /// into `activities.call_started_at` for `.call` saves.
    private let callStartedAt: Date?

    private var candidates: [LeadPhoneMatch] = []
    private var wasContactNameAutoFilled = false

    // MARK: - New-lead creation (unbound target, no dedup match)

    @Published var isCreatingNewLead: Bool = false
    @Published var newLeadName: String = ""
    @Published var newLeadPhone: String = ""
    @Published var newLeadEmail: String = ""

    // MARK: - Voice

    @Published var speechManager = SpeechRecognitionManager()
    @Published var voiceDraft: ActivityDraft?
    @Published var hasParsedVoice: Bool = false
    @Published var ambiguousCandidates: [(opportunityId: String, contactName: String, score: Double)] = []

    /// A detected follow-up suggestion from the voice draft. Never
    /// auto-persisted — `setFollowUp()` only runs when the operator taps SET.
    @Published var suggestedFollowUp: (title: String, dueAt: Date)?

    // MARK: - Save state

    @Published var isSaving: Bool = false
    @Published var errorMessage: String?
    @Published var isSettingFollowUp: Bool = false
    @Published var followUpSetSuccessfully: Bool = false

    // MARK: - Private

    private var companyId: String?
    private var userId: String?
    private var modelContext: ModelContext?
    private var activityRepository: ActivityRepository?
    private var opportunityRepository: OpportunityRepository?
    private var cancellables = Set<AnyCancellable>()

    /// The last opportunity id an activity was successfully logged against —
    /// the resolution `setFollowUp()` targets, since a brand-new lead's id
    /// isn't known until `save()` creates it.
    private var resolvedOpportunityId: String?

    // MARK: - Init

    init(entry: Entry) {
        self.entry = entry

        switch entry {
        case .genericFAB:
            target = .unbound
            isTargetLocked = false
            selectedType = .call
            callStartedAt = nil

        case .leadDetail(let opportunity):
            target = .opportunity(opportunity)
            isTargetLocked = true
            selectedType = .call
            callStartedAt = nil

        case .postCall(let pending):
            target = .unbound   // resolved to `.opportunity` once enriched in `configure`
            isTargetLocked = true
            selectedType = .call
            direction = "outbound"          // ContactCard places outbound calls
            callStartedAt = pending.startedAt
            knownOpportunityId = pending.opportunityId
            contactName = pending.contactName ?? ""
            phoneNumber = pending.phoneNumber

        case .capture:
            target = .unbound
            isTargetLocked = false
            selectedType = .call
            direction = "inbound"           // FAB / Shortcut usually capture inbound
            callStartedAt = nil
        }

        speechManager.preferOnDeviceRecognition = true
        // `speechManager` is a nested ObservableObject — forward its changes
        // so live transcription + mic state re-render the sheet.
        speechManager.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Configure

    func configure(companyId: String, userId: String?, modelContext: ModelContext) {
        self.companyId = companyId
        self.userId = userId
        self.modelContext = modelContext
        self.activityRepository = ActivityRepository(companyId: companyId)
        self.opportunityRepository = OpportunityRepository(companyId: companyId)

        switch entry {
        case .genericFAB:
            loadTargets()
        case .leadDetail:
            break // target already resolved + locked in init
        case .postCall:
            Task { await enrichKnownLead() }
        case .capture:
            Task { await loadCandidates() }
            loadTargets()
        }
    }

    private func enrichKnownLead() async {
        guard let id = knownOpportunityId, let repo = opportunityRepository else { return }
        resolvedOpportunityId = id
        if let dto = try? await repo.fetchOne(id) {
            let model = dto.toModel()
            target = .opportunity(model)
            if contactName.trimmingCharacters(in: .whitespaces).isEmpty {
                contactName = model.contactName
            }
        }
    }

    /// Loads the unified lead/client/job candidate list backing
    /// `ActivityTargetPickerView` for the unbound entry points.
    func loadTargets() {
        guard let companyId, let modelContext else { return }
        availableTargets = ActivityTargetLoader.load(companyId: companyId, modelContext: modelContext)
    }

    private func loadCandidates() async {
        guard let repo = opportunityRepository else { return }
        isResolvingCandidates = true
        candidates = await repo.fetchLeadCandidates()
        isResolvingCandidates = false
        runDedup()
    }

    // MARK: - Call-facet: mode lock + live phone dedup

    /// True when the target is fixed by the entry point and must not be
    /// re-picked (leadDetail, postCall).
    var leadIsLocked: Bool { isTargetLocked }

    /// Instant, local dedup against the cached candidate set — mirrors
    /// `LogCallViewModel.runDedup()` exactly. No-ops when the target is
    /// locked or the type isn't a call/text capture.
    func runDedup() {
        guard !leadIsLocked else { return }
        let phone = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard !phone.isEmpty else {
            matchedLead = nil
            if wasContactNameAutoFilled { contactName = ""; wasContactNameAutoFilled = false }
            return
        }
        let match = OpportunityRepository.matchLead(phone: phone, candidates: candidates)
        matchedLead = match
        if let match {
            if contactName.trimmingCharacters(in: .whitespaces).isEmpty || wasContactNameAutoFilled {
                contactName = match.contactName
                wasContactNameAutoFilled = true
            }
        } else if wasContactNameAutoFilled {
            contactName = ""
            wasContactNameAutoFilled = false
        }
    }

    func applyPickedContact(name: String, phone: String) {
        contactName = name
        wasContactNameAutoFilled = false
        phoneNumber = phone
        runDedup()
    }

    /// Source recorded to `activities.call_source` for a `.call` save.
    private var resolvedSource: String? {
        switch entry {
        case .postCall:        return CallCaptureSource.postCallPrompt.rawValue
        case .capture(let s):  return s.rawValue
        case .genericFAB, .leadDetail: return nil
        }
    }

    // MARK: - Target selection (unbound / FAB path)

    /// Applies a target picked from `ActivityTargetPickerView`. No-ops when
    /// the target is locked.
    func selectTarget(_ picked: ActivityTarget) {
        guard !isTargetLocked else { return }
        target = picked
        if case .opportunity(let opp) = picked {
            resolvedOpportunityId = opp.id
        }
    }

    func clearTarget() {
        guard !isTargetLocked else { return }
        target = .unbound
        resolvedOpportunityId = nil
    }

    // MARK: - Conditional field gating (mirrors LeadLogActivitySheet)

    /// DIRECTION only applies to correspondence with an in/out sense.
    var showDirectionField: Bool {
        selectedType == .call || selectedType == .email
    }

    /// OUTCOME applies to everything except a plain note.
    var showOutcomeField: Bool {
        selectedType != .note
    }

    /// DURATION only applies to time-boxed activities.
    var showDurationField: Bool {
        selectedType == .call || selectedType == .meeting
    }

    // MARK: - Validation

    /// Whether `save()` has enough to resolve a target: the locked lead, an
    /// explicit pick, a live phone-dedup match, or a valid new-lead name.
    var canSave: Bool {
        guard !isSaving else { return false }
        if leadIsLocked { return true }
        if target.parentKey != nil { return true }
        if matchedLead != nil { return true }
        return !contactName.trimmingCharacters(in: .whitespaces).isEmpty
            && !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    // MARK: - Voice

    func toggleRecording() {
        do { try speechManager.toggleRecording() }
        catch { speechManager.state = .error(error.localizedDescription) }
    }

    /// Parses the finished transcription into an `ActivityDraft` — reuses
    /// `VoiceActivityParser` exactly as `LogActivityViewModel` does — then
    /// applies every field the draft carries, including the follow-up
    /// suggestion (new in this VM; the legacy loggers never surfaced one).
    func parseTranscription() {
        let text = speechManager.transcription
        guard !text.isEmpty else { return }

        let opportunityCandidates = availableTargets.compactMap { candidate -> (id: String, contactName: String)? in
            guard case .opportunity(let opp) = candidate else { return nil }
            return (id: opp.id, contactName: opp.contactName)
        }
        let draft = VoiceActivityParser.parse(transcription: text, opportunities: opportunityCandidates)

        voiceDraft = draft
        hasParsedVoice = true
        selectedType = draft.type

        if !draft.notes.isEmpty {
            notesText = draft.notes
        }

        if !leadIsLocked {
            switch draft.confidence {
            case .exact, .high:
                if let matchedId = draft.matchedOpportunityId,
                   let match = availableTargets.first(where: {
                       if case .opportunity(let opp) = $0 { return opp.id == matchedId }
                       return false
                   }) {
                    target = match
                    resolvedOpportunityId = matchedId
                }
            case .ambiguous:
                ambiguousCandidates = draft.ambiguousCandidates
            case .noMatch:
                if let parsedName = draft.parsedContactName {
                    isCreatingNewLead = true
                    newLeadName = parsedName
                }
            case .noContact:
                break
            }
        }

        if let dueAt = draft.suggestedFollowUpDueAt, let title = draft.suggestedFollowUpTitle {
            suggestedFollowUp = (title: title, dueAt: dueAt)
        }
    }

    func resolveAmbiguousMatch(opportunityId: String) {
        if let match = availableTargets.first(where: {
            if case .opportunity(let opp) = $0 { return opp.id == opportunityId }
            return false
        }) {
            target = match
            resolvedOpportunityId = opportunityId
        }
        ambiguousCandidates = []
    }

    /// Fold the finished transcription into the notes body, then clear the
    /// source buffer so a second flush path can't re-append the same text.
    /// Also runs the parse so type/follow-up/target inference always fires,
    /// mirroring `LogCallViewModel.applyTranscription` + `parseTranscription`.
    func applyTranscription() {
        parseTranscription()
        let text = speechManager.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        speechManager.transcription = ""
    }

    /// Stop any in-flight dictation (audio session teardown). Idempotent.
    func teardownVoice() {
        if speechManager.state == .recording || speechManager.state == .stopping {
            speechManager.stopRecording()
        }
    }

    // MARK: - Save

    func save() async -> Bool {
        guard let companyId, let activityRepository, canSave else { return false }

        if speechManager.state == .recording {
            speechManager.stopRecording()
        }

        isSaving = true
        errorMessage = nil

        do {
            let resolvedTarget = try await resolveTarget(companyId: companyId)

            let planned = plannedLog(target: resolvedTarget)

            _ = try await activityRepository.logActivity(
                target: resolvedTarget,
                type: planned.type,
                subject: planned.subject,
                body: planned.body,
                direction: planned.direction,
                outcome: planned.outcome,
                durationMinutes: planned.durationMinutes,
                callSource: planned.callSource,
                callerNumber: planned.callerNumber,
                callStartedAt: planned.callStartedAt,
                createdBy: planned.createdBy
            )

            if case .opportunity(let opp) = resolvedTarget {
                resolvedOpportunityId = opp.id
                opp.lastActivityAt = Date()
                try? modelContext?.save()
            }

            target = resolvedTarget

            UINotificationFeedbackGenerator().notificationOccurred(.success)
            NotificationCenter.default.post(
                name: Notification.Name("LeadActivityLoggedSuccess"),
                object: nil,
                userInfo: resolvedOpportunityId.map { ["leadId": $0] } ?? [:]
            )

            isSaving = false
            return true
        } catch {
            errorMessage = simplifyError(error)
            isSaving = false
            return false
        }
    }

    /// Resolves the target to write against: the locked lead, an explicit
    /// pick, a live phone-dedup match, a late network re-check, or a
    /// brand-new lead created inline (in that priority order — mirrors
    /// LogCallViewModel.save + LogActivityViewModel.save combined).
    private func resolveTarget(companyId: String) async throws -> ActivityTarget {
        // Locked target (leadDetail / enriched postCall) always wins.
        if isTargetLocked, target.parentKey != nil {
            return target
        }
        // Post-call before enrichment completes: fall back to the known id.
        if let known = knownOpportunityId, let repo = opportunityRepository {
            if case .opportunity = target { return target }
            if let dto = try? await repo.fetchOne(known) {
                return .opportunity(dto.toModel())
            }
        }
        // Explicit pick from the target picker or voice match.
        if target.parentKey != nil {
            return target
        }
        // Live phone-dedup match.
        if let match = matchedLead, let repo = opportunityRepository,
           let dto = try? await repo.fetchOne(match.id) {
            return .opportunity(dto.toModel())
        }
        // Final network re-check catches a lead created since open.
        if !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty,
           let repo = opportunityRepository,
           let lateMatch = await repo.findByContactPhone(phoneNumber),
           let dto = try? await repo.fetchOne(lateMatch.id) {
            return .opportunity(dto.toModel())
        }
        // No target resolvable — create a new lead from whatever contact
        // info was captured (name from typing/voice, phone from the call
        // facet).
        guard let repo = opportunityRepository else {
            throw ActivityLogError.noResolvableTarget
        }
        let trimmedName = (isCreatingNewLead ? newLeadName : contactName)
            .trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else {
            throw ActivityLogError.noResolvableTarget
        }
        let resolvedPhone = isCreatingNewLead ? newLeadPhone : phoneNumber
        let resolvedEmail = isCreatingNewLead ? newLeadEmail : ""
        let dto = CreateOpportunityDTO(
            companyId: companyId,
            contactName: trimmedName,
            contactEmail: resolvedEmail.isEmpty ? nil : resolvedEmail,
            contactPhone: resolvedPhone.isEmpty ? nil : resolvedPhone,
            description: nil,
            estimatedValue: nil,
            source: newLeadSource,
            quoteDeliveryMethod: nil
        )
        let created = try await repo.create(dto)
        let model = created.toModel()
        modelContext?.insert(model)
        try? modelContext?.save()

        NotificationCenter.default.post(
            name: Notification.Name("LeadCreatedSuccess"),
            object: nil,
            userInfo: ["leadId": model.id]
        )
        return .opportunity(model)
    }

    /// `source` tag stamped on an inline-created lead — distinguishes a
    /// phone-dial-driven create from a voice/typed one for later analysis.
    private var newLeadSource: String {
        switch entry {
        case .capture, .postCall: return "phone"
        default: return "log_activity"
        }
    }

    // MARK: - Planned log (pure — unit-testable without network/SwiftData)

    /// Everything `save()` will write to the `activities` table, derived
    /// purely from current @Published state plus the already-resolved
    /// target. Kept separate from the network call so field gating and call
    /// provenance threading are testable without a live SupabaseClient.
    struct PlannedLog: Equatable {
        let type: ActivityType
        let subject: String?
        let body: String?
        let direction: String?
        let outcome: String?
        let durationMinutes: Int?
        let callSource: String?
        let callerNumber: String?
        let callStartedAt: Date?
        let createdBy: String?
    }

    /// `subject` is always nil (or the operator-typed override) — the DB
    /// trigger `trg_activities_default_subject` backfills a per-type label.
    /// Direction/duration are gated on `showDirectionField`/`showDurationField`
    /// so a hidden section never leaks a stale value into the write (mirrors
    /// `LeadLogActivitySheet`'s resolvedDirection/resolvedDuration). Call
    /// provenance is only threaded for `.call` saves.
    func plannedLog(target: ActivityTarget? = nil) -> PlannedLog {
        let isCall = selectedType == .call
        return PlannedLog(
            type: selectedType,
            subject: subject.trimmingCharacters(in: .whitespaces).isEmpty ? nil : subject,
            body: notesText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notesText,
            direction: showDirectionField ? direction : nil,
            outcome: showOutcomeField ? outcome : nil,
            durationMinutes: showDurationField ? durationMinutes : nil,
            callSource: isCall ? resolvedSource : nil,
            callerNumber: isCall ? PhoneNumber.normalize(phoneNumber) : nil,
            callStartedAt: isCall ? callStartedAt : nil,
            createdBy: userId
        )
    }

    // MARK: - Follow-up

    /// FollowUpType the operator's activity type maps to — call/email/meeting
    /// carry through 1:1; anything else (note, etc.) is `.custom` since
    /// `FollowUpType` has no note-shaped case.
    private var mappedFollowUpType: FollowUpType {
        switch selectedType {
        case .call:    return .call
        case .email:   return .email
        case .meeting: return .meeting
        default:       return .custom
        }
    }

    /// Persists the accepted follow-up suggestion via the SAME path
    /// `LeadDetailViewModel.addFollowUp`/`OpportunityRepository.createFollowUp`
    /// uses. Never called automatically — only when the operator taps SET.
    /// No-ops (returns false) when there's no suggestion or no resolvable
    /// opportunity id (follow_ups only carries an opportunity/client parent
    /// today, and dueAt/title come straight from the suggestion).
    @discardableResult
    func setFollowUp() async -> Bool {
        guard let suggestion = suggestedFollowUp,
              let companyId,
              let opportunityId = resolvedOpportunityId
        else { return false }

        isSettingFollowUp = true
        defer { isSettingFollowUp = false }

        let dto = Self.buildFollowUpDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            suggestion: suggestion,
            type: mappedFollowUpType
        )

        do {
            _ = try await opportunityRepository?.createFollowUp(dto)
            followUpSetSuccessfully = true
            suggestedFollowUp = nil
            return true
        } catch {
            errorMessage = simplifyError(error)
            return false
        }
    }

    /// Pure DTO builder for the follow-up write — unit-testable without a
    /// live SupabaseClient. `dueAt`/`title` come straight from the accepted
    /// suggestion; `reminderAt`/`assignedTo` are left nil (parity with
    /// `LeadDetailViewModel.addFollowUp`'s defaults for an unattended set).
    static func buildFollowUpDTO(
        companyId: String,
        opportunityId: String,
        suggestion: (title: String, dueAt: Date),
        type: FollowUpType
    ) -> CreateFollowUpDTO {
        CreateFollowUpDTO(
            companyId: companyId,
            opportunityId: opportunityId,
            title: suggestion.title,
            description: nil,
            type: type.rawValue,
            dueAt: SupabaseDate.format(suggestion.dueAt),
            reminderAt: nil,
            assignedTo: nil
        )
    }

    // MARK: - Errors

    enum ActivityLogError: Error {
        case noResolvableTarget
    }

    private func simplifyError(_ error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP TO RETRY"
        }
        if description.contains("permission") || description.contains("denied") {
            return "PERMISSION DENIED"
        }
        return "COULD NOT LOG — TAP TO RETRY"
    }
}
