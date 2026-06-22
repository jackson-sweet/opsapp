//
//  LogCallSheet.swift
//  OPS
//
//  Around-call lead capture sheet (iOS feature 154cb8a3). Modeled on
//  LeadLogActivitySheet, specialized for a call that just happened. Funnels all
//  three entry points (post-call prompt, FAB "Log a call", App Shortcut) into
//  the same capture:
//
//    • postCall  — lead already known, pre-filled, OUTBOUND default.
//    • capture   — pick from Contacts or type a number; OPS dedups it to an
//                  existing lead (attach) or creates a new source:"phone" lead.
//
//  Optional in-app voice note dictates (on-device) into the NOTE body. Recording
//  a native phone call is not possible for a third-party app — this is the
//  shipped substitute. The save funnels through LeadDetailViewModel.logActivity
//  with call provenance (source / number / started-at).
//

import SwiftUI
import Contacts

struct LogCallSheet: View {
    let request: CallCaptureRequest

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var vm: LogCallViewModel

    init(request: CallCaptureRequest) {
        self.request = request
        let mode: LogCallViewModel.Mode
        switch request {
        case .postCall(let pending): mode = .postCall(pending)
        case .capture(let source):   mode = .capture(source)
        }
        _vm = StateObject(wrappedValue: LogCallViewModel(mode: mode))
    }

