//
//  LogCallViewModel.swift
//  OPS
//
//  State + save path for the around-call capture sheet (iOS feature 154cb8a3).
//
//  Post-call mode attaches to the EXACT lead that was called (the opportunityId
//  is authoritative — carried straight through to logActivity, which writes
//  against an opportunity_id string and needs no local model). Capture mode
//  (FAB / App Shortcut) dedups the number against the network candidate set and
//  attaches to a match, or creates a new `source:"phone"` lead. Optional in-app
//  voice note dictates (on-device) into the note body.
//
//  Opportunities are network-only (never in SwiftData), so dedup fetches the
//  candidate set once on open and matches locally as the operator types, with a
//  final network re-check before creating to avoid duplicates.
//

import Foundation
import SwiftData
import Speech
import Combine

@MainActor
final class LogCallViewModel: ObservableObject {

    enum Mode {
        case postCall(PendingOutboundCall)   // returned after an in-app call to a known lead
        case capture(CallCaptureSource)      // FAB / App Shortcut — no lead yet
    }

    let mode: Mode

    // MARK: - Lead resolution
    @Published var matchedLead: LeadPhoneMatch?
    @Published var contactName: String = ""
    @Published var phoneNumber: String = ""
    @Published var showContactPicker = false
    @Published var isResolving = false

    /// Authoritative id for the post-call path — set from the recorded intent,
    /// independent of any local/display lookup so we always attach to the lead
    /// that was actually called.
    private(set) var knownOpportunityId: String?
    /// Display-only stage label for the locked lead (enriched async).
    @Published var knownStageName: String?

    // MARK: - Form
    @Published var direction: String          // "inbound" | "outbound"
    @Published var outcome: String = ""
    @Published var durationText: String = ""
    @Published var bodyText: String = ""

    // MARK: - Voice note
    @Published var speech = SpeechRecognitionManager()

    // MARK: - Save
    @Published var isSaving = false
    @Published var errorMessage: String?

