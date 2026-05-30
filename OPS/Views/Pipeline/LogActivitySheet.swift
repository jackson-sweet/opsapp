//
//  LogActivitySheet.swift
//  OPS
//
//  Voice-first quick logger for recording lead correspondence.
//  Tap mic → speak naturally → fields auto-populate → tap LOG.
//

import SwiftUI
import Speech

struct LogActivitySheet: View {
    @StateObject private var viewModel = LogActivityViewModel()
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// The user-loggable activity types (excludes system-generated types)
    private let loggableTypes: [ActivityType] = [.call, .email, .meeting, .note, .siteVisit]

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                QuickActionSheetHeader(
                    title: "LOG ACTIVITY",
                    canSave: viewModel.canSave && !viewModel.isSaving,
                    isSaving: viewModel.isSaving,
                    onDismiss: { dismiss() },
                    onSave: {
                        Task {
                            let success = await viewModel.save()
                            if success {
                                let generator = UINotificationFeedbackGenerator()
                                generator.notificationOccurred(.success)
                                dismiss()
                            }
                        }
                    }
                )

                ScrollView {
                    VStack(spacing: 24) {
                        // Mic hero
                        micSection()

                        // Activity type chips
                        typeChipsSection()

                        // Opportunity picker
                        opportunitySection()

                        // Ambiguous match disambiguation
                        if !viewModel.ambiguousCandidates.isEmpty {
                            disambiguationSection()
                        }

                        // Notes
                        notesSection()

                        // Optional metadata
                        metadataSection()

                        // Error display
                        if let error = viewModel.saveError {
                            Text(error)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .padding(.horizontal, 20)
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .onAppear {
            if let companyId = dataController.currentUser?.companyId,
               let userId = dataController.currentUser?.id {
                viewModel.setup(companyId: companyId, userId: userId, modelContext: modelContext)
            }
        }
        .onChange(of: viewModel.speechManager.state) { oldState, newState in
            // When recording stops, parse the transcription
            if oldState == .recording && newState == .idle {
                viewModel.parseTranscription()
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Mic Section

    @ViewBuilder
    private func micSection() -> some View {
        VStack(spacing: 12) {
            Button {
                Task {
                    // Request permissions on first tap
                    let speechStatus = await SpeechRecognitionManager.requestAuthorization()
                    guard speechStatus == .authorized else {
                        viewModel.speechManager.state = .error("Speech recognition not authorized. Enable in Settings > Privacy.")
                        return
                    }
                    let micAccess = await SpeechRecognitionManager.requestMicrophoneAccess()
                    guard micAccess else {
                        viewModel.speechManager.state = .error("Microphone access denied. Enable in Settings > Privacy.")
                        return
                    }
                    viewModel.toggleRecording()
                }
            } label: {
                VStack(spacing: 8) {
                    ZStack {
                        // Pulse ring when recording — sharp ease-out, no bounce
                        if viewModel.speechManager.state == .recording {
                            Circle()
                                .stroke(OPSStyle.Colors.successStatus.opacity(0.3), lineWidth: 2)
                                .frame(width: 72, height: 72)
                                .scaleEffect(viewModel.speechManager.state == .recording ? 1.3 : 1.0)
                                .opacity(viewModel.speechManager.state == .recording ? 0 : 1)
                                .animation(
                                    .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                    value: viewModel.speechManager.state
                                )
                        }

                        Circle()
                            .fill(viewModel.speechManager.state == .recording
                                  ? OPSStyle.Colors.errorStatus
                                  : OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 64, height: 64)

                        Image(systemName: viewModel.speechManager.state == .recording ? "stop.fill" : "mic.fill")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(viewModel.speechManager.state == .recording
                                             ? .white
                                             : OPSStyle.Colors.primaryText)
                    }

                    Text(micPromptText)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .buttonStyle(.plain)
            .frame(minHeight: 60)
            .accessibilityLabel(viewModel.speechManager.state == .recording ? "Stop recording" : "Start recording")

            // Live transcription preview
            if viewModel.speechManager.state == .recording && !viewModel.speechManager.transcription.isEmpty {
                Text(viewModel.speechManager.transcription)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            // Error state
            if case .error(let message) = viewModel.speechManager.state {
                Text(message)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.horizontal, 20)
    }

    private var micPromptText: String {
        switch viewModel.speechManager.state {
        case .idle:
            return viewModel.hasParsedVoice ? "Tap to re-record" : "Tap to record"
        case .recording:
            return "Listening... tap to stop"
        case .stopping:
            return "Processing..."
        case .error:
            return "Tap to try again"
        }
    }

    // MARK: - Type Chips

    @ViewBuilder
    private func typeChipsSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TYPE")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 20)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(loggableTypes, id: \.rawValue) { type in
                        typeChip(type)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    @ViewBuilder
    private func typeChip(_ type: ActivityType) -> some View {
        let isSelected = viewModel.selectedType == type
        Button {
            let generator = UIImpactFeedbackGenerator(style: .light)
            generator.impactOccurred()
            viewModel.selectedType = type
        } label: {
            HStack(spacing: 6) {
                Image(systemName: type.icon)
                    .font(.system(size: 14))
                Text(type.chipLabel)
                    .font(OPSStyle.Typography.smallButton)
            }
            .foregroundColor(isSelected ? .white : OPSStyle.Colors.primaryText)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? OPSStyle.Colors.successStatus : OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(20)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(type.chipLabel), \(isSelected ? "selected" : "not selected")")
    }

    // MARK: - Opportunity Section

    @ViewBuilder
    private func opportunitySection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LEAD")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 20)

            Button {
                viewModel.showOpportunityPicker = true
            } label: {
                HStack(spacing: 12) {
                    if let opp = viewModel.selectedOpportunity {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.successStatus.opacity(0.2))
                                .frame(width: 36, height: 36)
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.successStatus)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(opp.contactName)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text(opp.stage.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    } else if viewModel.isCreatingNewLead && !viewModel.newLeadName.isEmpty {
                        ZStack {
                            Circle()
                                .fill(OPSStyle.Colors.warningStatus.opacity(0.2))
                                .frame(width: 36, height: 36)
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            Text(viewModel.newLeadName)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Text("NEW LEAD")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                    } else {
                        Image(systemName: "person.crop.circle.badge.questionmark")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("Select a lead...")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .padding(.horizontal, 20)
            }
            .buttonStyle(.plain)
        }
        .sheet(isPresented: $viewModel.showOpportunityPicker) {
            NavigationStack {
                OpportunityPickerView(viewModel: viewModel)
                    .navigationTitle("Select Lead")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { viewModel.showOpportunityPicker = false }
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
            }
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Disambiguation

    @ViewBuilder
    private func disambiguationSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MULTIPLE MATCHES")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
                .padding(.horizontal, 20)

            VStack(spacing: 0) {
                ForEach(viewModel.ambiguousCandidates, id: \.opportunityId) { candidate in
                    Button {
                        let generator = UIImpactFeedbackGenerator(style: .light)
                        generator.impactOccurred()
                        viewModel.resolveAmbiguousMatch(opportunityId: candidate.opportunityId)
                    } label: {
                        HStack(spacing: 12) {
                            Text(candidate.contactName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Divider().padding(.leading, 16)
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Notes Section

    @ViewBuilder
    private func notesSection() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 20)

            ZStack(alignment: .topLeading) {
                if viewModel.notesText.isEmpty {
                    Text("What happened?")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                }

                TextEditor(text: $viewModel.notesText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 80, maxHeight: 160)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Optional Metadata

    @ViewBuilder
    private func metadataSection() -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(OPSStyle.Animation.fast) {
                    viewModel.showMetadata.toggle()
                }
            } label: {
                HStack {
                    Text("More details")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Image(systemName: viewModel.showMetadata ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if viewModel.showMetadata {
                VStack(spacing: 16) {
                    // Direction (call/email only)
                    if viewModel.showDirectionField {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DIRECTION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            SegmentedControl(
                                selection: $viewModel.direction,
                                options: [
                                    ("outbound", "Outbound"),
                                    ("inbound", "Inbound")
                                ]
                            )
                        }
                    }

                    // Outcome
                    VStack(alignment: .leading, spacing: 6) {
                        Text("OUTCOME")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        TextField("e.g., Left voicemail, Scheduled follow-up", text: $viewModel.outcome)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }

                    // Duration (call/meeting only)
                    if viewModel.showDurationField {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("DURATION (MINUTES)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Stepper(value: $viewModel.durationMinutes, in: 0...480, step: 5) {
                                Text("\(viewModel.durationMinutes) min")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

// MARK: - ActivityType Chip Labels

extension ActivityType {
    var chipLabel: String {
        switch self {
        case .call:      return "Call"
        case .email:     return "Email"
        case .meeting:   return "Meeting"
        case .note:      return "Note"
        case .siteVisit: return "Site Visit"
        default:         return rawValue.capitalized
        }
    }
}
