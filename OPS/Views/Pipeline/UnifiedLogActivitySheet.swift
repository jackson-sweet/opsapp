//
//  UnifiedLogActivitySheet.swift
//  OPS
//
//  The ONE Log Activity capture sheet — replaces LeadLogActivitySheet's
//  inline UI, LogCallSheet, and LogActivityView. All state + save logic
//  lives in `UnifiedLogActivityViewModel`; this file is presentation only.
//
//  Structure mirrors the existing lead sheets (LeadLogActivitySheet /
//  LogCallSheet): a scrolling body of `LeadField`-wrapped sections, a pinned
//  gradient-scrim footer with CANCEL/primary, reusing every primitive in
//  LeadFormView.swift verbatim. Zones:
//
//    1. HEADER      — title + optional call-provenance subline + close.
//    2. NOTE        — free text + inline DICTATE voice pill (LogCallSheet
//                     pattern), folds transcription into notesText on stop.
//    3. TYPE        — CALL / EMAIL / MEETING / NOTE chips. No SITE VISIT
//                     (its own flow) and no TEXT (ActivityType has no
//                     text/sms case — inventing one is out of scope here).
//    4. AGAINST     — state-aware target: locked NEUTRAL chip (never green)
//                     when resolved, else a picker-launching row.
//    5. DETAIL      — DIRECTION / DURATION / OUTCOME / SUBJECT, each gated
//                     by the view model's show*Field flags.
//    6. FOLLOW-UP   — only when a suggestion exists AND the target is a
//                     lead (opportunity) — follow_ups only ever attach to
//                     an opportunity id, so client/job targets can't SET.
//    7. FOOTER      — status line + CANCEL / LOG (LOG CALL for .call).
//
//  The steel-blue accent (`opsAccent`) appears exactly once: the primary
//  footer CTA. Every other affordance uses neutral surface/line tokens —
//  selection state is a white surface shift, never green.
//

import SwiftUI

