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

private struct PreparedLeadAttachment: Sendable {
    let fileURL: URL
    let directoryURL: URL
}

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
    /// Opens the linked project from THIS host instead of the app-wide route.
    ///
    /// The app-wide route presents the project sheet from `MainTabView`, which
    /// sits below any modal. When this dossier is reached from inside a sheet —
    /// the client profile's LEADS section is the one such host today — that
    /// route would put the project behind the sheet the operator is standing
    /// in (the mirror of bug 80dab840). Hosts in that position pass a closure
    /// and present the project themselves; the LEADS tab leaves it nil and
    /// keeps the app-wide route.
    var onOpenProject: ((String) -> Void)? = nil

    @StateObject private var vm: LeadDetailViewModel
    @StateObject private var assignmentViewModel: LeadAssignmentViewModel
    @Query private var allUsers: [User]
    @State private var showingSiteVisitCapture = false
    /// BOOK A VISIT / RESCHEDULE from the workflow menu (spec §4.1) — the
    /// menu itself is the NOW/BOOK branch here, so no extra dialog hop.
    @State private var bookingRequest: BookSiteVisitRequest?
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
    @State private var importingPhotoIDs: [String] = []
    @State private var photoViewerState: LeadPhotoViewerState?

    // Deck design on the lead. The DECK row PUSHES the deck screen (the drawing
    // deserves the display); `deckDesignToOpen` now serves only the creation
    // path — a brand-new design goes straight into the builder to be drawn.
    @State private var showingDeckScreen = false
    @State private var showingDeckCreationPicker = false
    @State private var deckDesignToOpen: DeckDesign?

    // Share lead summary
    @State private var isAssemblingShare = false

    // Status-menu guarded exits (Leads redesign spec §6)
    @State private var archiveTarget: Opportunity?
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
    @State private var showingAttachments = false
    @State private var attachmentToOpenAfterSheet: LeadAttachment?
    @State private var preparedAttachmentToOpenAfterSheet: PreparedLeadAttachment?

    // One activity stream (spec §5.10)
    @State private var showingActivityHistory = false

    // Hold-to-edit (bug b1d30fe8). Holding a dossier fact turns it into its
    // editor in place rather than sending the operator to hunt for an edit
    // affordance. The correction set is client / address / contact / value /
    // assigned-to — the things a person fixes when a lead arrives wrong.
    // Stage and status are deliberately excluded: they carry real side effects
    // and keep their own guarded flows.
    @StateObject private var fieldEdit: LeadFieldEditController
    /// The house client picker, hosted here so it presents above the whole
    /// dossier rather than from inside a document row.
    @State private var showingClientPicker = false
    /// One-time discovery counter for the hold gesture. Retires itself.
    @AppStorage(LeadHoldHint.storageKey) private var holdHintState = 0

    init(
        opportunity: Opportunity,
        onMarkLost: @escaping () -> Void = {},
        onEdit:     @escaping () -> Void = {},
        onMarkWon:  @escaping () -> Void = {},
        onConvertLead: @escaping (Opportunity) -> Void = { _ in },
        onOpenProject: ((String) -> Void)? = nil
    ) {
        self.opportunity = opportunity
        self.onMarkLost = onMarkLost
        self.onEdit = onEdit
        self.onMarkWon = onMarkWon
        self.onConvertLead = onConvertLead
        self.onOpenProject = onOpenProject
        _vm = StateObject(wrappedValue: LeadDetailViewModel(
            opportunityId: opportunity.id,
            companyId: opportunity.companyId,
            clientId: opportunity.clientId
        ))
        _assignmentViewModel = StateObject(
            wrappedValue: LeadAssignmentViewModel(opportunity: opportunity)
        )
        _fieldEdit = StateObject(
            wrappedValue: LeadFieldEditController(opportunity: opportunity)
        )
    }

    private var leadAccessPolicy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private var canEdit: Bool {
        leadAccessPolicy.can(.edit, assignedTo: opportunity.assignedTo)
    }
    private var canConvert: Bool {
        leadAccessPolicy.can(.convert, assignedTo: opportunity.assignedTo)
    }
    /// Amending a logged note is an edit of this lead, so it rides the lead's
    /// own edit scope — the same granular check every other correction on this
    /// screen uses, never a role name. Nil for a viewer, which removes the
    /// affordance rather than showing one that refuses (bug f740400e).
    private var noteEditing: LeadNoteEditing? {
        guard canEdit else { return nil }
        return LeadNoteEditing { activity, amended in
            do {
                try await vm.updateNoteBody(activity: activity, body: amended)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                return true
            } catch {
                return false
            }
        }
    }
    /// The lead's open booking, resolved when the workflow menu renders so
    /// its second entry always states the current reality.
    private var openBookingSnapshot: BookSiteVisitForm.BookingSnapshot? {
        guard let context = dataController.modelContext,
              let booking = SiteVisitBookingLookup.openBooking(
                forOpportunityId: opportunity.id,
                in: context
              ) else { return nil }
        return SiteVisitBookingLookup.snapshot(of: booking)
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
                        // Pinned identity (bug 73f7381b): the lead's title rides
                        // to the top of the viewport and stays there while the
                        // document scrolls under it — the ProjectDetailsView
                        // mechanism, LazyVStack + a Section header. iOS 17.6:
                        // pinning is the pinnedViews API, not scroll geometry.
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
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

                            Section {
                                VStack(spacing: 0) {
                                    DetailHero(
                                        opportunity: opportunity,
                                        clientName: vm.client?.name,
                                        assigneeName: currentAssigneeName,
                                        canChangeAssignee: canChangeAssignee,
                                        canEditValue: canEdit,
                                        fieldEdit: fieldEdit,
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
                                        onOpenAddress: { openDirections() },
                                        onOpenProject: { openLinkedProject() },
                                        onMatchProject: {
                                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                            onMarkWon()
                                        },
                                        onOpenDeck: { showingDeckScreen = true },
                                        onCreateDeck: { showingDeckCreationPicker = true },
                                        importingPhotoIDs: importingPhotoIDs,
                                        onAddPhotos: { showingAddPhotoDialog = true },
                                        onTapPhoto: { items, index in
                                            photoViewerState = LeadPhotoViewerState(items: items, initialIndex: index)
                                        },
                                        onOpenAttachments: { showingAttachments = true },
                                        onOpenEstimate: { estimateToOpen = $0 },
                                        fieldEdit: fieldEdit,
                                        onEditClient: { showingClientPicker = true },
                                        showsHoldHint: LeadHoldHint.shouldShow(
                                            state: holdHintState,
                                            canEdit: canEdit
                                        )
                                    )
                                    .padding(.top, 22)

                                    ActivityTimeline(
                                        activities: vm.activities,
                                        transitions: vm.stageTransitions,
                                        opportunity: opportunity,
                                        onViewAll: { showingActivityHistory = true },
                                        noteEditing: noteEditing
                                    )
                                    .padding(.top, 22)
                                }
                                // A LazyVStack does not inherit the old outer
                                // VStack's paint, so Section content carries its own
                                // solid background (mirrors ProjectDetailsView).
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(OPSStyle.Colors.background)
                            } header: {
                                LeadDetailStickyHeader(
                                    opportunity: opportunity,
                                    clientName: vm.client?.name
                                )
                            }
                        }
                        // Bug e13be3bb: a vertical document must never pan
                        // sideways. The column caps at the viewport width and
                        // the scroll clips anything that still tries to exceed
                        // it, so an oversized label truncates instead of
                        // widening the page.
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 200)   // clears the sticky action bar
                    }
                    .frame(maxWidth: .infinity)
                    .scrollIndicators(.hidden)
                    .clipped()
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
        .leadArchiveFlow(
            target: $archiveTarget,
            onCompleted: { _ in dismiss() }
        )
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
                transitions: vm.stageTransitions,
                opportunity: opportunity,
                noteEditing: noteEditing
            )
        }
        // DECK row → the drawing on the whole display. A push, not a cover: the
        // dossier stays one scroll and keeps its nav model, and the deck screen
        // owns the fullscreen expand from there.
        .navigationDestination(isPresented: $showingDeckScreen) {
            LeadDeckScreen(opportunity: opportunity)
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
            // Bug ced5b3cb-B self-repair. Leads damaged by the old
            // already-converted path carry a PERSISTED marker that hides MATCH
            // PROJECT for good. A lead that demonstrably HAS a project link is
            // proof the marker is stale — clear it silently on open.
            conversionVisibilityStore.repairIfLinked(
                leadId: opportunity.id,
                projectId: opportunity.projectId
            )
            // A gesture nobody knows about is a feature nobody has. The DETAILS
            // header carries one mono line for an operator's first few
            // dossiers, then stops on its own.
            if LeadHoldHint.shouldShow(state: holdHintState, canEdit: canEdit) {
                holdHintState = LeadHoldHint.advanced(holdHintState)
            }
        }
        .onChange(of: fieldEdit.didCompleteAnEdit) { _, completed in
            // They corrected something. The hint has done its job — retire it
            // for good rather than keep explaining a gesture they now know.
            if completed { holdHintState = LeadHoldHint.retired() }
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
        .sheet(item: $bookingRequest) { request in
            BookSiteVisitSheet(request: request)
                .environmentObject(dataController)
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
                let reservationIDs = images.map { _ in UUID().uuidString }
                importingPhotoIDs.append(contentsOf: reservationIDs)
                addPhotos(images, reservationIDs: reservationIDs)
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
            let reservationIDs = items.map { _ in UUID().uuidString }
            importingPhotoIDs.append(contentsOf: reservationIDs)
            libraryItems = []
            Task {
                await importLibraryItems(items, reservationIDs: reservationIDs)
            }
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
        // CLIENT hold → the house client picker (the same one that reassigns a
        // project's client, so it already searches the roster, blends in phone
        // contacts, and can create a client that exists nowhere yet). It
        // dismisses on select; the CLIENT row does the work and owns the
        // failure, so a lost write never sends the operator back to re-pick.
        .sheet(isPresented: $showingClientPicker) {
            ClientPickerSheet(
                currentClientId: opportunity.clientId,
                companyId: opportunity.companyId
            ) { client in
                Task { await fieldEdit.commitClient(id: client.id, name: client.name) }
            }
            .environmentObject(dataController)
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
        .sheet(
            isPresented: $showingAttachments,
            onDismiss: openAttachmentAfterSheetDismisses
        ) {
            LeadAttachmentsSheet(attachments: vm.attachments) { attachment in
                await prepareAttachmentForOpening(attachment)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(OPSStyle.Colors.background)
        }
        .fullScreenCover(item: $deckDesignToOpen) { design in
            deckBuilder(design: design)
        }
    }

    // MARK: - Photos

    private func addPhotos(_ images: [UIImage], reservationIDs: [String]) {
        Task {
            await Task.yield()
            let result = await LeadImageService.shared.addImages(
                images,
                to: opportunity,
                reservationIDs: reservationIDs
            )
            importingPhotoIDs.removeAll { reservationIDs.contains($0) }
            if result.failedCount > 0 {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            } else if result.queuedCount > 0 {
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }

    private func importLibraryItems(
        _ items: [PhotosPickerItem],
        reservationIDs: [String]
    ) async {
        let decoded = await withTaskGroup(
            of: (index: Int, reservationID: String, image: UIImage)?.self
        ) { group in
            for (index, item) in items.enumerated() {
                let reservationID = reservationIDs[index]
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else {
                        return nil
                    }
                    return (index, reservationID, image)
                }
            }
            var results: [(index: Int, reservationID: String, image: UIImage)] = []
            for await result in group {
                if let result { results.append(result) }
            }
            return results.sorted { $0.index < $1.index }
        }

        guard !decoded.isEmpty else {
            importingPhotoIDs.removeAll { reservationIDs.contains($0) }
            ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            return
        }

        let successfulIDs = decoded.map(\.reservationID)
        let result = await LeadImageService.shared.addImages(
            decoded.map(\.image),
            to: opportunity,
            reservationIDs: successfulIDs
        )
        importingPhotoIDs.removeAll { reservationIDs.contains($0) }

        if decoded.count != items.count || result.failedCount > 0 {
            ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
        } else if result.queuedCount > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    // MARK: - Deck design

    @ViewBuilder
    private var deckCreationPicker: some View {
        // Picker dismisses BEFORE the builder presents — iOS can't stack two
        // modals (same dance as ProjectDetailsView's deck creation, bug 1).
        CreationPickerView(
            projectId: nil,
            opportunityId: opportunity.id,
            preferredDesignTitle: opportunity.deckDesignTitle,
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
                projectName: opportunity.deckDesignTitle
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
        // Editing the contact takes over the whole pair's row: phone and email
        // side by side need the width, and the ⋯ workflows are not what the
        // operator is doing right now.
        Group {
            if fieldEdit.isEditing(.contact) {
                LeadContactInlineEditor(controller: fieldEdit)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            } else {
                actionPairControls
            }
        }
    }

    /// Phone and email have no row of their own on this dossier — they live
    /// behind CONTACT ▾, which makes that control the contact FIELD. It is also
    /// exactly where the operator is standing when they notice the number is
    /// wrong: they opened it to call. A lead carrying no phone and no email
    /// opens a dialog with nothing but CANCEL in it, so on that lead a plain
    /// tap goes straight to the editor instead of the dead end.
    private var contactHasValue: Bool {
        let phone = opportunity.contactPhone?.trimmingCharacters(in: .whitespaces) ?? ""
        let email = opportunity.contactEmail?.trimmingCharacters(in: .whitespaces) ?? ""
        return !phone.isEmpty || !email.isEmpty
    }

    /// Only an operator who can actually fill the blank is invited to. A viewer
    /// looking at a lead with no contact details still reads CONTACT — offering
    /// them ADD CONTACT would be a promise the screen cannot keep.
    private var contactInvitesAdd: Bool {
        !contactHasValue && canEdit
    }

    /// A lead with no phone and no email has nothing behind CONTACT ▾ but a
    /// CANCEL button. On that lead the control states what it can actually do —
    /// ADD CONTACT — and goes straight to the editor. Same principle as the
    /// document's empty-row chips: a blank never hides its way in behind a
    /// gesture, and the label describes the operator's reality, not the
    /// feature's name.
    private var actionPairControls: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 6) {
                Text(contactInvitesAdd ? "ADD CONTACT" : "CONTACT")
                    .font(.custom("CakeMono-Light", size: 13.5))
                    .kerning(0.27)
                    .textCase(.uppercase)
                Image(systemName: contactInvitesAdd ? "plus" : "chevron.down")
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
                    .strokeBorder(
                        OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .holdToEdit(
                .contact,
                offersEdit: InfoRowEdit.offersLongPressEdit(
                    canEdit: canEdit,
                    hasValue: contactHasValue,
                    isEditing: fieldEdit.isEditing(.contact)
                ),
                cornerRadius: OPSStyle.Layout.buttonRadius,
                onEdit: { fieldEdit.begin(.contact) },
                onActivate: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    if contactHasValue {
                        showingContactDialog = true
                    } else if canEdit {
                        fieldEdit.begin(.contact)
                    }
                }
            )
            .accessibilityLabel(
                contactInvitesAdd
                    ? "Add contact details for \(opportunity.displayContactName)"
                    : "Contact \(opportunity.displayContactName)"
            )

            Menu {
                if canConvert && !opportunity.stage.isTerminal {
                    Button {
                        showingSiteVisitCapture = true
                    } label: {
                        Label("START VISIT NOW", systemImage: "camera.viewfinder")
                    }
                    if let booking = openBookingSnapshot {
                        Button {
                            bookingRequest = BookSiteVisitRequest(lead: opportunity, existing: booking)
                        } label: {
                            Label(
                                "RESCHEDULE — \(SiteVisitBookingLookup.bookedToken(for: booking.scheduledAt))",
                                systemImage: "calendar"
                            )
                        }
                    } else {
                        Button {
                            bookingRequest = BookSiteVisitRequest(lead: opportunity, existing: nil)
                        } label: {
                            Label("BOOK A VISIT", systemImage: "calendar.badge.plus")
                        }
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
    /// and notifications use), unless the host supplied its own.
    private func openLinkedProject() {
        guard let pid = opportunity.projectId, !pid.isEmpty else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if let onOpenProject {
            onOpenProject(pid)
            return
        }
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

    /// Prepares the selected file while its sheet remains visible. This keeps
    /// loading feedback attached to the tapped row and avoids presenting a
    /// second sheet until the attachment browser has fully dismissed.
    @MainActor
    private func prepareAttachmentForOpening(_ attachment: LeadAttachment) async {
        let status = attachment.ingestStatus
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch status {
        case "external":
            guard let rawURL = attachment.sourceUrl,
                  let url = URL(string: rawURL),
                  url.scheme?.lowercased() == "https" else {
                ToastCenter.shared.present(Toast(label: "// FILE UNAVAILABLE", tone: .error))
                return
            }
            attachmentToOpenAfterSheet = attachment
            showingAttachments = false

        case "stored":
            do {
                let data = try await LeadAttachmentContentLoader.data(for: attachment)
                let safeName = LeadAttachmentPresentation.safeFilename(
                    filename: attachment.filename,
                    mimeType: attachment.mimeType
                )
                let prepared = try await Task.detached(priority: .userInitiated) {
                    let fileManager = FileManager.default
                    let directoryURL = fileManager.temporaryDirectory
                        .appendingPathComponent("lead-attachments", isDirectory: true)
                        .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    try fileManager.createDirectory(
                        at: directoryURL,
                        withIntermediateDirectories: true
                    )
                    let fileURL = directoryURL.appendingPathComponent(safeName)

                    do {
                        try data.write(to: fileURL, options: .atomic)
                    } catch {
                        try? fileManager.removeItem(at: directoryURL)
                        throw error
                    }

                    return PreparedLeadAttachment(
                        fileURL: fileURL,
                        directoryURL: directoryURL
                    )
                }.value
                preparedAttachmentToOpenAfterSheet = prepared
                showingAttachments = false
            } catch {
                ToastCenter.shared.present(Toast(label: "// FILE UNAVAILABLE", tone: .error))
            }

        default:
            ToastCenter.shared.present(Toast(label: "// FILE UNAVAILABLE", tone: .error))
        }
    }

    @MainActor
    private func openAttachmentAfterSheetDismisses() {
        if let prepared = preparedAttachmentToOpenAfterSheet {
            preparedAttachmentToOpenAfterSheet = nil
            presentShareSheet(
                [prepared.fileURL],
                cleanupURLs: [prepared.directoryURL]
            )
            return
        }

        guard let attachment = attachmentToOpenAfterSheet else { return }
        attachmentToOpenAfterSheet = nil
        guard let rawURL = attachment.sourceUrl,
              let url = URL(string: rawURL),
              url.scheme?.lowercased() == "https" else {
            ToastCenter.shared.present(Toast(label: "// FILE UNAVAILABLE", tone: .error))
            return
        }
        UIApplication.shared.open(url)
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
    private func presentShareSheet(_ items: [Any], cleanupURLs: [URL] = []) {
        let activityVC = UIActivityViewController(activityItems: items, applicationActivities: nil)
        activityVC.completionWithItemsHandler = { _, _, _, _ in
            let fileManager = FileManager.default
            for url in cleanupURLs {
                try? fileManager.removeItem(at: url)
            }
        }
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            var top = window.rootViewController
            while let presented = top?.presentedViewController {
                top = presented
            }
            top?.present(activityVC, animated: true)
        } else {
            let fileManager = FileManager.default
            for url in cleanupURLs {
                try? fileManager.removeItem(at: url)
            }
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
        guard let url = LeadDetailsAddressPresentation.directionsURL(
            address: opportunity.address,
            latitude: mapCoordinates?.lat,
            longitude: mapCoordinates?.lon
        ) else { return }
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

    /// ARCHIVE — hands off to the shared archive flow so the dossier and the
    /// day sheet capture the same reason, note, and undo. An archived lead
    /// leaves the queue, so the detail pops with it.
    private func requestArchive() {
        guard canEdit else { return }
        archiveTarget = opportunity
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
