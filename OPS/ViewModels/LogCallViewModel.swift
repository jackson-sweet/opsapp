//
//  LogCallViewModel.swift
//  OPS
//
//  State + save path for the around-call capture sheet (iOS feature 154cb8a3).
//  Resolves the lead (attach to an existing one matched by phone, or create a
//  new `source:"phone"` lead), then logs a `call` activity with provenance
//  through the existing data layer. Optional in-app voice note (on-device
//  Speech) dictates into the note body.
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
    @Published var matchedOpportunity: Opportunity?
    @Published var contactName: String = ""
    @Published var phoneNumber: String = ""
    @Published var showContactPicker = false

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
    private var cancellables = Set<AnyCancellable>()

    init(mode: Mode) {
        self.mode = mode
        switch mode {
        case .postCall(let pending):
            // ContactCard places OUTBOUND calls; default accordingly.
            direction = "outbound"
            callStartedAt = pending.startedAt
        case .capture:
            // FAB / Shortcut most often capture an inbound call or a fresh lead.
            direction = "inbound"
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
        resolveInitialLead()
        loadContextualStrings()
    }

    private func resolveInitialLead() {
        switch mode {
        case .postCall(let pending):
            phoneNumber = pending.phoneNumber
            if let oid = pending.opportunityId, let context = modelContext {
                let all = (try? context.fetch(FetchDescriptor<Opportunity>())) ?? []
                matchedOpportunity = all.first { $0.id == oid && $0.deletedAt == nil }
            }
            if matchedOpportunity == nil { runDedup() } // fall back to phone match
            contactName = matchedOpportunity?.contactName ?? pending.contactName ?? ""
        case .capture:
            break
        }
    }

    /// True when the lead is fixed by the entry point and must not be re-picked.
    var leadIsLocked: Bool {
        if case .postCall = mode { return matchedOpportunity != nil }
        return false
    }

    // MARK: - Dedup

    /// Re-run the phone→lead match. Called as the operator edits the number or
    /// picks a contact in capture mode.
    func runDedup() {
        guard let repo = repository, let context = modelContext,
              !phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty else {
            matchedOpportunity = nil
            return
        }
        matchedOpportunity = repo.findByContactPhone(phoneNumber, in: context)
        if let match = matchedOpportunity, contactName.trimmingCharacters(in: .whitespaces).isEmpty {
            contactName = match.contactName
        }
    }

    func applyPickedContact(name: String, phone: String) {
        contactName = name
        phoneNumber = phone
        runDedup()
    }

    /// Whether the save will attach to an existing lead vs create a new one.
    var willAttach: Bool { matchedOpportunity != nil }

    // MARK: - Voice note

    func toggleVoice() {
        do { try speech.toggleRecording() }
        catch { speech.state = .error(error.localizedDescription) }
    }

    /// Fold the finished transcription into the note body (accumulates across
    /// multiple dictation passes).
    func applyTranscription() {
        let text = speech.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        bodyText = bodyText.isEmpty ? text : bodyText + "\n" + text
    }

    private func loadContextualStrings() {
        var strings: [String] = []
        if !contactName.isEmpty { strings.append(contactName) }
        if let context = modelContext {
            let opps = (try? context.fetch(FetchDescriptor<Opportunity>())) ?? []
            strings += opps.map { $0.contactName }
        }
        speech.contextualStrings = Array(Set(strings)).prefix(100).map { String($0) }
    }

    // MARK: - Validation

    var canSave: Bool {
        guard !isSaving else { return false }
        if leadIsLocked { return true }
        return matchedOpportunity != nil
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

            if let existing = matchedOpportunity {
                opportunityId = existing.id
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
                let model = created.toModel()
                modelContext?.insert(model)
                try? modelContext?.save()
                matchedOpportunity = model
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

            matchedOpportunity?.lastActivityAt = Date()
            try? modelContext?.save()

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
        let name = (matchedOpportunity?.contactName ?? contactName)
            .trimmingCharacters(in: .whitespaces)
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