struct UnifiedLogActivitySheet: View {
    @StateObject var viewModel: UnifiedLogActivityViewModel

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showTargetPicker = false

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        noteSection
                        typeSection
                        targetSection
                        if viewModel.showDirectionField { directionSection }
                        if viewModel.showDurationField { durationSection }
                        if viewModel.showOutcomeField { outcomeSection }
                        subjectSection
                        if showFollowUpRow { followUpSection }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 160)
                }
                .scrollIndicators(.hidden)
            }

            footerOverlay
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(viewModel.isSaving || viewModel.speechManager.state == .recording)
        .onAppear {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.configure(companyId: companyId, userId: dataController.currentUser?.id, modelContext: modelContext)
            }
        }
        .onDisappear { viewModel.teardownVoice() }
        .onChange(of: viewModel.speechManager.state) { oldState, newState in
            viewModel.handleSpeechStateChange(from: oldState, to: newState)
        }
        .sheet(isPresented: $showTargetPicker) {
            if let companyId = dataController.currentUser?.companyId {
                ActivityTargetPickerView(companyId: companyId) { picked in
                    viewModel.selectTarget(picked)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                SheetTitleLabel(title: "LOG ACTIVITY", size: .full)
                if !viewModel.isTargetLocked {
                    SheetCloseButton { dismiss() }
                }
            }
            if let context = callProvenanceContext {
                Text(context)
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    /// `// CALLED <name>` subline shown only when the entry point carries call
    /// provenance (post-call return or FAB/Shortcut call capture) — mirrors
    /// LogCallSheet's `postCallContext`.
    private var callProvenanceContext: String? {
        guard viewModel.selectedType == .call else { return nil }
        switch viewModel.entry {
        case .postCall, .capture:
            let name = viewModel.contactName.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { return "// CALLED \(name)" }
            if !viewModel.phoneNumber.isEmpty { return "// CALLED \(viewModel.phoneNumber)" }
            return "// JUST CALLED"
        case .genericFAB, .leadDetail:
            return nil
        }
    }

    // MARK: - Note + voice

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NOTE")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                Text("[what happened]")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
                Spacer()
                voiceButton
            }

            LeadTextArea(
                placeholder: notePlaceholder,
                text: $viewModel.notesText,
                rows: 4
            )

            if viewModel.speechManager.state == .recording, !viewModel.speechManager.transcription.isEmpty {
                Text(viewModel.speechManager.transcription)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if case .error(let message) = viewModel.speechManager.state {
                Text(message)
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .foregroundColor(OPSStyle.Colors.roseTextM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var notePlaceholder: String {
        switch viewModel.selectedType {
        case .call:    return "What did you talk about?"
        case .email:   return "Paste the gist of the email here."
        case .meeting: return "Agenda, decisions, next steps."
        default:       return "Anything worth remembering."
        }
    }

    private var isRecording: Bool { viewModel.speechManager.state == .recording }

    /// Inline DICTATE pill — verbatim LogCallSheet treatment: mic/stop icon,
    /// a reduced-motion-aware pulse ring while listening, SYS-style label.
    private var voiceButton: some View {
        Button {
            Task { await toggleDictation() }
        } label: {
            HStack(spacing: 6) {
                ZStack {
                    if isRecording, !reduceMotion {
                        Circle()
                            .stroke(OPSStyle.Colors.roseTextM.opacity(0.4), lineWidth: 1.5)
                            .frame(width: 16, height: 16)
                            .scaleEffect(isRecording ? 1.6 : 1.0)
                            .opacity(isRecording ? 0 : 1)
                            .animation(
                                .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                value: isRecording
                            )
                    }
                    Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(isRecording ? OPSStyle.Colors.roseTextM : OPSStyle.Colors.text2)
                }
                Text(isRecording ? "SYS :: LISTENING" : "SYS :: READY")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .kerning(1.2)
                    .foregroundColor(isRecording ? OPSStyle.Colors.roseTextM : OPSStyle.Colors.text2)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: 32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(isRecording ? "Stop dictation" : "Dictate a note")
    }

    private func toggleDictation() async {
        if isRecording {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            viewModel.toggleRecording()
            return
        }
        let speechStatus = await SpeechRecognitionManager.requestAuthorization()
        guard speechStatus == .authorized else {
            viewModel.speechManager.state = .error("Speech access off — enable in Settings.")
            return
        }
        let micGranted = await SpeechRecognitionManager.requestMicrophoneAccess()
        guard micGranted else {
            viewModel.speechManager.state = .error("Mic access off — enable in Settings.")
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        viewModel.toggleRecording()
    }

    // MARK: - Type

    /// CORRESPONDENCE ONLY — CALL / EMAIL / MEETING / NOTE. `ActivityType` has
    /// no text/sms case, so TEXT is intentionally omitted rather than
    /// invented. SITE VISIT is its own flow and never appears here.
    private static let typeOptions: [LeadChipOption] = [
        .init(id: ActivityType.call.rawValue,    label: "CALL"),
        .init(id: ActivityType.email.rawValue,   label: "EMAIL"),
        .init(id: ActivityType.meeting.rawValue, label: "MEETING"),
        .init(id: ActivityType.note.rawValue,    label: "NOTE"),
    ]

    private var typeSection: some View {
        LeadField(label: "TYPE") {
            LeadChipPicker(selection: typeBinding, options: Self.typeOptions)
        }
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { viewModel.selectedType.rawValue },
            set: { newValue in
                if let type = ActivityType(rawValue: newValue) { viewModel.selectedType = type }
            }
        )
    }

    // MARK: - Target ("AGAINST")

    private var targetSection: some View {
        LeadField(label: "AGAINST") {
            if hasResolvedTarget {
                lockedTargetRow
            } else {
                unresolvedTargetRow
            }
        }
    }

    private var hasResolvedTarget: Bool {
        viewModel.target.parentKey != nil
    }

    /// A resolved target — locked by the entry point or explicitly picked —
    /// renders as a NEUTRAL confirmed row. Never green/accent: this is state
    /// confirmation, not a success signal. The clear (X) affordance only
    /// appears when the target isn't locked by the entry point.
    private var lockedTargetRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            VStack(alignment: .leading, spacing: 2) {
                Text(viewModel.target.displayName.isEmpty ? "This lead" : viewModel.target.displayName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                if let subtitle = viewModel.target.subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .kerning(1.4)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            Spacer()
            if let badge = viewModel.target.sourceBadge {
                sourceBadgeView(badge)
            }
            if !viewModel.isTargetLocked {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    viewModel.clearTarget()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear target")
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    /// Neutral "LEAD" / "CLIENT" / "JOB" disambiguation tag — verbatim
    /// ActivityTargetPickerView treatment (text3-on-line, never accent).
    private func sourceBadgeView(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .tracking(1.2)
            .foregroundColor(OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .padding(.vertical, OPSStyle.Layout.spacing1)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .fill(OPSStyle.Colors.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }

    /// Unresolved + unlocked: a tappable row that opens the unified
    /// lead/client/job picker.
    private var unresolvedTargetRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showTargetPicker = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
                Text("Select a lead, client, or job")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.textMute)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Detail: direction

    private var directionSection: some View {
        LeadField(label: "DIRECTION") {
            LeadChipPicker(
                selection: $viewModel.direction,
                options: [
                    .init(id: "outbound", label: "OUT"),
                    .init(id: "inbound",  label: "IN"),
                ]
            )
        }
    }

    // MARK: - Detail: duration

    private var durationSection: some View {
        LeadField(label: "DURATION") {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.durationMinutes = max(0, viewModel.durationMinutes - 5)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .fill(OPSStyle.Colors.surfaceInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Text("\(viewModel.durationMinutes) MIN")
                    .font(.custom("JetBrainsMono-Medium", size: 14))
                    .monospacedDigit()
                    .kerning(0.6)
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(minWidth: 64)

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    viewModel.durationMinutes += 5
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(width: 36, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .fill(OPSStyle.Colors.surfaceInput)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Spacer()
            }
        }
    }

    // MARK: - Detail: outcome

    private var outcomeSection: some View {
        LeadField(label: "OUTCOME", hint: "[e.g. left voicemail]") {
            LeadTextInput(placeholder: "left voicemail", text: $viewModel.outcome)
        }
    }

    // MARK: - Detail: subject

    private var subjectSection: some View {
        LeadField(label: "SUBJECT", hint: "[optional]") {
            LeadTextInput(placeholder: "Subject line", text: $viewModel.subject)
        }
    }

    // MARK: - Follow-up

    /// A follow-up suggestion can only attach to an opportunity — follow_ups
    /// has no client/job parent column — so the row is hidden entirely
    /// (not just disabled) when the resolved target isn't a lead. Prevents a
    /// dead SET tap: `setFollowUp()` no-ops without a resolved opportunity id.
    private var showFollowUpRow: Bool {
        guard viewModel.suggestedFollowUp != nil else { return false }
        if case .opportunity = viewModel.target { return true }
        return false
    }

    private var followUpSection: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 8, weight: .regular))
                .foregroundColor(OPSStyle.Colors.tanTextM)

            VStack(alignment: .leading, spacing: 2) {
                Text("FOLLOW-UP")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .textCase(.uppercase)
                if let suggestion = viewModel.suggestedFollowUp {
                    Text("\(suggestion.title) · \(followUpDateText(suggestion.dueAt))")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .lineLimit(1)
                }
            }

            Spacer()

            Button {
                Task { await viewModel.setFollowUp() }
            } label: {
                if viewModel.isSettingFollowUp {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.tanTextM)
                        .frame(width: 56, height: 32)
                } else {
                    Text(viewModel.followUpSetSuccessfully ? "SET ✓" : "SET")
                        .font(.custom("JetBrainsMono-Medium", size: 11))
                        .kerning(1.2)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                        .frame(width: 56, height: 32)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .fill(OPSStyle.Colors.tanFillM)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                                .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: 1)
                        )
                }
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(viewModel.isSettingFollowUp || viewModel.followUpSetSuccessfully)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .fill(OPSStyle.Colors.tanSoft)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.tanLine, lineWidth: 1)
        )
        .animation(OPSStyle.Animation.standard, value: viewModel.followUpSetSuccessfully)
    }

    /// `TODAY` / `TOMORROW` / `IN Nd` — the same day-delta convention
    /// FollowUpsCard uses so a follow-up reads identically everywhere.
    private func followUpDateText(_ date: Date) -> String {
        let cal = Calendar.current
        let from = cal.startOfDay(for: Date())
        let to = cal.startOfDay(for: date)
        let delta = cal.dateComponents([.day], from: from, to: to).day ?? 0
        if delta < 0  { return "\(-delta)D OVERDUE" }
        if delta == 0 { return "TODAY" }
        if delta == 1 { return "TOMORROW" }
        return "IN \(delta)D"
    }

    // MARK: - Footer

    private var primaryLabel: String {
        viewModel.selectedType == .call ? "LOG CALL" : "LOG"
    }

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage = viewModel.errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if viewModel.isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { viewModel.teardownVoice(); dismiss() }
                )
                .disabled(viewModel.isSaving)
            } primary: {
                SheetCTAButton(
                    label: primaryLabel,
                    icon: "checkmark",
                    variant: .primary,
                    isLoading: viewModel.isSaving,
                    action: save
                )
                .disabled(!viewModel.canSave)
                .opacity(viewModel.canSave ? 1 : 0.5)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [Color.black.opacity(0), Color.black.opacity(0.95), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Save

    private func save() {
        guard viewModel.canSave else { return }
        Task {
            let ok = await viewModel.save()
            if ok { dismiss() }
        }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("UnifiedLogActivitySheet / call, locked lead, follow-up") {
    let lead = Opportunity(
        companyId: "preview",
        contactName: "Helen Calloway",
        stage: .qualifying
    )
    let vm = UnifiedLogActivityViewModel(entry: .leadDetail(lead))
    vm.selectedType = .call
    vm.direction = "inbound"
    vm.outcome = "booked_visit"
    vm.durationMinutes = 12
    vm.notesText = "Wants a quote for the deck rebuild. Sending photos tonight."
    vm.suggestedFollowUp = (title: "Send deck rebuild quote", dueAt: Calendar.current.date(byAdding: .day, value: 2, to: Date())!)

    return UnifiedLogActivitySheet(viewModel: vm)
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
#endif
