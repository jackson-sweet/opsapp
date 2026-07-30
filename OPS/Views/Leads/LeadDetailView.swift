//
//  LeadDetailView.swift
//  OPS
//
//  The lead dossier (Leads redesign 2026-07-17, spec §5). Pushed from a
//  triage row tap on LeadsTabView. Composition (top → bottom):
//
//      [site map — fixed behind, content scrolls over]   ← LeadMapHeader
//      ‹ LEADS                              [QUOTED ▾]   ← nav + status chip
//      // L-XXXXXX · 9D IN STAGE
//      Roof tear-off, 28 sq                              ← DetailHero (title first)
//      Helen Calloway · Calloway Homes
//      1240 Maple Ave
//      // ASSIGNED TO row
//      [VALUE | NEXT TOUCH | SOURCE]
//      [→ YOUR MOVE · 2D            HANDLED ✓]           ← LeadChaseStrip
//      // SUMMARY · UPDATED 2D AGO   (agent rail)
//      [CONTACT ▾]                        [⋯]            ← action pair
//      // WON · NOT CONVERTED   [conditional]
//      // DETAILS  CLIENT/PROJECT/DECK/PHOTOS/FILES      ← LeadDetailsDocument
//      // ACTIVITY · N  (one stream, VIEW ALL →)         ← ActivityTimeline
//      [✎ EDIT]              [MARK WON →]                ← StickyActionBar
//
//  Sticky action bar is hidden when `opportunity.stage.isTerminal`. LOST /
//  ARCHIVE / DISCARD live in the status chip's menu; EDIT / WON closures
//  route up to LeadsTabView's `.sheet(item:)`.
//
//  Spec: docs/superpowers/specs/2026-07-17-leads-tab-redesign-design.md §5
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct LeadDetailView: View {
    let opportunity: Opportunity

    /// Routes to `LeadsSheet.lost(opportunity)` in the parent.
    var onMarkLost: () -> Void = {}
    /// Routes to `LeadsSheet.edit(opportunity)` in the parent.
    var onEdit:     () -> Void = {}
    /// Routes to `LeadsSheet.convert(opportunity)` in the parent.
    /// Also bound to the WON · NOT CONVERTED card's primary button.
    var onMarkWon:  () -> Void = {}
    /// Routes a site-visit handoff to conversion for the lead currently attached
    /// to the visit. This can differ from `opportunity` after reassignment.
    var onConvertLead: (Opportunity) -> Void = { _ in }

    @StateObject private var vm: LeadDetailViewModel
    @StateObject private var assignmentViewModel: LeadAssignmentViewModel
    @Query private var allUsers: [User]
    @State private var showingSiteVisitCapture = false
    @State private var showingAssignmentPicker = false
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @ObservedObject private var conversionVisibilityStore = LeadConversionVisibilityStore.shared

    // Photos on the lead
    @State private var showingAddPhotoDialog = false
    @State private var showingCameraCapture = false
    @State private var showingPhotoLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var photoViewerState: LeadPhotoViewerState?

    // Deck design on the lead
    @State private var showingDeckCreationPicker = false
    @State private var deckDesignToOpen: DeckDesign?

    // Share lead summary
    @State private var isAssemblingShare = false

    // Status-menu guarded exits (Leads redesign spec §6)
    @State private var archiveConfirm: OPSConfirmConfig?
    @State private var discardTarget: Opportunity?

    // Chase strip on detail (spec §5.6) — a single-lead PipelineViewModel so
    // markHandled / adjustComeback / bucketOf run the EXACT engine the queue
    // uses, mutating the same Opportunity instance by reference.
    @StateObject private var chaseVM = PipelineViewModel()
    @State private var comebackTarget: Opportunity?

    // CONTACT ▾ + ⋯ pair (spec §5.8)
    @State private var showingContactDialog = false
    @State private var showingLogActivity = false

    // Details document (spec §5.9)
    @State private var isAddingToClient = false
    @State private var showingClientDetail = false
    @State private var estimateToOpen: Estimate?
    @State private var isFetchingAttachment = false

    // One activity stream (spec §5.10)
    @State private var showingActivityHistory = false

    init(
        opportunity: Opportunity,
        onMarkLost: @escaping () -> Void = {},
        onEdit:     @escaping () -> Void = {},
        onMarkWon:  @escaping () -> Void = {},
        onConvertLead: @escaping (Opportunity) -> Void = { _ in }
    ) {
        self.opportunity = opportunity
        self.onMarkLost = onMarkLost
        self.onEdit = onEdit
        self.onMarkWon = onMarkWon
        self.onConvertLead = onConvertLead
        _vm = StateObject(wrappedValue: LeadDetailViewModel(
            opportunityId: opportunity.id,
            companyId: opportunity.companyId,
            clientId: opportunity.clientId
        ))
        _assignmentViewModel = StateObject(
            wrappedValue: LeadAssignmentViewModel(opportunity: opportunity)
        )
    }

    private var leadAccessPolicy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private var canEdit: Bool {
        leadAccessPolicy.can(.edit, assignedTo: opportunity.assignedTo)
    }
    private var canConvert: Bool {
        leadAccessPolicy.can(.convert, assignedTo: opportunity.assignedTo)
    }
    private var canChangeAssignee: Bool {
        guard leadAccessPolicy.can(.assign, assignedTo: opportunity.assignedTo),
              let scope = leadAccessPolicy.scope(for: .assign) else {
            return false
        }

        switch scope {
        case .all:
            return true
        case .assigned:
            return !opportunity.stage.isTerminal && !opportunity.isArchived
        }
    }

    /// The map hero needs coordinates — an address string alone can't render
    /// a map. No coordinates → plain canvas, zero layout shift (spec §5.1).
    private var mapCoordinates: (lat: Double, lon: Double)? {
        guard let lat = opportunity.latitude, let lon = opportunity.longitude else { return nil }
        return (lat, lon)
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()
            Atmosphere(tone: atmosphereTone)

            ZStack(alignment: .top) {
                // Layer 1: fixed map background (ProjectDetailsView treatment)
                if let coords = mapCoordinates {
                    VStack(spacing: 0) {
                        LeadMapHeaderSection(
                            latitude: coords.lat,
                            longitude: coords.lon,
                            pinLabel: opportunity.displayContactName,
                            onMapTap: { openDirections() }
                        )
                        Spacer()
                    }
                    .ignoresSafeArea(edges: .top)
                }

                // Layer 2: nav + content scrolling over the map
                VStack(spacing: 0) {
                    DetailNavBar(
                        onBack: {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            dismiss()
                        },
                        trailing: { statusChip }
                    )
                    .background(navScrim)

                    ScrollView {
                        VStack(spacing: 0) {
                            if mapCoordinates != nil {
                                // Open map area — taps anywhere over the visible
                                // map launch directions (the spacer sits on top
                                // of the map layer, so it owns these taps).
                                // 198pt of the map stays under the document —
                                // deep enough that the snapshot's baked-in
                                // Mapbox watermark region can never surface,
                                // including through top rubber-band overscroll.
                                Color.clear
                                    .frame(height: LeadMapHeader.mapHeight - 198)
                                    .contentShape(Rectangle())
                                    .onTapGesture { openDirections() }

                                mapScrollGradient
                            }

                            VStack(spacing: 0) {
                                DetailHero(
                                    opportunity: opportunity,
                                    clientName: vm.client?.name,
                                    assigneeName: currentAssigneeName,
                                    canChangeAssignee: canChangeAssignee,
                                    onAssigneeTap: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        showingAssignmentPicker = true
                                    }
                                )

                                // Chase strip — the same control as the card (spec §5.6)
                                if !opportunity.stage.isTerminal {
                                    LeadChaseStrip(
                                        lead: opportunity,
                                        bucket: chaseVM.bucketOf(opportunity),
                                        canAct: canEdit,
                                        canSendFollowUp: chaseVM.canSendFollowUp(for: opportunity),
                                        followUpProgress: chaseVM.followUpProgress(for: opportunity.id),
                                        actorUserId: chaseVM.currentUserId,
                                        onHandled: { markHandledFromDetail() },
                                        onReviewFollowUp: {
                                            await chaseVM.previewFollowUp(
                                                opportunityId: opportunity.id
                                            )
                                        },
                                        onSendFollowUp: { sendFollowUpFromDetail() },
                                        onAdjust: { comebackTarget = opportunity }
                                    )
                                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                }

                                // Agent summary — always open on detail (spec §5.7)
                                if let summary = agentSummary {
                                    summarySection(summary)
                                        .padding(.top, 22)
                                }

                                // CONTACT ▾ + ⋯ action pair (spec §5.8)
                                actionPair
                                    .padding(.top, 22)

                                if canConvert && showWonNotConverted {
                                    WonNotConvertedCard(onConvert: onMarkWon)
                                        .padding(.top, 22)
                                }

                                LeadDetailsDocument(
                                    lead: opportunity,
                                    client: vm.client,
                                    rosterState: rosterState,
                                    canEdit: canEdit,
                                    canMatchProject: canConvert && showWonNotConverted,
                                    projectName: linkedProjectName,
                                    attachments: vm.attachments,
                                    estimates: vm.estimates,
                                    correspondence: vm.latestCorrespondence,
                                    isAddingToClient: isAddingToClient,
                                    onAddToClient: { addContactToClient() },
                                    onOpenClient: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        showingClientDetail = true
                                    },
                                    onOpenProject: { openLinkedProject() },
                                    onMatchProject: {
                                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                        onMarkWon()
                                    },
                                    onOpenDeck: { design in deckDesignToOpen = design },
                                    onCreateDeck: { showingDeckCreationPicker = true },
                                    onAddPhotos: { showingAddPhotoDialog = true },
                                    onTapPhoto: { items, index in
                                        photoViewerState = LeadPhotoViewerState(items: items, initialIndex: index)
                                    },
                                    onOpenAttachment: { openAttachment($0) },
                                    onOpenEstimate: { estimateToOpen = $0 }
                                )
                                .padding(.top, 22)

                                ActivityTimeline(
                                    activities: vm.activities,
                                    transitions: vm.stageTransitions,
                                    onViewAll: { showingActivityHistory = true }
                                )
                                .padding(.top, 22)
                            }
                            .background(OPSStyle.Colors.background)
                        }
                        .padding(.bottom, 200)   // clears the sticky action bar
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if (canEdit || canConvert) && !opportunity.stage.isTerminal {
                StickyActionBar(
                    canEdit: canEdit,
                    canConvert: canConvert,
                    onEdit:     onEdit,
                    onMarkWon:  onMarkWon
                )
                .padding(.bottom, 49)   // clears the custom tab bar (49pt)
            }
        }
        .navigationBarHidden(true)
        .opsConfirm($archiveConfirm)
        .leadDiscardFlow(
            target: $discardTarget,
            onCompleted: { _, _ in dismiss() }
        )
        .sheet(item: $comebackTarget) { lead in
            ComebackChooserSheet(lead: lead, viewModel: chaseVM)
        }
        .sheet(isPresented: $showingLogActivity) {
            UnifiedLogActivitySheet(viewModel: UnifiedLogActivityViewModel(entry: .leadDetail(opportunity)))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .navigationDestination(item: $estimateToOpen) { estimate in
            EstimateDetailViewDeepLinkWrapper(estimate: estimate, companyId: opportunity.companyId)
        }
        .navigationDestination(isPresented: $showingActivityHistory) {
            LeadActivityHistoryView(
                activities: vm.activities,
                transitions: vm.stageTransitions
            )
        }
        .confirmationDialog(
            "CONTACT",
            isPresented: $showingContactDialog,
            titleVisibility: .visible
        ) {
            if let phone = opportunity.contactPhone, !phone.isEmpty {
                Button("CALL \(phone)") { placeCallFromDetail() }
                Button("TEXT") { touchTextFromDetail() }
            }
            if let email = opportunity.contactEmail, !email.isEmpty {
                Button("EMAIL \(email)") { touchEmailFromDetail() }
            }
            Button("CANCEL", role: .cancel) {}
        }
        .task {
            chaseVM.setup(
                companyId: opportunity.companyId,
                currentUserId: dataController.currentUser?.id
            )
            chaseVM.allOpportunities = [opportunity]
            await vm.loadAll()
        }
        .onAppear {
            if let context = dataController.modelContext {
                LeadImageService.shared.configure(modelContext: context)
            }
            Task { await LeadImageService.shared.drain() }
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("LeadActivityLoggedSuccess")
            )
        ) { notification in
            guard LeadDetailViewModel.activityNotificationTargets(
                notification,
                opportunityId: opportunity.id
            ) else { return }
            Task { await vm.reloadActivities() }
        }
        .fullScreenCover(isPresented: $showingSiteVisitCapture) {
            SiteVisitCaptureView(
                opportunity: opportunity,
                onCreateProject: { lead in
                    if lead.id == opportunity.id {
                        onMarkWon()
                    } else {
                        onConvertLead(lead)
                    }
                }
            )
        }
        .confirmationDialog(
            "ADD PHOTOS",
            isPresented: $showingAddPhotoDialog,
            titleVisibility: .visible
        ) {
            Button("TAKE PHOTOS") { showingCameraCapture = true }
            Button("CHOOSE FROM LIBRARY") { showingPhotoLibrary = true }
            Button("CANCEL", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCameraCapture) {
            CameraBatchView { images in
                showingCameraCapture = false
                guard !images.isEmpty else { return }
                addPhotos(images)
            }
        }
        .photosPicker(
            isPresented: $showingPhotoLibrary,
            selection: $libraryItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            libraryItems = []
            Task { await importLibraryItems(items) }
        }
        .fullScreenCover(item: $photoViewerState) { state in
            LeadPhotoViewer(
                opportunity: opportunity,
                canManage: canEdit,
                initialState: state
            )
        }
        .sheet(isPresented: $showingDeckCreationPicker) {
            deckCreationPicker
        }
        .sheet(isPresented: $showingAssignmentPicker) {
            LeadAssignmentSheet(
                viewModel: assignmentViewModel,
                isOnline: dataController.isConnected,
                onMutation: handleAssignmentMutation
            )
        }
        // CLIENT row → the canonical contact surface (same as every other
        // client tap app-wide: JobBoard, universal search, Spotlight).
        .sheet(isPresented: $showingClientDetail) {
            if let client = vm.client {
                ContactDetailView(client: client, project: nil)
                    .environmentObject(dataController)
                    .environmentObject(permissionStore)
            }
        }
        .fullScreenCover(item: $deckDesignToOpen) { design in
            deckBuilder(design: design)
        }
    }

    // MARK: - Photos

    private func addPhotos(_ images: [UIImage]) {
        Task {
            let result = await LeadImageService.shared.addImages(images, to: opportunity)
            if result.failedCount > 0 {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            } else if !result.uploadedURLs.isEmpty || result.queuedCount > 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func importLibraryItems(_ items: [PhotosPickerItem]) async {
        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                images.append(image)
            }
        }
        guard !images.isEmpty else { return }
        addPhotos(images)
    }

    // MARK: - Deck design

    @ViewBuilder
    private var deckCreationPicker: some View {
        // Picker dismisses BEFORE the builder presents — iOS can't stack two
        // modals (same dance as ProjectDetailsView's deck creation, bug 1).
        CreationPickerView(
            projectId: nil,
            opportunityId: opportunity.id,
            companyId: opportunity.companyId,
            userId: dataController.currentUser?.id,
            onDesignCreated: { design in
                showingDeckCreationPicker = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    deckDesignToOpen = design
                }
            }
        )
        .presentationDetents([.medium])
    }

    @ViewBuilder
    private func deckBuilder(design: DeckDesign) -> some View {
        if let modelContext = dataController.modelContext {
            DeckBuilderView(
                deckDesign: design,
                modelContext: modelContext,
                syncEngine: dataController.syncEngine,
                projectName: opportunity.displayContactName
            )
        }
    }

    // MARK: - Agent summary (spec §5.7 — always open on detail)

    private var agentSummary: String? {
        guard let s = opportunity.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !s.isEmpty else { return nil }
        return s
    }

    private func summarySection(_ summary: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                HStack(spacing: 0) {
                    Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                    Text("SUMMARY").foregroundColor(OPSStyle.Colors.agent)
                }
                if let stamp = summaryStamp {
                    Text("· UPDATED \(stamp)")
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .monospacedDigit()
                }
                Spacer(minLength: 0)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.6)
            .textCase(.uppercase)

            HStack(alignment: .top, spacing: 0) {
                Rectangle()
                    .fill(OPSStyle.Colors.agentLine)
                    .frame(width: OPSStyle.Layout.Border.thick)
                Text(summary)
                    .font(.custom("Mohave-Regular", size: 13.5))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.agentSoft)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Summary\(summaryStamp.map { ", updated \($0.lowercased())" } ?? ""). \(summary)")
    }

    private var summaryStamp: String? {
        guard let updated = opportunity.aiSummaryUpdatedAt else { return nil }
        let interval = Date().timeIntervalSince(updated)
        if interval < 3600 { return "NOW" }
        let hours = Int(interval / 3600)
        if hours < 24 { return "\(hours)H AGO" }
        return "\(hours / 24)D AGO"
    }

    // MARK: - CONTACT ▾ + ⋯ pair (spec §5.8)

    private var actionPair: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingContactDialog = true
            } label: {
                HStack(spacing: 6) {
                    Text("CONTACT")
                        .font(.custom("CakeMono-Light", size: 13.5))
                        .kerning(0.27)
                        .textCase(.uppercase)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Contact \(opportunity.displayContactName)")

            Menu {
                if canConvert && !opportunity.stage.isTerminal {
                    Button {
                        showingSiteVisitCapture = true
                    } label: {
                        Label("START SITE VISIT", systemImage: "camera.viewfinder")
                    }
                }
                if canEdit {
                    Button {
                        showingLogActivity = true
                    } label: {
                        Label("LOG ACTIVITY", systemImage: "square.and.pencil")
                    }
                }
                Button {
                    shareLead()
                } label: {
                    Label("SHARE LEAD", systemImage: "square.and.arrow.up")
                }
            } label: {
                Group {
                    if isAssemblingShare {
                        ProgressView()
                            .controlSize(.small)
                            .tint(OPSStyle.Colors.text2)
                    } else {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .accessibilityLabel("More workflows")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    /// CALL — the around-call contract (record intent when editable, dial).
    private func placeCallFromDetail() {
        let sanitized = (opportunity.contactPhone ?? "").filter { "0123456789+".contains($0) }
        guard !sanitized.isEmpty else { return }
        if PermissionStore.shared.isFeatureEnabled("pipeline"), canEdit {
            CallLogStore.shared.recordOutbound(
                opportunityId: opportunity.id,
                contactName: opportunity.contactName,
                phone: opportunity.contactPhone ?? sanitized
            )
        }
        guard let url = URL(string: "tel:\(sanitized)") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    /// TEXT / EMAIL — do-and-stamp (same contract as the card); a viewer
    /// without edit rights gets the conversation without the doomed log write.
    private func touchTextFromDetail() {
        guard let phone = opportunity.contactPhone, !phone.isEmpty else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(
                .text,
                lead: opportunity,
                companyId: opportunity.companyId
            )
        } else if let url = URL(string: LeadQuickTouchLogger.smsURLString(phone: phone)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func touchEmailFromDetail() {
        guard let email = opportunity.contactEmail, !email.isEmpty else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(
                .email,
                lead: opportunity,
                companyId: opportunity.companyId
            )
        } else if let url = URL(string: LeadQuickTouchLogger.mailtoURLString(email: email, threadSubject: vm.latestThreadSubject)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    /// HANDLED from the detail strip — the queue engine on the single-lead VM,
    /// so the flip + comeback + toast + reload contract match the card exactly.
    private func markHandledFromDetail() {
        guard canEdit else { return }
        Task {
            do {
                let comeback = try await chaseVM.markHandled(opportunityId: opportunity.id)
                ToastCenter.shared.present(Toast(
                    label: "// HANDLED · BACK \(LeadChaseStrip.comebackLabel(comeback))",
                    tone: .success,
                    autoDismissAfter: 6,
                    action: ToastAction(label: "ADJUST", accessibilityLabel: "Adjust comeback date") {
                        comebackTarget = opportunity
                    }
                ))
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }

    /// Provider-backed follow-up. The deliberate hold/review surface shares
    /// the queue's exact send, reconciliation, comeback, and feedback contract.
    private func sendFollowUpFromDetail() {
        guard canEdit, chaseVM.canSendFollowUp(for: opportunity) else { return }
        Task {
            let outcome = await chaseVM.sendFollowUp(opportunityId: opportunity.id)
            ToastCenter.shared.present(
                Feedback.Lead.followUpResult(outcome) {
                    comebackTarget = opportunity
                }
            )
        }
    }

    // MARK: - Details document wiring (spec §5.9)

    private var rosterState: LeadContactRosterState {
        LeadDetailViewModel.rosterState(
            contactName: opportunity.contactName,
            contactEmail: opportunity.contactEmail,
            contactPhone: opportunity.contactPhone,
            client: vm.client,
            subClients: vm.subClients
        )
    }

    /// Linked project's title, resolved from the local synced store.
    private var linkedProjectName: String? {
        guard let pid = opportunity.projectId, !pid.isEmpty,
              let context = dataController.modelContext else { return nil }
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == pid })
        return (try? context.fetch(descriptor))?.first?.title
    }

    /// PROJECT row tap — the app-wide project route (same channel Spotlight
    /// and notifications use).
    private func openLinkedProject() {
        guard let pid = opportunity.projectId, !pid.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        NotificationCenter.default.post(
            name: Notification.Name("OpenProjectDetails"),
            object: nil,
            userInfo: ["projectId": pid]
        )
    }

    /// ADD TO CLIENT — files the lead's person as a sub_client.
    private func addContactToClient() {
        guard canEdit, !isAddingToClient else { return }
        isAddingToClient = true
        Task {
            do {
                try await vm.addContactToClient(
                    name: opportunity.contactName,
                    email: opportunity.contactEmail,
                    phone: opportunity.contactPhone
                )
                await MainActor.run {
                    isAddingToClient = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    ToastCenter.shared.present(Toast(label: "// ADDED TO CLIENT", tone: .success))
                }
            } catch {
                await MainActor.run {
                    isAddingToClient = false
                    ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
                }
            }
        }
    }

    /// FILES tap — external attachments open their source; stored ones stream
    /// through the authenticated ops-web proxy into a temp file, then the
    /// share sheet (QuickLook-equivalent preview + save/send in one surface).
    private func openAttachment(_ attachment: LeadAttachment) {
        if attachment.ingestStatus == "external" {
            guard let raw = attachment.sourceUrl, let url = URL(string: raw) else { return }
            UIApplication.shared.open(url)
            return
        }
        guard !isFetchingAttachment else { return }
        isFetchingAttachment = true
        Task {
            defer { isFetchingAttachment = false }
            do {
                let token = try await FirebaseAuthService.shared.getIDToken()
                var comps = URLComponents(
                    url: AppConfiguration.apiBaseURL.appendingPathComponent("/api/integrations/email/attachment"),
                    resolvingAgainstBaseURL: false
                )
                comps?.queryItems = [URLQueryItem(name: "id", value: attachment.id)]
                guard let url = comps?.url else { return }
                var request = URLRequest(url: url)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                    throw URLError(.badServerResponse)
                }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(attachment.displayName)
                try data.write(to: tempURL)
                await MainActor.run {
                    presentShareSheet([tempURL])
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.present(Toast(label: "// FILE UNAVAILABLE", tone: .error))
                }
            }
        }
    }

    // MARK: - Share lead summary

    private func shareLead() {
        guard !isAssemblingShare else { return }
        isAssemblingShare = true

        Task {
            var designs: [DeckDesign] = []
            if let context = dataController.modelContext {
                let oppId: String? = opportunity.id
                let descriptor = FetchDescriptor<DeckDesign>(
                    predicate: #Predicate<DeckDesign> { $0.opportunityId == oppId }
                )
                designs = (try? context.fetch(descriptor)) ?? []
            }

            let items = await LeadShareSummaryBuilder.assemblePacket(
                opportunity: opportunity,
                activities: vm.activities,
                deckDesigns: designs
            )
            isAssemblingShare = false
            presentShareSheet(items)
        }
    }

    /// Imperative present from the top controller — the codebase's standing
    /// share-sheet pattern (PhotoGalleryViewer et al).
    private func presentShareSheet(_ items: [Any]) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            var top = window.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            top?.present(activityVC, animated: true)
        }
    }

    // MARK: - Nav chrome (map layering, spec §5.1–5.2)

    /// The status chip — top-right, hosting the shared status menu.
    private var statusChip: some View {
        LeadStatusMenu(
            lead: opportunity,
            canEdit: canEdit,
            canConvert: canConvert,
            onStage: { setStage($0) },
            onWon: onMarkWon,
            onLost: onMarkLost,
            onArchive: { requestArchive() },
            onDiscard: { discardTarget = opportunity }
        ) {
            StageTag(stage: opportunity.stage, showsChevron: canEdit || canConvert)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .contentShape(Rectangle())
        }
    }

    /// Legibility scrim behind the nav row while it floats over raw map —
    /// the photo-scrim treatment; clear when there's no map hero.
    @ViewBuilder
    private var navScrim: some View {
        if mapCoordinates != nil {
            LinearGradient(
                colors: [OPSStyle.Colors.background.opacity(0.45), .clear],
                startPoint: .top,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        } else {
            Color.clear
        }
    }

    /// 90pt bridge from open map to solid content — the exact
    /// ProjectDetailsView stops.
    private var mapScrollGradient: some View {
        LinearGradient(
            gradient: Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: OPSStyle.Colors.background.opacity(0.25), location: 0.55),
                .init(color: OPSStyle.Colors.background.opacity(0.75), location: 0.85),
                .init(color: OPSStyle.Colors.background, location: 1.0)
            ]),
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 90)
        .allowsHitTesting(false)
    }

    /// Directions to the site — address string when present, raw coordinates
    /// otherwise (a map hero can exist on a coordinate-only lead).
    private func openDirections() {
        let query: String
        if let address = opportunity.address, !address.isEmpty {
            query = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        } else if let coords = mapCoordinates {
            query = "\(coords.lat),\(coords.lon)"
        } else {
            return
        }
        guard let url = URL(string: "https://maps.apple.com/?daddr=\(query)") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    // MARK: - Status-menu mutations

    /// Direct stage pick from the nav chip. The detail has no
    /// PipelineViewModel — it mutates through the repository and refreshes
    /// the shared instance via apply(), then posts the reload contract.
    private func setStage(_ stage: PipelineStage) {
        guard canEdit, stage != opportunity.stage else { return }
        Task {
            do {
                let repo = OpportunityRepository(companyId: opportunity.companyId)
                let dto = try await repo.moveToStage(
                    opportunityId: opportunity.id,
                    to: stage,
                    userId: dataController.currentUser?.id
                )
                await MainActor.run {
                    opportunity.apply(dto.toModel())
                    NotificationCenter.default.post(
                        name: Notification.Name("LeadUpdatedSuccess"),
                        object: nil, userInfo: ["leadId": opportunity.id]
                    )
                    ToastCenter.shared.present(Feedback.Lead.stageSet)
                }
            } catch {
                await MainActor.run {
                    ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
                }
            }
        }
    }

    /// ARCHIVE — guarded by the standardized confirm; an archived lead leaves
    /// the queue, so the detail pops with it.
    private func requestArchive() {
        guard canEdit else { return }
        archiveConfirm = OPSConfirmConfig(
            title: "ARCHIVE LEAD?",
            message: "It leaves the queue. Restore any time from the by-stage list.",
            verb: "ARCHIVE"
        ) {
            Task {
                do {
                    try await OpportunityRepository(companyId: opportunity.companyId)
                        .archive(opportunity.id)
                    await MainActor.run {
                        NotificationCenter.default.post(
                            name: Notification.Name("LeadArchivedSuccess"),
                            object: nil, userInfo: ["leadId": opportunity.id]
                        )
                        ToastCenter.shared.present(Feedback.Lead.archived)
                        dismiss()
                    }
                } catch {
                    await MainActor.run {
                        ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
                    }
                }
            }
        }
    }

    // MARK: - Derived state

    private var currentAssigneeName: String {
        guard let assignedTo = opportunity.assignedTo else {
            return "Unassigned"
        }

        if let candidate = assignmentViewModel.candidates.first(where: {
            normalizedUserId($0.id) == normalizedUserId(assignedTo)
        }), !candidate.displayName.isEmpty {
            return candidate.displayName
        }

        if let user = allUsers.first(where: {
            normalizedUserId($0.id) == normalizedUserId(assignedTo)
                && $0.companyId == opportunity.companyId
        }) {
            let name = user.fullName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { return name }
        }

        // Assigned, but the operator's name isn't resolvable on this device —
        // matches the web surface's vocabulary for the same state.
        return "Unknown"
    }

    private func handleAssignmentMutation(
        _ outcome: LeadAssignmentMutationOutcome
    ) {
        let disposition = LeadAssignmentMutationDisposition.resolve(
            outcome: outcome,
            retainsLeadAccess: leadAccessPolicy.can(
                .view,
                assignedTo: opportunity.assignedTo
            )
        )

        // Failure gets felt, not just read — one error notification per
        // failed mutation outcome (audit P3-21). Success keeps its existing
        // haptic below; .unchanged is a no-op and stays silent.
        switch outcome {
        case .conflict, .failed, .accessLost:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .unchanged, .updated:
            break
        }

        if disposition.showSuccess {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(
                Toast(
                    label: opportunity.assignedTo == nil
                        ? "// LEAD UNASSIGNED"
                        : "// LEAD ASSIGNED",
                    tone: .success
                )
            )
        }

        if disposition.refreshLeads {
            NotificationCenter.default.post(name: .opsLeadsDidChange, object: nil)
        }

        if disposition.dismissPicker {
            showingAssignmentPicker = false
        }

        if disposition.dismissLead {
            // `assignment_access_lost` deliberately returns no replacement
            // assignee. Dismiss from the stable server token alone, then let
            // the scoped list refresh destroy its cached row.
            DispatchQueue.main.async {
                dismiss()
            }
        }
    }

    private func normalizedUserId(_ value: String) -> String {
        value.lowercased()
    }

    private var atmosphereTone: Atmosphere.Tone {
        switch opportunity.stage {
        case .won:                                   return .olive
        case .lost:                                  return .rose
        case .quoted, .followUp, .negotiation:       return .tan
        case .newLead, .qualifying, .quoting, .discarded:  return .steel
        }
    }

    private var showWonNotConverted: Bool {
        opportunity.stage == .won
            && opportunity.projectId == nil
            && !conversionVisibilityStore.contains(opportunity.id)
    }

}

// MARK: - DetailNavBar (private)

/// Minimal nav bar above the scroll view. Custom back chevron + LEADS label;
/// the trailing slot carries the share affordance (the summary + photo packet
/// + deck snapshot leave through here). Swipe-back gesture is preserved by
/// the NavigationStack.
private struct DetailNavBar<Trailing: View>: View {
    let onBack: () -> Void
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .regular))
                    Text("LEADS")
                        .font(OPSStyle.Typography.miniLabel)
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .padding(.leading, OPSStyle.Layout.spacing1)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                // Meet the 44pt touch floor (review W-10).
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Back to leads")

            Spacer()

            trailing()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: 52)
    }
}