    private var detents: Set<PresentationDetent> {
        if case .postCall = request { return [.medium, .large] }
        return [.large]
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        if vm.leadIsLocked {
                            lockedLeadSection
                        } else {
                            contactSection
                        }
                        directionSection
                        outcomeSection
                        durationSection
                        noteSection
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
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
        .presentationBackground(OPSStyle.Colors.background)
        .interactiveDismissDisabled(vm.isSaving || vm.speech.state == .recording)
        .onAppear {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                vm.setup(companyId: companyId, userId: dataController.currentUser?.id, modelContext: modelContext)
            }
        }
        .onDisappear { vm.teardown() }
        .onChange(of: vm.speech.state) { oldState, newState in
            if oldState == .recording && newState == .idle {
                vm.applyTranscription()
            }
        }
        .sheet(isPresented: $vm.showContactPicker) {
            ContactPicker(
                onContactSelected: { contact in
                    let name = [contact.givenName, contact.familyName]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let phone = contact.phoneNumbers.first?.value.stringValue ?? ""
                    vm.applyPickedContact(name: name, phone: phone)
                },
                onDismiss: nil
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                SheetTitleLabel(title: "LOG CALL", size: .half)
                if !isPostCall {
                    SheetCloseButton { dismiss() }
                }
            }
            if let context = postCallContext {
                Text(context)
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .kerning(1.4)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    private var isPostCall: Bool {
        if case .postCall = request { return true }
        return false
    }

    private var postCallContext: String? {
        guard isPostCall else { return nil }
        let name = vm.contactName.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return "// CALLED \(name)" }
        if !vm.phoneNumber.isEmpty { return "// CALLED \(vm.phoneNumber)" }
        return "// JUST CALLED"
    }

    // MARK: - Locked lead (post-call, known lead)

    private var lockedLeadSection: some View {
        LeadField(label: "CONTACT") {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.contactName.isEmpty ? "This lead" : vm.contactName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.text)
                    if let stage = vm.knownStageName {
                        Text(stage)
                            .font(.custom("JetBrainsMono-Regular", size: 10))
                            .kerning(1.4)
                            .textCase(.uppercase)
                            .foregroundColor(OPSStyle.Colors.text3)
                    }
                }
                Spacer()
                Text("// ATTACHING")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, 14)
            .glassSurface()
        }
    }

    // MARK: - Contact (capture / unmatched)

    private var contactSection: some View {
        LeadField(label: "CONTACT") {
            VStack(alignment: .leading, spacing: 10) {
                SheetCTAButton(
                    label: "ADD FROM CONTACTS",
                    icon: "person.crop.circle.badge.plus",
                    variant: .outline,
                    action: { vm.showContactPicker = true }
                )

                LeadTextInput(
                    placeholder: "Helen Calloway",
                    text: $vm.contactName,
                    keyboard: .default,
                    textContentType: .name
                )

                LeadTextInput(
                    placeholder: "604-555-0142",
                    text: $vm.phoneNumber,
                    keyboard: .phonePad,
                    textContentType: .telephoneNumber
                )
                .onChange(of: vm.phoneNumber) { _, _ in vm.runDedup() }

                dedupStatusLine
            }
        }
    }

    @ViewBuilder
    private var dedupStatusLine: some View {
        let hasInput = !vm.phoneNumber.trimmingCharacters(in: .whitespaces).isEmpty
            || !vm.contactName.trimmingCharacters(in: .whitespaces).isEmpty
        if hasInput {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                if vm.isResolving {
                    Text("CHECKING…")
                        .foregroundColor(OPSStyle.Colors.text3)
                } else if let match = vm.matchedLead {
                    Text("MATCHED — \(match.contactName)")
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                } else {
                    Text("NEW LEAD")
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                }
            }
            .font(.custom("JetBrainsMono-Medium", size: 11))
            .kerning(1.4)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Direction

    private var directionSection: some View {
        LeadField(label: "DIRECTION") {
            LeadChipPicker(
                selection: $vm.direction,
                options: [
                    .init(id: "inbound",  label: "INBOUND"),
                    .init(id: "outbound", label: "OUTBOUND"),
                ]
            )
        }
    }

    // MARK: - Outcome

    private var outcomeSection: some View {
        LeadField(label: "OUTCOME", hint: "[OPTIONAL]") {
            LeadChipPicker(
                selection: $vm.outcome,
                options: LogCallSheet.outcomeOptions
            )
        }
    }

    static let outcomeOptions: [LeadChipOption] = [
        .init(id: "spoke",          label: "SPOKE"),
        .init(id: "left_voicemail", label: "LEFT VM"),
        .init(id: "no_answer",      label: "NO ANSWER"),
        .init(id: "booked_visit",   label: "BOOKED VISIT"),
        .init(id: "other",          label: "OTHER"),
    ]

    // MARK: - Duration

    private var durationSection: some View {
        LeadField(label: "DURATION", hint: "[MINUTES, OPTIONAL]") {
            HStack(spacing: 10) {
                LeadTextInput(
                    placeholder: "15",
                    text: $vm.durationText,
                    keyboard: .numberPad
                )
                .frame(maxWidth: 120)

                Text("MINUTES")
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)

                Spacer()
            }
        }
    }

    // MARK: - Note + voice

    private var noteSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("NOTE")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .textCase(.uppercase)
                Text("[OPTIONAL]")
                    .font(.custom("JetBrainsMono-Regular", size: 10))
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
                Spacer()
                voiceButton
            }

            LeadTextArea(
                placeholder: "What did you talk about?",
                text: $vm.bodyText,
                rows: 4
            )

            if vm.speech.state == .recording, !vm.speech.transcription.isEmpty {
                Text(vm.speech.transcription)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }

            if case .error(let message) = vm.speech.state {
                Text(message)
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .foregroundColor(OPSStyle.Colors.roseTextM)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var isRecording: Bool { vm.speech.state == .recording }

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
                Text(isRecording ? "LISTENING" : "DICTATE")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
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
            vm.toggleVoice()
            return
        }
        let speechStatus = await SpeechRecognitionManager.requestAuthorization()
        guard speechStatus == .authorized else {
            vm.speech.state = .error("Speech access off — enable in Settings.")
            return
        }
        let micGranted = await SpeechRecognitionManager.requestMicrophoneAccess()
        guard micGranted else {
            vm.speech.state = .error("Mic access off — enable in Settings.")
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        vm.toggleVoice()
    }

    // MARK: - Footer

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage = vm.errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else if vm.isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { vm.teardown(); dismiss() }
                )
                .disabled(vm.isSaving)
            } primary: {
                SheetCTAButton(
                    label: "LOG CALL",
                    icon: "checkmark",
                    variant: .primary,
                    isLoading: vm.isSaving,
                    action: save
                )
                .disabled(!vm.canSave)
                .opacity(vm.canSave ? 1 : 0.5)
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
        guard vm.canSave else { return }
        Task {
            let ok = await vm.save()
            if ok {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            }
        }
    }
}