    // MARK: - Private
    private var companyId: String?
    private var userId: String?
    private var modelContext: ModelContext?
    private var repository: OpportunityRepository?
    private let callStartedAt: Date?
    private var candidates: [LeadPhoneMatch] = []
    private var wasNameAutoFilled = false
    private var cancellables = Set<AnyCancellable>()

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .postCall(let pending):
            direction = "outbound"               // ContactCard places outbound calls
            callStartedAt = pending.startedAt
            knownOpportunityId = pending.opportunityId
            contactName = pending.contactName ?? ""
            phoneNumber = pending.phoneNumber
        case .capture:
            direction = "inbound"                // FAB / Shortcut usually capture inbound
            callStartedAt = nil
        }
        speech.preferOnDeviceRecognition = true
        // `speech` is a nested ObservableObject — forward its changes so the
        // live transcription + mic state re-render the sheet.
        speech.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Setup

    func setup(companyId: String, userId: String?, modelContext: ModelContext) {
        self.companyId = companyId
        self.userId = userId
        self.modelContext = modelContext
        self.repository = OpportunityRepository(companyId: companyId)

        if leadIsLocked {
            // Post-call: lead is fixed by id. Enrich the display (name/stage)
            // without gating attach on it.
            Task { await enrichKnownLead() }
        } else {
            // Capture: load the dedup candidate set once, then match locally.
            Task { await loadCandidates() }
        }
    }

    /// True when the lead is fixed by the entry point and must not be re-picked.
    var leadIsLocked: Bool {
        if case .postCall = mode { return knownOpportunityId != nil }
        return false
    }

    private func enrichKnownLead() async {
        guard let id = knownOpportunityId, let repo = repository else { return }
        if let dto = try? await repo.fetchOne(id) {
            knownStageName = PipelineStage(rawValue: dto.stage)?.displayName
            if contactName.trimmingCharacters(in: .whitespaces).isEmpty {
                contactName = dto.contactName ?? ""
            }
        }
    }

    private func loadCandidates() async {
        guard let repo = repository else { return }
        isResolving = true
        candidates = await repo.fetchLeadCandidates()
        isResolving = false
        runDedup()
    }

    // MARK: - Dedup (instant, local against cached candidates)

    func runDedup() {
        guard !leadIsLocked else { return }
        let phone = phoneNumber.trimmingCharacters(in: .whitespaces)
        guard !phone.isEmpty else {
            matchedLead = nil
            if wasNameAutoFilled { contactName = ""; wasNameAutoFilled = false }
            return
        }
        let match = OpportunityRepository.matchLead(phone: phone, candidates: candidates)
        matchedLead = match
        if let match {
            // Auto-fill the name from the match when the operator hasn't typed
            // their own (or only inherited a prior auto-fill).
            if contactName.trimmingCharacters(in: .whitespaces).isEmpty || wasNameAutoFilled {
                contactName = match.contactName
                wasNameAutoFilled = true
            }
        } else if wasNameAutoFilled {
            // A previously auto-filled name must not ride onto a new, unmatched
            // number (which would mislabel the new lead).
            contactName = ""
            wasNameAutoFilled = false
        }
    }

    func applyPickedContact(name: String, phone: String) {
        contactName = name
        wasNameAutoFilled = false
        phoneNumber = phone
        runDedup()
    }

    /// Whether the save will attach to an existing lead vs create a new one.
    var willAttach: Bool { leadIsLocked || matchedLead != nil }

    // MARK: - Voice note

    func toggleVoice() {
        do { try speech.toggleRecording() }
        catch { speech.state = .error(error.localizedDescription) }
    }

    /// Fold the finished transcription into the note body, then clear the source
    /// buffer so a second flush path can't re-append the same text.
    func applyTranscription() {
        let text = speech.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        bodyText = bodyText.isEmpty ? text : bodyText + "\n" + text
        speech.transcription = ""
    }

    /// Stop any in-flight dictation (audio session teardown). Idempotent.
    func teardown() {
        if speech.state == .recording || speech.state == .stopping {
            speech.stopRecording()
        }
    }

    // MARK: - Validation

    var canSave: Bool {
        guard !isSaving else { return false }
        if leadIsLocked { return true }
        return matchedLead != nil
            || !contactName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var resolvedSource: String {
        switch mode {
        case .postCall:        return CallCaptureSource.postCallPrompt.rawValue
        case .capture(let s):  return s.rawValue
        }
    }

    // MARK: - Save

    func save() async -> Bool {
        guard let companyId, let repo = repository, canSave else { return false }

        // Flush any in-flight dictation into the body first.
        if speech.state == .recording {
            speech.stopRecording()
            applyTranscription()
        }

        isSaving = true
        errorMessage = nil

        do {
            let opportunityId: String
            var createdNewLead = false

            if let known = knownOpportunityId {
                // Post-call: attach to the exact lead that was called.
                opportunityId = known
            } else if let match = matchedLead {
                opportunityId = match.id
            } else if let lateMatch = await repo.findByContactPhone(phoneNumber) {
                // Final network re-check catches a lead created since open.
                opportunityId = lateMatch.id
            } else {
                let trimmedName = contactName.trimmingCharacters(in: .whitespaces)
                let dto = CreateOpportunityDTO(
                    companyId: companyId,
                    contactName: trimmedName,
                    contactPhone: phoneNumber.isEmpty ? nil : phoneNumber,
                    source: "phone",
                    assignedTo: userId
                )
                let created = try await repo.create(dto)
                opportunityId = created.id
                createdNewLead = true
            }

            let detailVM = LeadDetailViewModel(opportunityId: opportunityId, companyId: companyId)
            let duration = Int(durationText.trimmingCharacters(in: .whitespaces))

            try await detailVM.logActivity(
                type: .call,
                subject: defaultSubject(),
                body: bodyText.isEmpty ? nil : bodyText,
                direction: direction,
                outcome: outcome.isEmpty ? nil : outcome,
                durationMinutes: duration,
                callSource: resolvedSource,
                callerNumber: PhoneNumber.normalize(phoneNumber),
                callStartedAt: callStartedAt
            )

            if createdNewLead {
                NotificationCenter.default.post(
                    name: Notification.Name("LeadCreatedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunityId]
                )
            }
            NotificationCenter.default.post(
                name: Notification.Name("LeadActivityLoggedSuccess"),
                object: nil,
                userInfo: ["leadId": opportunityId]
            )

            isSaving = false
            return true
        } catch {
            errorMessage = simplifyError(error)
            isSaving = false
            return false
        }
    }

    private func defaultSubject() -> String {
        let name = contactName.trimmingCharacters(in: .whitespaces)
        let who = name.isEmpty ? "lead" : name
        return direction == "inbound" ? "Inbound call from \(who)" : "Call with \(who)"
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