// MARK: - WonNotConvertedCard (private)

/// L1 card rendered only when `stage == .won && projectId == nil`. Olive
/// border + olive-tinted eyebrow signal "this is good, but it's incomplete."
/// CONVERT → PROJECT uses the same `onMarkWon` closure as the sticky bar so
/// the parent routes to the same `LeadsSheet.convert` case.
private struct WonNotConvertedCard: View {
    let onConvert: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("WON · NOT CONVERTED")
                    .foregroundColor(OPSStyle.Colors.oliveTextM)
            }
            .font(OPSStyle.Typography.miniLabel)
            .fontWeight(.semibold)
            .kerning(1.6)
            .textCase(.uppercase)

            Text("Promote this lead into a project.")
                .font(.custom("Mohave-Medium", size: 14.5))
                .foregroundColor(OPSStyle.Colors.text)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConvert()
            }) {
                Text("CONVERT → PROJECT")
                    .font(.custom("CakeMono-Light", size: 13.5))
                    .kerning(0.27)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.inputHeight)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .fill(OPSStyle.Colors.opsAccent)
                    )
            }
            .buttonStyle(PlainButtonStyle())
            .padding(.top, OPSStyle.Layout.spacing1)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Solid command surface + mobile-bright olive edge (the -M line clears
        // outdoor-glare contrast that commandCard(tone:)'s 0.30 border would not).
        .commandCard()
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.oliveLineM, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}

