//
//  LogActivityViewModel.swift
//  OPS
//
//  State management for the Log Activity quick-capture sheet.
//  Coordinates speech recognition, voice parsing, opportunity loading, and save.
//

import Foundation
import SwiftData
import Speech

@MainActor
class LogActivityViewModel: ObservableObject {

    // MARK: - Form State

    @Published var selectedType: ActivityType = .call
    @Published var selectedOpportunity: Opportunity?
    @Published var notesText: String = ""
    @Published var direction: String = "outbound"  // "inbound" or "outbound"
    @Published var outcome: String = ""
    @Published var durationMinutes: Int = 0
    @Published var showMetadata: Bool = false

    // MARK: - Opportunity Picker State

    @Published var opportunitySearchText: String = ""
    @Published var showOpportunityPicker: Bool = false
    @Published var activeOpportunities: [Opportunity] = []

    // MARK: - Inline Create Lead State

    @Published var isCreatingNewLead: Bool = false
    @Published var newLeadName: String = ""
    @Published var newLeadPhone: String = ""
    @Published var newLeadEmail: String = ""

    // MARK: - Voice State

    @Published var speechManager = SpeechRecognitionManager()
    @Published var voiceDraft: ActivityDraft?
    @Published var hasParsedVoice: Bool = false
    @Published var ambiguousCandidates: [(opportunityId: String, contactName: String, score: Double)] = []

    // MARK: - Save State

    @Published var isSaving: Bool = false
    @Published var saveError: String?

    // MARK: - Private

    private var repository: OpportunityRepository?
    private var companyId: String?
    private var userId: String?
    private var modelContext: ModelContext?

    // MARK: - Setup

    func setup(companyId: String, userId: String, modelContext: ModelContext) {
        self.companyId = companyId
        self.userId = userId
        self.modelContext = modelContext
        self.repository = OpportunityRepository(companyId: companyId)
        loadActiveOpportunities()
        loadContextualStrings()
    }

    // MARK: - Opportunity Loading

    private func loadActiveOpportunities() {
        guard let modelContext else { return }
        // Fetch all opportunities, then filter client-side for non-terminal stages.
        // #Predicate with PipelineStage enum is unreliable — safer to filter in-memory.
        let descriptor = FetchDescriptor<Opportunity>()
        do {
            let all = try modelContext.fetch(descriptor)
            activeOpportunities = all
                .filter { !$0.stage.isTerminal }
                .sorted { ($0.lastActivityAt ?? $0.createdAt) > ($1.lastActivityAt ?? $1.createdAt) }
        } catch {
            activeOpportunities = []
        }
    }

    var filteredOpportunities: [Opportunity] {
        guard !opportunitySearchText.isEmpty else { return activeOpportunities }
        let search = opportunitySearchText.lowercased()
        return activeOpportunities.filter {
            $0.contactName.lowercased().contains(search)
            || ($0.jobDescription?.lowercased().contains(search) ?? false)
            || ($0.contactEmail?.lowercased().contains(search) ?? false)
        }
    }

    // MARK: - Contextual Strings for Speech

    private func loadContextualStrings() {
        var strings: [String] = []

        // Active opportunity contact names
        strings += activeOpportunities.map { $0.contactName }

        // Team member names
        if let modelContext {
            let userDescriptor = FetchDescriptor<User>()
            if let users = try? modelContext.fetch(userDescriptor) {
                strings += users.compactMap { user in
                    let full = [user.firstName, user.lastName].joined(separator: " ")
                    return full.trimmingCharacters(in: .whitespaces).isEmpty ? nil : full
                }
            }
        }

        speechManager.contextualStrings = Array(Set(strings)).prefix(100).map { String($0) }
    }

    // MARK: - Voice Recording

    func toggleRecording() {
        do {
            try speechManager.toggleRecording()
        } catch {
            speechManager.state = .error(error.localizedDescription)
        }
    }

    /// Call after speech recognition completes to parse the transcription
    func parseTranscription() {
        let text = speechManager.transcription
        guard !text.isEmpty else { return }

        let opportunities = activeOpportunities.map { (id: $0.id, contactName: $0.contactName) }
        let draft = VoiceActivityParser.parse(transcription: text, opportunities: opportunities)

        voiceDraft = draft
        hasParsedVoice = true

        // Apply parsed data to form fields
        selectedType = draft.type

        if !draft.notes.isEmpty {
            notesText = draft.notes
        }

        switch draft.confidence {
        case .exact, .high:
            if let matchedId = draft.matchedOpportunityId {
                selectedOpportunity = activeOpportunities.first { $0.id == matchedId }
            }
        case .ambiguous:
            ambiguousCandidates = draft.ambiguousCandidates
            // Don't auto-select — user picks from disambiguation
        case .noMatch:
            // Pre-fill new lead creation with parsed name
            if let parsedName = draft.parsedContactName {
                isCreatingNewLead = true
                newLeadName = parsedName
            }
        case .noContact:
            break // Notes-only — user selects opportunity manually
        }
    }

    func resolveAmbiguousMatch(opportunityId: String) {
        selectedOpportunity = activeOpportunities.first { $0.id == opportunityId }
        ambiguousCandidates = []
    }

    // MARK: - Validation

    var canSave: Bool {
        (selectedOpportunity != nil || (isCreatingNewLead && !newLeadName.trimmingCharacters(in: .whitespaces).isEmpty))
    }

    var showDirectionField: Bool {
        selectedType == .call || selectedType == .email
    }

    var showDurationField: Bool {
        selectedType == .call || selectedType == .meeting
    }

    // MARK: - Save

    func save() async -> Bool {
        guard let repository, let companyId, let userId else { return false }
        guard canSave else { return false }

        isSaving = true
        saveError = nil

        do {
            var opportunityId: String

            // Create new lead if needed
            if isCreatingNewLead && selectedOpportunity == nil {
                let dto = CreateOpportunityDTO(
                    companyId: companyId,
                    contactName: newLeadName.trimmingCharacters(in: .whitespaces),
                    contactEmail: newLeadEmail.isEmpty ? nil : newLeadEmail,
                    contactPhone: newLeadPhone.isEmpty ? nil : newLeadPhone,
                    description: nil,
                    estimatedValue: nil,
                    source: "voice_log"
                )
                let created = try await repository.create(dto)
                opportunityId = created.id

                // Insert into local SwiftData
                let model = created.toModel()
                modelContext?.insert(model)
                try? modelContext?.save()
            } else if let selected = selectedOpportunity {
                opportunityId = selected.id
            } else {
                isSaving = false
                return false
            }

            // Log the activity
            let activityDTO = CreateActivityDTO(
                opportunityId: opportunityId,
                companyId: companyId,
                type: selectedType.rawValue,
                content: notesText.isEmpty ? nil : notesText
            )
            _ = try await repository.logActivity(activityDTO)

            // Update local opportunity's lastActivityAt
            if let opp = selectedOpportunity {
                opp.lastActivityAt = Date()
                try? modelContext?.save()
            }

            isSaving = false
            return true
        } catch {
            saveError = error.localizedDescription
            isSaving = false
            return false
        }
    }
}
