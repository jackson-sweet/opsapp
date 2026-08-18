//
//  SiteVisitCaptureView.swift
//  OPS
//
//  Field-first site visit capture console.
//

import Contacts
import PencilKit
import Speech
import SwiftData
import SwiftUI
import UIKit

struct SiteVisitCaptureView: View {
    let opportunity: Opportunity?
    let initialSiteVisitType: SiteVisitType?
    let onCreateProject: (Opportunity) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @State private var viewModel: SiteVisitCaptureViewModel?

    init(
        opportunity: Opportunity? = nil,
        onCreateProject: @escaping (Opportunity) -> Void,
        initialSiteVisitType: SiteVisitType? = nil
    ) {
        self.opportunity = opportunity
        self.onCreateProject = onCreateProject
        self.initialSiteVisitType = initialSiteVisitType
    }

    var body: some View {
        Group {
            if let viewModel {
                SiteVisitCaptureConsole(
                    viewModel: viewModel,
                    onClose: { dismiss() },
                    onCreateProject: { lead in
                        dismiss()
                        onCreateProject(lead)
                    }
                )
            } else {
                ZStack {
                    OPSStyle.Colors.background.ignoresSafeArea()
                    ProgressView()
                        .tint(OPSStyle.Colors.text)
                }
                .task {
                    let companyId = opportunity?.companyId
                        ?? dataController.currentUser?.companyId
                        ?? ""
                    guard !companyId.isEmpty else { return }
                    _ = try? dataController.ensureSiteVisitTypesSeeded(
                        deckBuilderEnabled: PermissionStore.shared.isFeatureEnabled("deck_builder")
                    )
                    let vm = SiteVisitCaptureViewModel(
                        opportunity: opportunity,
                        companyId: companyId,
                        userId: dataController.currentUser?.id,
                        modelContext: modelContext
                    )
                    vm.loadOrCreateVisit()
                    if let initialSiteVisitType {
                        vm.selectSiteVisitType(initialSiteVisitType)
                    }
                    viewModel = vm
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum SiteVisitCaptureField: Hashable {
    case note
    case measurement
}

private enum SiteVisitCaptureScrollTarget: Hashable {
    case notes
    case identity
}

private struct SiteVisitCaptureConsole: View {
    @ObservedObject var viewModel: SiteVisitCaptureViewModel
    let onClose: () -> Void
    let onCreateProject: (Opportunity) -> Void

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @StateObject private var speechManager = SpeechRecognitionManager()
    @FocusState private var focusedField: SiteVisitCaptureField?

    @State private var showingCamera = false
    @State private var showingReview = false
    @State private var showingDeckBuilder = false
    @State private var activeDeckDesign: DeckDesign?
    @State private var markupArtifact: SiteVisitCaptureArtifact?
    @State private var previewArtifact: SiteVisitCaptureArtifact?
    @State private var editingNoteArtifact: SiteVisitCaptureArtifact?
    @State private var isPacketExpanded = true
    @State private var showingDimensionedCapture = false
    @State private var showingCloseConfirm = false
    @State private var identityExpanded = true
    @State private var recordingPulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pendingIdentityFocus = false
    @State private var noteAutosaveTask: Task<Void, Never>?
    @State private var customChecklistQuestion = ""
    @State private var customChecklistKind: SiteVisitFieldKind = .shortText
    @State private var keyboardVisible = false
    /// Owned by the console, NOT the identity panel. The panel lives inside the
    /// capture ScrollView; presenting a modal from there put the picker's
    /// dismissal in reach of the visit's own fullScreenCover (bug 5d5df5b0).
    /// The console root is the stable presentation slot.
    @State private var showingContactPicker = false
    @State private var showingChecklistGuide = false
    @State private var showingChecklistSettings = false

    private var canManageSiteVisitTypes: Bool {
        PermissionStore.shared.can("settings.company")
    }

    var body: some View {
        ScrollViewReader { scrollProxy in
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if viewModel.resumableVisit != nil {
                        resumeBanner
                    }

                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            // Bug (site-visit report) — a sequential checklist the
                            // operator works top-to-bottom: the LEAD form (step 1,
                            // always required) sits at the top. A linked lead's
                            // read-only summary follows when one exists, then the
                            // type-dependent CHECKLIST (step 2, variable fields)
                            // and NOTES (step 3). statusStrip is the at-a-glance
                            // readout above; the captured packet is the flat list
                            // at the bottom.
                            statusStrip
                            primaryFormSections
                            packetPanel
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing2)
                        .padding(.bottom, 132)
                    }
                    .scrollIndicators(.hidden)
                }

                // Hidden while the keyboard is up (bug e73f3a5c): typing owns
                // the bottom edge — the keyboard toolbar's DONE is the exit.
                // ignoresSafeArea keeps the bar anchored so it never rides the
                // keyboard during the transition; the opacity fade is already
                // the reduced-motion-safe treatment.
                actionBar(scrollProxy: scrollProxy)
                    .opacity(keyboardVisible ? 0 : 1)
                    .allowsHitTesting(!keyboardVisible)
                    .animation(OPSStyle.Animation.standard, value: keyboardVisible)
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                keyboardVisible = true
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                keyboardVisible = false
            }
            .onChange(of: showingReview) { _, showing in
                // Returning from Review with "add lead details" pending: open the
                // identity panel and scroll to it so the operator lands exactly
                // where they must act, instead of hunting for it.
                guard !showing, pendingIdentityFocus else { return }
                pendingIdentityFocus = false
                identityExpanded = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    withAnimation(OPSStyle.Animation.standard) {
                        scrollProxy.scrollTo(SiteVisitCaptureScrollTarget.identity, anchor: .top)
                    }
                }
            }
        }
        .task {
            speechManager.preferOnDeviceRecognition = true
            speechManager.contextualStrings = [
                viewModel.currentOpportunity?.contactName ?? viewModel.identityDraft?.contactName ?? "",
                viewModel.currentOpportunity?.address ?? viewModel.identityDraft?.address ?? "",
                "deck", "membrane", "railing", "stairs", "vinyl", "slope", "drainage"
            ].filter { !$0.isEmpty }

            if canManageSiteVisitTypes,
               SiteVisitChecklistGuideStore().shouldPresent(
                userId: dataController.currentUser?.id
               ) {
                showingChecklistGuide = true
            }
        }
        .onChange(of: speechManager.state) { oldValue, newValue in
            if oldValue == .recording && newValue == .idle {
                let text = speechManager.transcription.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    // Append to the working note — never overwrite what was typed.
                    viewModel.appendDictation(text)
                    speechManager.transcription = ""
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
            }
        }
        .onChange(of: viewModel.noteDraft) { _, _ in
            scheduleNoteAutosave()
        }
        .onChange(of: focusedField) { oldValue, newValue in
            if oldValue == .note && newValue != .note {
                noteAutosaveTask?.cancel()
                viewModel.autosaveNote()
            }
        }
        .onDisappear {
            noteAutosaveTask?.cancel()
            viewModel.autosaveNote()
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraBatchView { images in
                viewModel.addPhotos(images)
                if !images.isEmpty {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                showingCamera = false
            }
        }
        .fullScreenCover(item: $activeDeckDesign) { design in
            DeckBuilderView(
                deckDesign: design,
                modelContext: modelContext,
                syncEngine: dataController.syncEngine,
                projectName: viewModel.currentOpportunity?.title
            )
        }
        .fullScreenCover(isPresented: $showingDimensionedCapture) {
            DimensionedCaptureView(
                projectId: "site-visit-\(viewModel.siteVisit?.id ?? UUID().uuidString)",
                projectName: viewModel.visitProjectTitle,
                companyId: viewModel.companyIdentifier,
                userId: dataController.currentUser?.id ?? "",
                developerFlagOverride: MeasureActionButton.usesDeveloperFlagOverride(
                    flagEnabled: PermissionStore.shared.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
                    capability: CaptureCapability.detect().capability
                ),
                saveOverride: { assets, dimensions in
                    try viewModel.addDimensionedCapture(
                        assets: assets,
                        dimensions: dimensions
                    )
                    return .synced
                },
                onSavedLocally: {
                    viewModel.reloadArtifacts()
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    showingDimensionedCapture = false
                },
                onError: { _ in
                    viewModel.errorMessage = "MEASURE PHOTO SAVE FAILED"
                    showingDimensionedCapture = false
                }
            )
        }
        .sheet(item: $markupArtifact) { artifact in
            SiteVisitPhotoMarkupView(
                artifact: artifact,
                persistMarkup: { url in
                    viewModel.saveMarkup(artifact, renderedAssetURL: url)
                },
                onSaved: { viewModel.reloadArtifacts() }
            )
        }
        .sheet(item: $previewArtifact) { artifact in
            SiteVisitPhotoPreviewSheet(artifact: artifact) {
                previewArtifact = nil
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    markupArtifact = artifact
                }
            }
        }
        .sheet(item: $editingNoteArtifact) { artifact in
            SiteVisitNoteEditSheet(artifact: artifact) { body in
                viewModel.updateNoteArtifact(artifact, body: body)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .background(
            ContactPicker(isPresented: $showingContactPicker) { contact in
                viewModel.applyImportedContact(contact)
            }
        )
        .sheet(isPresented: $showingReview) {
            SiteVisitReviewSheet(
                viewModel: viewModel,
                onCreateProject: onCreateProject,
                onSaved: {
                    // Saved without conversion — close the whole capture flow.
                    // The success toast is presented by the review sheet.
                    onClose()
                },
                onRequestLeadCapture: { pendingIdentityFocus = true }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingChecklistGuide) {
            SiteVisitChecklistGuideView(
                onOpenSettings: openChecklistSettingsFromGuide,
                onNotNow: { showingChecklistGuide = false },
                onNeverShowAgain: {
                    SiteVisitChecklistGuideStore().suppress(
                        userId: dataController.currentUser?.id
                    )
                    showingChecklistGuide = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
        .fullScreenCover(isPresented: $showingChecklistSettings) {
            NavigationStack {
                SiteVisitTypeSettingsView()
                    .environmentObject(dataController)
            }
        }
        .onChange(of: showingChecklistSettings) { wasShowing, isShowing in
            if wasShowing && !isShowing {
                viewModel.refreshSiteVisitTypesAfterSettings()
            }
        }
        .confirmationDialog(
            "CLOSE THIS VISIT?",
            isPresented: $showingCloseConfirm,
            titleVisibility: .visible
        ) {
            Button("SAVE DRAFT & CLOSE") {
                onClose()
            }
            Button("DISCARD VISIT", role: .destructive) {
                viewModel.discardVisit()
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                onClose()
            }
            Button("KEEP CAPTURING", role: .cancel) {}
        } message: {
            Text("Your draft is saved on this device — pick it back up anytime. Or discard it for good.")
        }
        .errorToast($viewModel.errorMessage, label: Feedback.Err.operationFailed)
    }

    private var header: some View {
        OPSScreenHeader(
            "SITE VISIT",
            leading: { OPSHeaderCloseButton(action: attemptClose) },
            trailing: {
                Button {
                    showingReview = true
                } label: {
                    Text("DONE")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(1.2)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundColor(viewModel.canComplete ? OPSStyle.Colors.invertedText : OPSStyle.Colors.text3)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(height: 40)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(viewModel.canComplete ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.surfaceHover)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canComplete)
            }
        )
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    private var resumeBanner: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                viewModel.resumeResumableVisit()
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("// RECOVER UNSAVED DRAFT · TAP TO PICK UP")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tanTextM)
                            .lineLimit(1)
                        Text(viewModel.resumableVisitSummary ?? "IN PROGRESS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)
                    }
                    Spacer(minLength: OPSStyle.Layout.spacing1)
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                viewModel.dismissResumePrompt()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss and start a new visit")
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .padding(.trailing, OPSStyle.Layout.spacing1)
        .padding(.vertical, OPSStyle.Layout.spacing1)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // Display readout (not an input card): a flat HUD header — visit identity +
    // live capture counts as L2 tiles — deliberately distinct from the elevated
    // glass input cards below it.
    private var statusStrip: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.visitDisplayName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .textCase(.uppercase)
                    .lineLimit(1)

                Text(viewModel.captureAddress.uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(2)
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                metricTile(label: "PHOTOS", value: viewModel.summary.photoCount)
                metricTile(label: "NOTES", value: viewModel.summary.noteCount)
                metricTile(label: "MEASURE", value: viewModel.summary.measurementCount)
                metricTile(label: "DECK", value: viewModel.summary.deckDesignCount)
            }

            Text("// SAVED ON THIS DEVICE · WORKS OFFLINE")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func metricTile(label: String, value: Int) -> some View {
        SiteVisitCaptureMetric(label: label, value: "\(value)")
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()
    }

    /// One tested sequence owns the form's information hierarchy. A bound
    /// lead's authoritative `aiSummary` sits after identity and before the
    /// checklist; nil or whitespace-only summaries add no empty chrome.
    private var primaryFormSections: some View {
        ForEach(
            SiteVisitPrimaryFormSemantics.orderedSections(
                boundLeadSummary: viewModel.currentOpportunity?.aiSummary,
                leadDescription: viewModel.currentOpportunity?.descriptionText
            )
        ) { section in
            primaryFormSection(section)
        }
    }

    @ViewBuilder
    private func primaryFormSection(_ section: SiteVisitPrimaryFormSection) -> some View {
        switch section {
        case .identity:
            SiteVisitIdentityPanel(
                viewModel: viewModel,
                isExpanded: $identityExpanded,
                isPresentingContactPicker: $showingContactPicker
            )
            .id(SiteVisitCaptureScrollTarget.identity)
        case .leadSummary(let presentation):
            SiteVisitLeadSummaryBand(presentation: presentation)
        case .checklist:
            checklistPanel
        case .notes:
            quickNotePanel
                .id(SiteVisitCaptureScrollTarget.notes)
        }
    }

    private var quickNotePanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            panelHeader("3 · NOTES", trailing: speechStateLabel)

            TextEditor(text: $viewModel.noteDraft)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 92)
                .padding(OPSStyle.Layout.spacing2)
                .focused($focusedField, equals: .note)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(speechManager.state == .recording ? OPSStyle.Colors.roseLineM : OPSStyle.Colors.line, lineWidth: 1)
                )

            if speechManager.state == .recording {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Circle()
                        .fill(OPSStyle.Colors.roseTextM)
                        .frame(width: 8, height: 8)
                        .opacity(recordingPulse ? 1.0 : 0.3)
                        .padding(.top, 4)
                    Text(speechManager.transcription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? "LISTENING…"
                         : speechManager.transcription)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .animation(nil, value: speechManager.transcription)
                }
                .onAppear {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                        recordingPulse = true
                    }
                }
                .onDisappear { recordingPulse = false }
            }

            HStack(spacing: OPSStyle.Layout.spacing2) {
                Button(action: toggleSpeech) {
                    Label(speechManager.state == .recording ? "STOP" : "DICTATE", systemImage: speechManager.state == .recording ? "stop.fill" : "mic.fill")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(speechManager.state == .recording ? OPSStyle.Colors.roseTextM : OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.surfaceHover)
                        )
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.commitNote()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Text("SAVE NOTE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(isNoteDraftEmpty ? OPSStyle.Colors.text3 : OPSStyle.Colors.invertedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(isNoteDraftEmpty ? OPSStyle.Colors.surfaceHover : OPSStyle.Colors.opsAccent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(isNoteDraftEmpty)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var isNoteDraftEmpty: Bool {
        viewModel.noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Display list (not an input card): the captured packet is rendered flat —
    // a labelled list of L2 artifact tiles, no glass frame — so it reads as
    // "what you've captured" rather than "a surface to act on".
    private var packetPanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Button {
                withAnimation(OPSStyle.Animation.standard) {
                    isPacketExpanded.toggle()
                }
            } label: {
                HStack {
                    panelHeader("CAPTURE PACKET", trailing: "\(viewModel.activeArtifacts.count) ITEMS")
                    Spacer()
                    Image(systemName: isPacketExpanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .buttonStyle(.plain)

            if isPacketExpanded {
                if viewModel.activeArtifacts.isEmpty {
                    Text("NO CAPTURE YET")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .frame(maxWidth: .infinity, minHeight: 72, alignment: .center)
                } else {
                    VStack(spacing: 8) {
                        ForEach(viewModel.activeArtifacts) { artifact in
                            SiteVisitArtifactRow(
                                artifact: artifact,
                                onPreview: artifact.pipesToProjectPhotos ? {
                                    previewArtifact = artifact
                                } : nil,
                                onMarkup: {
                                    markupArtifact = artifact
                                },
                                onEdit: artifact.pipesToProjectNotes ? {
                                    editingNoteArtifact = artifact
                                } : nil,
                                onIncludedChange: { included in
                                    viewModel.setIncluded(artifact, included: included)
                                }
                            )
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var checklistPanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                panelHeader(
                    "2 · CHECKLIST",
                    trailing: viewModel.selectedSiteVisitType?.name ?? "TYPE"
                )
                Spacer(minLength: OPSStyle.Layout.spacing1)
                if !viewModel.missingRequiredChecklistAnswers.isEmpty {
                    Text("\(viewModel.missingRequiredChecklistAnswers.count) REQ")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.tanTextM)
                }
            }

            if !viewModel.siteVisitTypes.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        ForEach(viewModel.siteVisitTypes) { type in
                            let isSelected = viewModel.selectedSiteVisitType?.id == type.id
                            Button {
                                viewModel.selectSiteVisitType(type)
                            } label: {
                                Text(type.name.uppercased())
                                    .font(OPSStyle.Typography.miniLabel)
                                    .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                                    .frame(height: OPSStyle.Layout.chipMinHeight)
                                    .background(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                            .fill(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                            .strokeBorder(isSelected ? OPSStyle.Colors.line : Color.clear, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        if canManageSiteVisitTypes {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showingChecklistSettings = true
                            } label: {
                                HStack(spacing: OPSStyle.Layout.spacing1) {
                                    Image(systemName: OPSStyle.Icons.adjust)
                                    Text("EDIT TYPES")
                                }
                                .font(OPSStyle.Typography.miniLabel)
                                .foregroundColor(OPSStyle.Colors.text2)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                                .background(
                                    RoundedRectangle(
                                        cornerRadius: OPSStyle.Layout.buttonRadius,
                                        style: .continuous
                                    )
                                    .fill(OPSStyle.Colors.surfaceInput)
                                )
                                .overlay(
                                    RoundedRectangle(
                                        cornerRadius: OPSStyle.Layout.buttonRadius,
                                        style: .continuous
                                    )
                                    .strokeBorder(
                                        OPSStyle.Colors.line,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Edit site visit types in Settings")
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            if viewModel.checklistAnswers.isEmpty {
                Text("NO CHECKLIST FIELDS")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .center)
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(viewModel.checklistAnswers) { answer in
                        SiteVisitChecklistAnswerRow(
                            answer: answer,
                            onUpdate: { value in
                                viewModel.updateChecklistAnswer(answer, value: value)
                            },
                            onStartDeckDesign: {
                                // EDIT opens the design linked to THIS row, not a
                                // re-derived (blank) one. START passes nil → create.
                                startDeckDesign(preferredDesignId: answer.answerValue.deckDesignId)
                            }
                        )
                    }
                }
                .padding(.bottom, OPSStyle.Layout.spacing1)
            }

            HStack(spacing: OPSStyle.Layout.spacing1) {
                TextField("ADD QUESTION", text: $customChecklistQuestion)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                    )

                Menu {
                    ForEach([
                        SiteVisitFieldKind.shortText,
                        .longText,
                        .measurement,
                        .checkbox,
                        .yesNoNA,
                        .photo,
                        .photoMarkup
                    ], id: \.self) { kind in
                        Button(kind.displayName) {
                            customChecklistKind = kind
                        }
                    }
                } label: {
                    Text(customChecklistKind.displayName)
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(width: 82, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.surfaceHover)
                        )
                }

                Button {
                    viewModel.addAdHocChecklistQuestion(
                        label: customChecklistQuestion,
                        kind: customChecklistKind
                    )
                    customChecklistQuestion = ""
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(width: 44, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.opsAccent)
                        )
                }
                .buttonStyle(.plain)
                .disabled(customChecklistQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(customChecklistQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private func openChecklistSettingsFromGuide() {
        SiteVisitChecklistGuideStore().suppress(
            userId: dataController.currentUser?.id
        )
        showingChecklistGuide = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            showingChecklistSettings = true
        }
    }

    private func actionBar(scrollProxy: ScrollViewProxy) -> some View {
        OPSActionBar {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                OPSActionBarButton(icon: "camera.fill", label: "PHOTO") {
                    showingCamera = true
                }
                Spacer(minLength: 0)
                OPSActionBarButton(icon: "note.text", label: "NOTE") {
                    focusNotes(scrollProxy: scrollProxy)
                }
                if canCaptureDimensionedPhoto {
                    Spacer(minLength: 0)
                    OPSActionBarButton(icon: "ruler", label: "MEASURE") {
                        startDimensionedCapture()
                    }
                }
                if canCaptureDeckDesign {
                    Spacer(minLength: 0)
                    OPSActionBarButton(icon: "square.grid.3x3", label: "DECK") {
                        startDeckDesign()
                    }
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private var canCaptureDeckDesign: Bool {
        ProjectQuickActionPermissionGate.canShowDeckAction(
            featureEnabled: PermissionStore.shared.isFeatureEnabled("deck_builder"),
            canCreate: PermissionStore.shared.can("deck_builder.create"),
            canEdit: PermissionStore.shared.can("deck_builder.edit")
        )
    }

    private var canCaptureDimensionedPhoto: Bool {
        MeasureActionButton.shouldRender(
            flagEnabled: PermissionStore.shared.isFeatureEnabled(MeasurementFlag.dimensionedCapture),
            capability: CaptureCapability.detect().capability
        )
    }

    private var speechStateLabel: String {
        switch speechManager.state {
        case .recording: return "RECORDING"
        case .stopping: return "SAVING"
        case .error: return "MIC ERROR"
        case .idle: return "TYPE · DICTATE"
        }
    }

    private func panelHeader(_ title: String, trailing: String) -> some View {
        HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(title)
                .foregroundColor(OPSStyle.Colors.text)
            Text("  ·  ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(trailing)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(OPSStyle.Typography.metadata)
        .textCase(.uppercase)
    }

    private func attemptClose() {
        if viewModel.hasCapturedAnything {
            showingCloseConfirm = true
        } else {
            onClose()
        }
    }

    private func toggleSpeech() {
        Task {
            let speechStatus = await SpeechRecognitionManager.requestAuthorization()
            guard speechStatus == .authorized else {
                speechManager.state = .error("SPEECH NOT AUTHORIZED")
                return
            }
            let micAccess = await SpeechRecognitionManager.requestMicrophoneAccess()
            guard micAccess else {
                speechManager.state = .error("MIC NOT AUTHORIZED")
                return
            }
            do {
                try speechManager.toggleRecording()
            } catch {
                speechManager.state = .error("MIC FAILED")
            }
        }
    }

    private func focusNotes(scrollProxy: ScrollViewProxy) {
        withAnimation(OPSStyle.Animation.standard) {
            scrollProxy.scrollTo(SiteVisitCaptureScrollTarget.notes, anchor: .top)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            focusedField = .note
        }
    }

    private func scheduleNoteAutosave() {
        noteAutosaveTask?.cancel()
        noteAutosaveTask = Task {
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                viewModel.autosaveNote()
            }
        }
    }

    private func startDeckDesign(preferredDesignId: String? = nil) {
        guard canCaptureDeckDesign else {
            viewModel.errorMessage = "DECK DESIGN UNAVAILABLE"
            return
        }

        // Continue before create: the exact design the caller asked for
        // (checklist EDIT), then the visit's own sketch, then the lead's
        // design (same display-candidate rule the lead page uses). DECK never
        // forks a duplicate — and the checklist row's EDIT genuinely edits the
        // linked design instead of quietly replacing it with a blank one.
        let allDesigns = (try? modelContext.fetch(FetchDescriptor<DeckDesign>())) ?? []
        let visitDesignIds = viewModel.activeArtifacts
            .filter { $0.kind == .deckDesign }
            .compactMap(\.deckDesignId)
        if let existing = SiteVisitDeckDesignResolver.existingDesign(
            preferredDesignId: preferredDesignId,
            artifactDesignIds: visitDesignIds,
            opportunityId: viewModel.currentOpportunity?.id,
            in: allDesigns
        ) {
            viewModel.attachDeckDesign(existing)   // idempotent — links, never dupes
            activeDeckDesign = existing
            return
        }

        let design = DeckDesign(
            companyId: viewModel.companyIdentifier,
            projectId: nil,
            // Bind the sketch to the lead the visit is for — it surfaces on
            // the lead detail immediately and re-parents to the project at
            // conversion (server-side, alongside the existing iOS handoff).
            opportunityId: viewModel.currentOpportunity?.id,
            title: viewModel.deckDesignTitle,
            createdBy: dataController.currentUser?.id
        )
        modelContext.insert(design)
        try? modelContext.save()
        viewModel.attachDeckDesign(design)
        activeDeckDesign = design
    }

    private func startDimensionedCapture() {
        guard canCaptureDimensionedPhoto else {
            viewModel.errorMessage = "MEASURE PHOTO UNAVAILABLE"
            return
        }
        showingDimensionedCapture = true
    }
}

private struct SiteVisitCaptureMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
            Text(label)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Read-only lead context at the exact decision point where the operator starts
/// scope capture. This reuses the lead surfaces' agent-provenance band instead
/// of introducing another card or a second editable summary field.
private struct SiteVisitLeadSummaryBand: View {
    let presentation: SiteVisitLeadSummaryPresentation

    /// The agent tint marks agent-written copy. A lead's own inquiry text is
    /// not that, so it reads in the neutral panel treatment — same band, same
    /// position, honest about who wrote it.
    private var isAgentWritten: Bool {
        presentation.source == .agentSummary
    }

    private var accentColor: Color {
        isAgentWritten ? OPSStyle.Colors.agent : OPSStyle.Colors.text2
    }

    private var fillColor: Color {
        isAgentWritten ? OPSStyle.Colors.agentSoft : OPSStyle.Colors.surfaceInput
    }

    private var railColor: Color {
        isAgentWritten ? OPSStyle.Colors.agentLine : OPSStyle.Colors.line
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(presentation.source.label)
                    .foregroundColor(accentColor)
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .textCase(.uppercase)

            Text(presentation.text)
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .padding(.leading, OPSStyle.Layout.Border.thick)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(fillColor)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(railColor)
                .frame(width: OPSStyle.Layout.Border.thick)
        }
        .clipShape(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cardRadius,
                style: .continuous
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
    }
}

private struct SiteVisitIdentityPanel: View {
    @ObservedObject var viewModel: SiteVisitCaptureViewModel

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    // Collapsed by default (owned by the console) — capture is the job,
    // identity is end-of-flow. The console can expand it to route the operator
    // here from the Review sheet when a project needs a linked lead.
    @Binding var isExpanded: Bool
    /// The picker is presented by the console, not here — see the console's
    /// `showingContactPicker`. This panel only asks for it.
    @Binding var isPresentingContactPicker: Bool
    @State private var searchText = ""
    @State private var clientName = ""
    @State private var contactName = ""
    @State private var preferredEmail = ""
    @State private var additionalEmailsText = ""
    @State private var phoneNumber = ""
    @State private var address = ""
    @State private var notes = ""
    @State private var activeLeads: [Opportunity] = []
    @State private var clients: [Client] = []
    @State private var autosaveTask: Task<Void, Never>?
    /// Until the fields above have been filled from the saved draft they hold
    /// empty strings, not edits. Committing them would erase the draft — the
    /// form-wipe half of bug 5d5df5b0.
    @State private var hasHydrated = false

    private var completionCount: Int {
        [
            clientName.trimmedNilIfEmpty,
            contactName.trimmedNilIfEmpty,
            preferredEmail.trimmedNilIfEmpty ?? additionalEmailsText.trimmedNilIfEmpty,
            phoneNumber.trimmedNilIfEmpty,
            address.trimmedNilIfEmpty
        ].compactMap { $0 }.count
    }

    private var isComplete: Bool {
        requirements.isComplete
    }

    // Bug (site-visit report) — the required-field groups, surfaced per field
    // so the operator can see exactly what a lead needs. A lead needs an
    // identity (a person's name OR a company), a way to reach them (email OR
    // phone), and a site address. COMPANY is optional — see
    // `SiteVisitIdentityRequirements`, which owns the rule for form and tests
    // alike.
    private var requirements: SiteVisitIdentityRequirements {
        .resolve(
            name: contactName,
            company: clientName,
            email: preferredEmail,
            additionalEmails: additionalEmailsText,
            phone: phoneNumber,
            address: address
        )
    }

    private var badgeText: String {
        if viewModel.hasBoundOpportunity { return "LINKED" }
        if isComplete { return "READY" }
        return "\(completionCount)/5"
    }

    private var badgeColor: Color {
        if viewModel.hasBoundOpportunity || isComplete { return OPSStyle.Colors.oliveTextM }
        return OPSStyle.Colors.tanTextM
    }

    private var suggestions: [SiteVisitIdentitySuggestion] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return [] }

        let currentOpportunityId = viewModel.currentOpportunity?.id
        let leadSuggestions = activeLeads
            .filter { $0.id != currentOpportunityId }
            .filter { lead in
                matches(query, values: [
                    lead.displayContactName,
                    lead.title,
                    lead.contactEmail,
                    lead.contactPhone,
                    lead.address
                ])
            }
            .prefix(4)
            .map(SiteVisitIdentitySuggestion.lead)

        let clientSuggestions = clients
            .filter { client in
                matches(query, values: [
                    client.name,
                    client.email,
                    client.phoneNumber,
                    client.address
                ] + client.subClients.flatMap { subClient in
                    [
                        subClient.name,
                        subClient.email,
                        subClient.phoneNumber,
                        subClient.address
                    ]
                })
            }
            .prefix(4)
            .map(SiteVisitIdentitySuggestion.client)

        return Array(leadSuggestions) + Array(clientSuggestions)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            header

            if isExpanded {
                searchField
                suggestionList

                if boundDisplayName == nil {
                    importContactsButton
                }

                let requirements = self.requirements
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    // NAME carries the identity requirement — a person's name,
                    // or a business when the business IS the client. COMPANY
                    // never advertises one: most visits are residential and
                    // there is no business to name.
                    identityField(
                        "NAME",
                        text: $contactName,
                        placeholder: "WHO YOU MET",
                        capitalization: .words,
                        requirement: requirements.name
                    )
                    identityField(
                        "COMPANY",
                        text: $clientName,
                        placeholder: "BUSINESS",
                        capitalization: .words,
                        requirement: requirements.company
                    )
                    // Email OR phone satisfies the contact-method requirement.
                    identityField(
                        "EMAIL",
                        text: $preferredEmail,
                        placeholder: "PRIMARY EMAIL",
                        keyboard: .emailAddress,
                        capitalization: .never,
                        requirement: requirements.email
                    )
                    identityField(
                        "OTHER EMAILS",
                        text: $additionalEmailsText,
                        placeholder: "ONE PER LINE OR COMMA SEPARATED",
                        keyboard: .emailAddress,
                        capitalization: .never,
                        axis: .vertical,
                        caption: "ADDED AS CONTACTS ON THE CLIENT"
                    )
                    identityField(
                        "PHONE",
                        text: $phoneNumber,
                        placeholder: "PHONE",
                        keyboard: .phonePad,
                        capitalization: .never,
                        requirement: requirements.phone
                    )
                    // Address is an autocomplete, not a free-text field
                    // (bugs e6a700ff / 0adf456b): suggestions-as-you-type plus
                    // a use-my-location reverse geocode. Selections arrive
                    // comma-canonical so the server's autoname derives the
                    // street-line project name, and they persist to the bound
                    // lead (with coordinates) immediately — a selection is a
                    // commit, unlike keystrokes.
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Text("ADDRESS")
                                .font(OPSStyle.Typography.miniLabel)
                                .foregroundColor(OPSStyle.Colors.text3)
                            Spacer(minLength: 0)
                            requirementMarker(requirements.address)
                        }

                        AddressAutocompleteField(
                            address: $address,
                            placeholder: "SITE ADDRESS",
                            onAddressSelected: { selected, coordinate in
                                viewModel.applySelectedSiteAddress(selected, coordinate: coordinate)
                            }
                        )
                    }
                    identityField(
                        "CLIENT NOTES",
                        text: $notes,
                        placeholder: "ACCESS, GATE, PARKING, OWNER NOTES",
                        capitalization: .sentences,
                        axis: .vertical
                    )
                }

                footer
            } else {
                collapsedSummary
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
        .task {
            // Hydrate FIRST. This used to await the network fetch below before
            // filling the fields, so for the length of that request the panel
            // held an empty mirror that autosave or `.onDisappear` could commit
            // straight over a saved draft (bug 5d5df5b0).
            syncFromDraft()
            hasHydrated = true
            await loadSearchSources()
        }
        .onChange(of: viewModel.contactImportGeneration) { _, _ in
            // A contact import writes the draft from the console. Re-mirror it —
            // the ONLY re-hydration after the first, so ordinary autosaves never
            // yank fields out from under the operator.
            syncFromDraft()
        }
        .onDisappear {
            autosaveTask?.cancel()
            commitDraft()
        }
        .onChange(of: searchText) { _, _ in scheduleAutosave() }
        .onChange(of: clientName) { _, _ in scheduleAutosave() }
        .onChange(of: contactName) { _, _ in scheduleAutosave() }
        .onChange(of: preferredEmail) { _, _ in scheduleAutosave() }
        .onChange(of: additionalEmailsText) { _, _ in scheduleAutosave() }
        .onChange(of: phoneNumber) { _, _ in scheduleAutosave() }
        .onChange(of: address) { _, _ in scheduleAutosave() }
        .onChange(of: notes) { _, _ in scheduleAutosave() }
    }

    private var header: some View {
        Button {
            withAnimation(OPSStyle.Animation.standard) {
                isExpanded.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: 0) {
                    Text("// ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text("1 · LEAD")
                        .foregroundColor(OPSStyle.Colors.text)
                    Text("  ·  ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(badgeText)
                        .foregroundColor(badgeColor)
                }
                .font(OPSStyle.Typography.metadata)

                Spacer(minLength: OPSStyle.Layout.spacing1)

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Lead and client details")
    }

    private var boundDisplayName: String? {
        if viewModel.hasBoundOpportunity {
            return viewModel.currentOpportunity?.displayContactName
                ?? contactName.trimmedNilIfEmpty
                ?? clientName.trimmedNilIfEmpty
        }
        if viewModel.activeClientId != nil {
            return contactName.trimmedNilIfEmpty ?? clientName.trimmedNilIfEmpty
        }
        return nil
    }

    @ViewBuilder
    private var searchField: some View {
        if let bound = boundDisplayName {
            // Linked to an existing lead/client — show who, with an X to clear.
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.oliveTextM)

                Text(bound.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: clearSelection) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear linked lead or client")
            }
            .padding(.leading, OPSStyle.Layout.spacing3)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
            )
        } else {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)

                TextField("SEARCH LEADS OR CLIENTS", text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.words)

                if searchText.trimmedNilIfEmpty != nil {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text3)
                            .frame(width: 32, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear search")
                }
            }
            .padding(.leading, OPSStyle.Layout.spacing3)
            .padding(.trailing, searchText.trimmedNilIfEmpty == nil ? OPSStyle.Layout.spacing3 : OPSStyle.Layout.spacing1)
            .frame(height: 48)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
    }

    private func clearSelection() {
        viewModel.clearIdentitySelection()
        syncFromDraft()
        searchText = ""
        UISelectionFeedbackGenerator().selectionChanged()
    }

    @ViewBuilder
    private var suggestionList: some View {
        if searchText.trimmedNilIfEmpty != nil {
            if suggestions.isEmpty {
                Text("NO LOCAL MATCH · FILL MANUAL FIELDS")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .center)
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(suggestions) { suggestion in
                        Button {
                            apply(suggestion)
                        } label: {
                            suggestionRow(suggestion)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var collapsedSummary: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 3) {
                Text((contactName.trimmedNilIfEmpty ?? clientName.trimmedNilIfEmpty ?? "UNLINKED VISIT").uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                Text((address.trimmedNilIfEmpty ?? "NO SITE ADDRESS").uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Text(badgeText)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(badgeColor)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
    }

    private var footer: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("LOCAL AUTOSAVE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)

            Spacer(minLength: OPSStyle.Layout.spacing1)

            if !viewModel.hasBoundOpportunity {
                Button {
                    Task {
                        commitDraft()
                        switch await viewModel.createLeadFromIdentityDraft(dataController: dataController) {
                        case .created:
                            syncFromDraft()
                            await loadSearchSources()
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                        case .queued(let offline):
                            // Saved and handed to the durable queue — not a
                            // failure. The toast carries its own haptic.
                            ToastCenter.shared.present(
                                offline ? Feedback.Lead.savedOffline : Feedback.Lead.savedSyncing
                            )
                        case .failed:
                            UINotificationFeedbackGenerator().notificationOccurred(.error)
                        }
                    }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if viewModel.isCommittingIdentity {
                            ProgressView()
                                .tint(OPSStyle.Colors.invertedText)
                                .scaleEffect(0.72)
                        } else {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        Text("CREATE LEAD")
                            .font(OPSStyle.Typography.miniLabel)
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(viewModel.canCreateLeadFromIdentity ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.surfaceHover)
                    )
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.canCreateLeadFromIdentity || viewModel.isCommittingIdentity)
                .opacity(viewModel.canCreateLeadFromIdentity ? 1 : 0.55)
            }
        }
    }

    /// Trailing REQUIRED → DONE marker. Speaks the same language as the
    /// checklist row's status label (tan when outstanding, olive when met)
    /// so the two halves of the form read as one checklist. `.optional`
    /// fields render no marker at all — an optional field says nothing.
    @ViewBuilder
    private func requirementMarker(_ requirement: SiteVisitIdentityFieldRequirement) -> some View {
        switch requirement {
        case .optional:
            EmptyView()
        case .required(let satisfied):
            HStack(spacing: 3) {
                Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 10, weight: .bold))
                Text(satisfied ? "DONE" : "REQUIRED")
                    .font(OPSStyle.Typography.miniLabel)
            }
            .foregroundColor(satisfied ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.tanTextM)
            .accessibilityLabel(satisfied ? "Done" : "Required")
        }
    }

    private func identityField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        keyboard: UIKeyboardType = .default,
        capitalization: TextInputAutocapitalization = .words,
        axis: Axis = .horizontal,
        caption: String? = nil,
        requirement: SiteVisitIdentityFieldRequirement = .optional
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.text3)
                Spacer(minLength: 0)
                requirementMarker(requirement)
            }

            TextField(placeholder, text: text, axis: axis)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .keyboardType(keyboard)
                .textInputAutocapitalization(capitalization)
                .autocorrectionDisabled(keyboard == .emailAddress || keyboard == .phonePad)
                .lineLimit(axis == .vertical ? 3 : 1)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .frame(minHeight: axis == .vertical ? 58 : 44, alignment: axis == .vertical ? .topLeading : .leading)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(
                            OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )

            if let caption {
                Text(caption)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
    }

    private func suggestionRow(_ suggestion: SiteVisitIdentitySuggestion) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: 3) {
                Text(suggestion.title.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                Text(suggestion.subtitle.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            Text(suggestion.badge)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(suggestion.badge == "LEAD" ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.text2)
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    private func apply(_ suggestion: SiteVisitIdentitySuggestion) {
        switch suggestion.source {
        case .lead(let lead):
            viewModel.reassignVisit(to: lead)
        case .client(let client):
            viewModel.bindClient(client)
        }
        syncFromDraft()
        searchText = ""
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func syncFromDraft() {
        guard let draft = viewModel.identityDraft else { return }
        searchText = draft.searchText
        clientName = draft.clientName
        contactName = draft.contactName
        preferredEmail = draft.preferredEmail
        additionalEmailsText = draft.additionalEmails.joined(separator: "\n")
        phoneNumber = draft.phoneNumber
        address = draft.address
        notes = draft.notes
    }

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                commitDraft()
            }
        }
    }

    private func commitDraft() {
        viewModel.updateIdentityDraft(
            searchText: searchText,
            clientName: clientName,
            contactName: contactName,
            preferredEmail: preferredEmail,
            additionalEmailsText: additionalEmailsText,
            phoneNumber: phoneNumber,
            address: address,
            notes: notes,
            isHydrated: hasHydrated
        )
    }

    /// Bug (site-visit report) — pull an existing person straight from the
    /// phone's address book instead of retyping them. Shown only while the
    /// visit is unlinked; a pick fills the identity draft.
    private var importContactsButton: some View {
        Button {
            isPresentingContactPicker = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                Text("IMPORT FROM CONTACTS")
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.text2)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Import from phone contacts")
    }

    private func loadSearchSources() async {
        // Bug (site-visit report) — leads are network-only; they are not
        // persisted in SwiftData (see [[opportunities-not-in-swiftdata]]), so
        // the old `FetchDescriptor<Opportunity>` always came back empty and
        // search never matched a lead. Pull the live opportunity store, and
        // fall back to whatever SwiftData holds only when offline.
        let repo = OpportunityRepository(companyId: viewModel.companyIdentifier)
        if let dtos = try? await repo.fetchAll() {
            activeLeads = dtos
                .map { $0.toModel() }
                .filter { !$0.stage.isTerminal && !$0.isDeleted && !$0.isArchived }
        } else {
            let opportunityDescriptor = FetchDescriptor<Opportunity>(
                sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
            )
            activeLeads = ((try? modelContext.fetch(opportunityDescriptor)) ?? [])
                .filter { lead in
                    lead.companyId == viewModel.companyIdentifier
                    && !lead.stage.isTerminal
                    && !lead.isDeleted
                    && !lead.isArchived
                }
        }

        let clientDescriptor = FetchDescriptor<Client>(
            sortBy: [SortDescriptor(\.name)]
        )
        clients = ((try? modelContext.fetch(clientDescriptor)) ?? [])
            .filter { client in
                (client.companyId == nil || client.companyId == viewModel.companyIdentifier)
                && client.deletedAt == nil
            }
    }

    private func matches(_ query: String, values: [String?]) -> Bool {
        values.contains { value in
            value?.lowercased().contains(query) == true
        }
    }
}

private struct SiteVisitIdentitySuggestion: Identifiable {
    enum Source {
        case lead(Opportunity)
        case client(Client)
    }

    let id: String
    let title: String
    let subtitle: String
    let badge: String
    let source: Source

    static func lead(_ lead: Opportunity) -> SiteVisitIdentitySuggestion {
        SiteVisitIdentitySuggestion(
            id: "lead-\(lead.id)",
            title: lead.displayContactName,
            subtitle: lead.address ?? lead.title ?? lead.stage.displayName,
            badge: "LEAD",
            source: .lead(lead)
        )
    }

    static func client(_ client: Client) -> SiteVisitIdentitySuggestion {
        let detail = [
            client.email,
            client.phoneNumber,
            client.address
        ]
            .compactMap { $0?.trimmedNilIfEmpty }
            .first ?? "CLIENT"
        return SiteVisitIdentitySuggestion(
            id: "client-\(client.id)",
            title: client.name,
            subtitle: detail,
            badge: "CLIENT",
            source: .client(client)
        )
    }
}

private struct SiteVisitChecklistAnswerRow: View {
    let answer: SiteVisitChecklistAnswer
    let onUpdate: (SiteVisitChecklistValue) -> Void
    let onStartDeckDesign: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(answer.label.uppercased())
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(2)
                    if let helpText = answer.helpText, !helpText.isEmpty {
                        Text(helpText.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing1)

                Text(statusLabel)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(statusColor)
            }

            control
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(answer.required && !answer.isAnswered ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var control: some View {
        switch answer.kind {
        case .checkbox:
            Toggle(isOn: Binding(
                get: { answer.answerValue.boolValue ?? false },
                set: { onUpdate(.bool($0)) }
            )) {
                Text("CONFIRMED")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text2)
            }
            .tint(OPSStyle.Colors.text3)
        case .yesNoNA:
            HStack(spacing: OPSStyle.Layout.spacing1) {
                choiceButton("YES")
                choiceButton("NO")
                choiceButton("N/A")
            }
        case .shortText, .longText, .measurement:
            // Measurement auto-fills from captured measurements; all three remain
            // freely editable.
            TextField("ANSWER", text: Binding(
                get: { answer.answerValue.text ?? "" },
                set: { onUpdate(.text($0)) }
            ), axis: .vertical)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.text)
            .textInputAutocapitalization(.sentences)
            .frame(minHeight: answer.kind == .longText ? 72 : 42, alignment: .topLeading)
        case .photo:
            // Site photos link automatically as they're captured — no action needed.
            capturedStatus(
                answer.answerValue.artifactIds.isEmpty
                    ? "TAKE PHOTOS — THEY LINK HERE AUTOMATICALLY"
                    : "\(answer.answerValue.artifactIds.count) PHOTOS LINKED",
                linked: !answer.answerValue.artifactIds.isEmpty
            )
        case .photoMarkup:
            capturedStatus(
                answer.answerValue.artifactIds.isEmpty
                    ? "TAKE PHOTOS — THEY LINK HERE AUTOMATICALLY"
                    : "\(answer.answerValue.artifactIds.count) ITEMS LINKED",
                linked: !answer.answerValue.artifactIds.isEmpty
            )
        case .deckDesign:
            HStack(spacing: OPSStyle.Layout.spacing1) {
                capturedStatus(
                    answer.answerValue.deckDesignId == nil ? "NO DESIGN YET" : "DESIGN LINKED",
                    linked: answer.answerValue.deckDesignId != nil
                )
                Spacer(minLength: OPSStyle.Layout.spacing1)
                Button(action: onStartDeckDesign) {
                    Text(answer.answerValue.deckDesignId == nil ? "START" : "EDIT")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(height: OPSStyle.Layout.touchTargetMin)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                .fill(OPSStyle.Colors.opsAccent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func capturedStatus(_ text: String, linked: Bool) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(linked ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.text3)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusLabel: String {
        if answer.isAnswered { return "DONE" }
        return answer.required ? "REQUIRED" : answer.kind.displayName
    }

    private var statusColor: Color {
        if answer.isAnswered { return OPSStyle.Colors.oliveTextM }
        return answer.required ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.text3
    }

    private func choiceButton(_ choice: String) -> some View {
        let selected = answer.answerValue.choice.map {
            $0.caseInsensitiveCompare(choice) == .orderedSame
        } ?? false
        return Button {
            onUpdate(.choice(choice))
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            Text(choice)
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(selected ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(selected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(selected ? OPSStyle.Colors.line : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

}

private struct SiteVisitArtifactRow: View {
    let artifact: SiteVisitCaptureArtifact
    let onPreview: (() -> Void)?
    let onMarkup: (() -> Void)?
    let onEdit: (() -> Void)?
    let onIncludedChange: (Bool) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            leadingVisual

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
                if let body = artifact.body, !body.isEmpty {
                    Text(body)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(2)
                } else {
                    Text(artifact.source.rawValue.replacingOccurrences(of: "_", with: " ").uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: OPSStyle.Layout.spacing1)

            if artifact.pipesToProjectPhotos, let onMarkup {
                Button(action: onMarkup) {
                    Image(systemName: "pencil.tip.crop.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Markup photo")
            }

            if artifact.pipesToProjectNotes, let onEdit {
                Button(action: onEdit) {
                    Image(systemName: OPSStyle.Icons.pencil)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Edit note")
            }

            // Whether this capture flows into the project when the visit converts.
            Button {
                onIncludedChange(!artifact.includedInProjectReview)
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: artifact.includedInProjectReview ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .regular))
                    Text(artifact.includedInProjectReview ? "IN PROJECT" : "SKIP")
                        .font(OPSStyle.Typography.miniLabel)
                }
                .foregroundColor(artifact.includedInProjectReview ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.text3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(artifact.includedInProjectReview ? "Included in project, tap to skip" : "Skipped, tap to include")
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var leadingVisual: some View {
        if artifact.pipesToProjectPhotos {
            Button {
                onPreview?()
            } label: {
                SiteVisitArtifactThumbnail(
                    artifact: artifact,
                    fallbackIcon: icon,
                    iconColor: iconColor
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("View photo")
        } else {
            iconTile
        }
    }

    private var iconTile: some View {
        Image(systemName: icon)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(iconColor)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceHover)
            )
    }

    private var title: String {
        artifact.title?.uppercased() ?? artifact.kind.rawValue.replacingOccurrences(of: "_", with: " ").uppercased()
    }

    private var icon: String {
        switch artifact.kind {
        case .photo: return "camera.fill"
        case .annotatedPhoto: return "pencil.tip.crop.circle.fill"
        case .dimensionedPhoto: return "viewfinder"
        case .note: return "note.text"
        case .transcript: return "mic.fill"
        case .measurement: return "ruler"
        case .deckDesign: return "square.grid.3x3"
        }
    }

    private var iconColor: Color {
        switch artifact.kind {
        case .dimensionedPhoto, .measurement, .deckDesign:
            return OPSStyle.Colors.tanTextM
        case .annotatedPhoto:
            return OPSStyle.Colors.opsAccent
        case .photo, .note, .transcript:
            return OPSStyle.Colors.text2
        }
    }
}

private struct SiteVisitNoteEditSheet: View {
    let artifact: SiteVisitCaptureArtifact
    let onSave: (String) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(
        artifact: SiteVisitCaptureArtifact,
        onSave: @escaping (String) -> Bool
    ) {
        self.artifact = artifact
        self.onSave = onSave
        _draft = State(initialValue: artifact.body ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack {
                Text("EDIT NOTE")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                Button("CANCEL") { dismiss() }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.text3)
            }

            TextEditor(text: $draft)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .scrollContentBackground(.hidden)
                .padding(OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin * 3)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                )
                .focused($isFocused)

            Button {
                guard onSave(draft) else { return }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } label: {
                Text("SAVE NOTE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(canSave ? OPSStyle.Colors.invertedText : OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(canSave ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.surfaceHover)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear { isFocused = true }
    }

    private var canSave: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

private struct SiteVisitArtifactThumbnail: View {
    let artifact: SiteVisitCaptureArtifact
    let fallbackIcon: String
    let iconColor: Color

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceHover)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(iconColor)
            }
        }
        .frame(width: 54, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
        .task(id: artifact.previewAssetURL ?? artifact.id) {
            loadImage()
        }
    }

    private func loadImage() {
        guard let url = artifact.previewAssetURL else {
            image = nil
            return
        }
        image = ImageFileManager.shared.loadCompositedImage(forURL: url)
            ?? ImageFileManager.shared.loadImage(localID: url)
    }
}

private struct SiteVisitReviewSheet: View {
    @ObservedObject var viewModel: SiteVisitCaptureViewModel
    let onCreateProject: (Opportunity) -> Void
    let onSaved: () -> Void
    let onRequestLeadCapture: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var previewArtifact: SiteVisitCaptureArtifact?
    @State private var editingNoteArtifact: SiteVisitCaptureArtifact?
    @State private var isCreatingLead = false
    @State private var isSaving = false
    // Bug (site-visit report) — the lead stage the visit will leave the lead
    // in. Seeded from SiteVisitStageDefault (QUALIFYING for a new lead; held
    // otherwise); the operator can change it. Never WON.
    @State private var selectedStage: PipelineStage?

    init(
        viewModel: SiteVisitCaptureViewModel,
        onCreateProject: @escaping (Opportunity) -> Void,
        onSaved: @escaping () -> Void,
        onRequestLeadCapture: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onCreateProject = onCreateProject
        self.onSaved = onSaved
        self.onRequestLeadCapture = onRequestLeadCapture
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetTitleLabel(title: "REVIEW VISIT", size: .full)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        summaryCard
                        if viewModel.hasBoundOpportunity {
                            stageCard
                        }
                        includedList
                        checklistReviewList
                        if canCreateProject {
                            createProjectCard
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing2)
                    .padding(.bottom, 132)
                }
            }

            SheetFooterButtonRow {
                SheetCTAButton(label: "BACK", variant: .secondary) {
                    dismiss()
                }
            } primary: {
                SheetCTAButton(
                    label: isSaving ? "SAVING…" : "SAVE VISIT",
                    icon: "checkmark",
                    variant: .primary,
                    action: saveVisit
                )
                .disabled(!viewModel.canComplete || isSaving)
                .opacity(viewModel.canComplete && !isSaving ? 1 : 0.5)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 28)
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0), Color.black.opacity(0.95), .black],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 170)
                .allowsHitTesting(false),
                alignment: .bottom
            )
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selectedStage == nil, let current = viewModel.currentOpportunity?.stage {
                selectedStage = SiteVisitStageDefault.defaultStage(current: current)
            }
        }
        .sheet(item: $previewArtifact) { artifact in
            SiteVisitPhotoPreviewSheet(artifact: artifact, onMarkup: nil)
        }
        .sheet(item: $editingNoteArtifact) { artifact in
            SiteVisitNoteEditSheet(artifact: artifact) { body in
                viewModel.updateNoteArtifact(artifact, body: body)
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.hidden)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Projected auto-name readout — NOT an input. The old editable
            // "PROJECT NAME" field here fed a dead payload field and silently
            // lost whatever was typed; naming is decided on the convert sheet
            // that opens next (AUTO by default, RENAME affordance there).
            // This mirrors the server's derive_project_name so the operator
            // sees the street-line name the project will actually get.
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("PROJECT · ")
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(viewModel.projectedProjectName.uppercased())
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)
            }
            .font(OPSStyle.Typography.metadata)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                SiteVisitCaptureMetric(label: "PHOTOS", value: "\(viewModel.summary.photoCount)")
                SiteVisitCaptureMetric(label: "NOTES", value: "\(viewModel.summary.noteCount)")
                SiteVisitCaptureMetric(label: "MEASURE", value: "\(viewModel.summary.measurementCount)")
                SiteVisitCaptureMetric(label: "DECK", value: "\(viewModel.summary.deckDesignCount)")
            }

            if !viewModel.missingRequiredChecklistAnswers.isEmpty {
                Text("REQUIRED :: " + viewModel.missingRequiredChecklistAnswers.map(\.label).joined(separator: " · ").uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .lineLimit(3)
            }

            if !viewModel.hasBoundOpportunity {
                leadLinkPrompt
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    /// A project needs a lead. Rather than dead-ending on a static warning,
    /// finish in place: if the operator already filled the identity draft, create
    /// the lead right here; otherwise route them straight to the identity panel.
    @ViewBuilder
    private var leadLinkPrompt: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// LINK A LEAD TO CREATE THE PROJECT")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tanTextM)

            if viewModel.canCreateLeadFromIdentity {
                Button {
                    Task { await createLeadInline() }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        if isCreatingLead {
                            ProgressView()
                                .tint(OPSStyle.Colors.invertedText)
                                .scaleEffect(0.8)
                        } else {
                            Image(systemName: "person.badge.plus")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        }
                        Text("CREATE LEAD")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.opsAccent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCreatingLead)
            } else {
                Button {
                    onRequestLeadCapture()
                    dismiss()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text("ADD LEAD DETAILS")
                            .font(OPSStyle.Typography.captionBold)
                        Image(systemName: "arrow.right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.surfaceHover)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func createLeadInline() async {
        isCreatingLead = true
        defer { isCreatingLead = false }
        switch await viewModel.createLeadFromIdentityDraft(dataController: dataController) {
        case .created:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .queued(let offline):
            ToastCenter.shared.present(
                offline ? Feedback.Lead.savedOffline : Feedback.Lead.savedSyncing
            )
        case .failed:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    private var includedList: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("PIPE INTO PROJECT")
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .font(OPSStyle.Typography.metadata)

            ForEach(viewModel.activeArtifacts) { artifact in
                SiteVisitArtifactRow(
                    artifact: artifact,
                    onPreview: artifact.pipesToProjectPhotos ? {
                        previewArtifact = artifact
                    } : nil,
                    onMarkup: nil,
                    onEdit: artifact.pipesToProjectNotes ? {
                        editingNoteArtifact = artifact
                    } : nil,
                    onIncludedChange: { included in
                        viewModel.setIncluded(artifact, included: included)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var checklistReviewList: some View {
        if !viewModel.checklistAnswers.isEmpty {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack(spacing: 0) {
                    Text("// ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text("CHECKLIST")
                        .foregroundColor(OPSStyle.Colors.text)
                    Text("  ·  ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(viewModel.selectedSiteVisitType?.name.uppercased() ?? "SITE VISIT")
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .font(OPSStyle.Typography.metadata)

                ForEach(viewModel.checklistAnswers) { answer in
                    HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(answer.label.uppercased())
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.text)
                            Text(reviewValue(for: answer))
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(answer.isAnswered ? OPSStyle.Colors.text3 : OPSStyle.Colors.textMute)
                                .lineLimit(3)
                        }

                        Spacer(minLength: OPSStyle.Layout.spacing1)

                        Text(answer.isAnswered ? "DONE" : (answer.required ? "REQUIRED" : "OPEN"))
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(
                                answer.isAnswered
                                ? OPSStyle.Colors.oliveTextM
                                : (answer.required ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.text3)
                            )
                    }
                    .padding(OPSStyle.Layout.spacing2)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .strokeBorder(answer.required && !answer.isAnswered ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.line, lineWidth: 1)
                    )
                }
            }
        }
    }

    private var canCreateProject: Bool {
        viewModel.hasProjectEvidence
        && viewModel.hasBoundOpportunity
        && viewModel.missingRequiredChecklistAnswers.isEmpty
    }

    private func reviewValue(for answer: SiteVisitChecklistAnswer) -> String {
        let value = answer.answerValue
        switch answer.kind {
        case .checkbox:
            guard let boolValue = value.boolValue else { return "—" }
            return boolValue ? "YES" : "NO"
        case .yesNoNA:
            return value.choice?.uppercased() ?? "—"
        case .shortText, .longText, .measurement:
            let trimmed = value.text?.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed?.nilIfEmpty ?? "—"
        case .photo, .photoMarkup:
            return value.artifactIds.isEmpty ? "—" : "\(value.artifactIds.count) CAPTURED"
        case .deckDesign:
            return value.deckDesignId == nil ? "—" : "DESIGN LINKED"
        }
    }

    // Bug (site-visit report) — the lead's stage after this visit. Defaults to
    // QUALIFYING for a fresh lead (never WON); the operator can pick any
    // non-terminal stage. Chips mirror the capture console's type selector.
    private var stageCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("LEAD STAGE AFTER VISIT")
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .font(OPSStyle.Typography.metadata)

            ScrollView(.horizontal) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(SiteVisitStageDefault.selectableStages) { stage in
                        let isSelected = selectedStage == stage
                        Button {
                            selectedStage = stage
                            UISelectionFeedbackGenerator().selectionChanged()
                        } label: {
                            Text(stage.displayName)
                                .font(OPSStyle.Typography.miniLabel)
                                .foregroundColor(isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                                .frame(height: OPSStyle.Layout.chipMinHeight)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                        .fill(isSelected ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                                        .strokeBorder(isSelected ? OPSStyle.Colors.line : Color.clear, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    /// The explicit, opt-in conversion path — deliberately secondary to SAVE
    /// VISIT so a visit save never converts by default. Reachable only when the
    /// visit has project-ready evidence and a bound lead.
    private var createProjectCard: some View {
        Button(action: createProject) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("CREATE PROJECT NOW")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.text)
                    Text("CONVERTS THIS LEAD INTO A PROJECT")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text2)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// SAVE VISIT — completes the visit WITHOUT converting the lead, moving it
    /// to the selected stage (QUALIFYING by default). The lifeline: a visit is
    /// saved, the lead advances a notch, nobody is auto-marked WON.
    private func saveVisit() {
        guard viewModel.canComplete, !isSaving else { return }
        isSaving = true
        let stage = selectedStage
        Task {
            let result: SiteVisitSaveResult
            if let stage {
                result = await viewModel.saveVisit(movingLeadTo: stage)
            } else {
                // Unbound visit — nothing to re-stage; just complete it.
                let completion = await viewModel.completeVisit()
                switch completion {
                case .committed:
                    result = .committed
                case .notCommitted(let failure):
                    result = .notCommitted(failure)
                }
            }
            await MainActor.run {
                isSaving = false
                guard result.visitWasCommitted else {
                    ToastCenter.shared.present(Feedback.SiteVisit.notSaved)
                    return
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if result == .committedStageUpdateFailed {
                    ToastCenter.shared.present(Feedback.SiteVisit.savedStageNotUpdated)
                } else {
                    ToastCenter.shared.present(Feedback.SiteVisit.saved)
                }
                dismiss()
                onSaved()
            }
        }
    }

    private func createProject() {
        guard canCreateProject,
              let opportunity = viewModel.currentOpportunity,
              !isSaving else { return }
        isSaving = true
        Task {
            let completion = await viewModel.completeVisit()
            await MainActor.run {
                isSaving = false
                guard completion.isCommitted else {
                    ToastCenter.shared.present(Feedback.SiteVisit.notSaved)
                    return
                }
                guard let payload = viewModel.projectPayload() else {
                    ToastCenter.shared.present(Feedback.SiteVisit.projectNotStarted)
                    return
                }
                SiteVisitProjectHandoffStore.shared.stage(payload, for: opportunity.id)
                dismiss()
                onCreateProject(opportunity)
            }
        }
    }
}

private struct SiteVisitPhotoPreviewSheet: View {
    @Bindable var artifact: SiteVisitCaptureArtifact
    let onMarkup: (() -> Void)?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                if let url = artifact.previewAssetURL {
                    ZoomablePhotoView(url: url)
                        .ignoresSafeArea()
                } else {
                    Text("PHOTO NOT AVAILABLE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .navigationTitle("PHOTO")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CLOSE") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.text2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if let onMarkup {
                        Button("MARKUP") {
                            dismiss()
                            onMarkup()
                        }
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

private struct SiteVisitPhotoMarkupView: View {
    @Bindable var artifact: SiteVisitCaptureArtifact
    let persistMarkup: (String) -> Bool
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var drawing = PKDrawing()
    @State private var canvasSize = CGSize(width: 1, height: 1)
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                if let image {
                    ZoomablePhotoAnnotationCanvas(
                        image: image,
                        drawing: $drawing,
                        displayedCanvasSize: $canvasSize
                    )
                    .ignoresSafeArea()
                } else {
                    Text("PHOTO NOT AVAILABLE")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .navigationTitle("MARKUP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.text2)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("SAVE") { saveMarkup() }
                        .foregroundColor(OPSStyle.Colors.opsAccent)
                        .disabled(image == nil)
                }
            }
        }
        .task {
            loadImage()
        }
        .errorToast($errorMessage, label: Feedback.Err.operationFailed)
    }

    private func loadImage() {
        let url = artifact.renderedAssetURL ?? artifact.localAssetURL ?? ""
        image = ImageFileManager.shared.loadImage(localID: url)
    }

    private func saveMarkup() {
        guard let image else { return }
        let rendered = renderComposite(base: image)
        guard let data = rendered.jpegData(compressionQuality: 0.86) else {
            errorMessage = "MARKUP SAVE FAILED"
            return
        }

        let localID = "site_visit_markup_\(artifact.id).jpg"
        let url = "local://project_images/\(localID)"
        guard ImageFileManager.shared.saveImage(data: data, localID: url) else {
            errorMessage = "MARKUP SAVE FAILED"
            return
        }

        guard persistMarkup(url) else {
            errorMessage = "MARKUP SAVE FAILED"
            return
        }
        onSaved()
        dismiss()
    }

    private func renderComposite(base: UIImage) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: base.size)
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: base.size))
            guard canvasSize.width > 1, canvasSize.height > 1 else { return }
            let drawingBounds = CGRect(origin: .zero, size: canvasSize)
            let overlay = drawing.image(
                from: drawingBounds,
                scale: max(base.size.width / canvasSize.width, base.size.height / canvasSize.height)
            )
            overlay.draw(in: CGRect(origin: .zero, size: base.size))
        }
    }
}