// SiteVisitLaunchCard deleted — START SITE VISIT lives in the ⋯ workflow
// menu (spec §5.8); the sticky bar's MARK WON keeps the screen's only accent.

// MARK: - Previews

#if DEBUG
#Preview("LeadDetailView / quoted") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Roof tear-off, 28 sq",
                contactName: "Helen Calloway",
                stage: .quoted,
                estimatedValue: 14_200,
                daysInStage: 9
            )
            o.contactPhone = "(555) 123-4567"
            o.contactEmail = "helen@example.com"
            o.address = "1240 Maple Ave"
            o.source = "referral"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}

#Preview("LeadDetailView / won not converted") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Maple Lane porch",
                contactName: "Tom Liu",
                stage: .won,
                estimatedValue: 11_200,
                daysInStage: 12
            )
            o.contactPhone = "(555) 234-5678"
            o.address = "880 Maple Lane"
            o.source = "manual"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}

#Preview("LeadDetailView / lost") {
    NavigationStack {
        LeadDetailView(opportunity: {
            let o = Opportunity.preview(
                title: "Beacon Hill addition",
                contactName: "Beacon Hill LLC",
                stage: .lost,
                estimatedValue: 26_500,
                daysInStage: 20
            )
            o.contactPhone = "(555) 999-0000"
            o.source = "web_form"
            o.lostReason = "price"
            return o
        }())
    }
    .leadsPreviewEnvironment()
}
#endif
