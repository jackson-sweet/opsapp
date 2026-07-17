//
//  LeadDetailView.swift
//  OPS
//
//  Full record for one lead. Pushed from a triage row tap on LeadsTabView.
//  Phase 3 of the LEADS tab rebuild — replaces the placeholder that shipped
//  in Phase 2.
//
//  Composition (top → bottom):
//
//      Atmosphere(tone: derivedFromStage)
//      ┌────────────────────────────────────────────────┐
//      │  ← LEADS                                       │ ← DetailNavBar
//      ├────────────────────────────────────────────────┤
//      │  // L-XXXXXX                       9D IN STAGE │
//      │  [STAGE]   60% WIN PROB                        │
//      │  Helen Calloway                                │ ← DetailHero
//      │  Roof tear-off, 28 sq                          │
//      │  ┌──────┬──────┬──────┐                        │
//      │  │VALUE │WEIGHT│SOURCE│                        │
//      │  └──────┴──────┴──────┘                        │
//      │                                                │
//      │  [40] Helen Calloway                           │ ← ContactCard
//      │       (555) … · 1240 Maple Ave                 │
//      │  [CALL][TEXT][EMAIL][MAP]                      │
//      │                                                │
//      │  // WON · NOT CONVERTED   [conditional]        │ ← WonNotConvertedCard
//      │  Promote this lead into a project.             │
//      │  [CONVERT → PROJECT]                           │
//      │                                                │
//      │  // NEXT FOLLOW-UP                             │ ← FollowUpsCard
//      │  ● 2D OVERDUE                          AUTO    │
//      │  Chase quote response                          │
//      │                                                │
//      │  // RECENT ACTIVITY                  04        │ ← ActivityTimeline
//      │  [↓ Inbound call         5D ]                  │
//      │  …                                             │
//      │                                                │
//      │  // STAGE HISTORY                              │ ← StageTimeline
//      │  14D  NEW LEAD                                 │
//      │   0D  QUOTING → QUOTED                         │
//      └────────────────────────────────────────────────┘
//      [×]   [EDIT]   [MARK WON →]                       ← StickyActionBar
//
//  Sticky action bar is hidden when `opportunity.stage.isTerminal`.
//  Action closures route up to LeadsTabView which presents the matching
//  LeadsSheet (.lost / .edit / .convert) via its `.sheet(item:)` binding.
//
//  Plan: docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §7
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
            companyId: opportunity.companyId
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

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()
            Atmosphere(tone: atmosphereTone)

            VStack(spacing: 0) {
                DetailNavBar(
                    onBack: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    },
                    trailing: { shareButton }
                )

                ScrollView {
                    VStack(spacing: 0) {
                        DetailHero(
                            opportunity: opportunity,
                            assigneeName: currentAssigneeName,
                            canChangeAssignee: canChangeAssignee,
                            onAssigneeTap: {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showingAssignmentPicker = true
                            }
                        )

                        ContactCard(
                            opportunity: opportunity,
                            canLogActivity: canEdit
                        )
                            .padding(.top, OPSStyle.Layout.spacing1)

                        if canConvert && showWonNotConverted {
                            WonNotConvertedCard(onConvert: onMarkWon)
                                .padding(.top, 22)
                        }

                        if let nextFU = nextFollowUp {
                            FollowUpsCard(followUp: nextFU)
                                .padding(.top, 22)
                        }

                        if canConvert && !opportunity.stage.isTerminal {
                            SiteVisitLaunchCard {
                                showingSiteVisitCapture = true
                            }
                            .padding(.top, 22)
                        }

                        LeadPhotosSection(
                            opportunity: opportunity,
                            canManage: canEdit,
                            onAdd: { showingAddPhotoDialog = true },
                            onTap: { items, index in
                                photoViewerState = LeadPhotoViewerState(items: items, initialIndex: index)
                            }
                        )
                        .padding(.top, 22)

                        LeadDeckSection(
                            opportunity: opportunity,
                            canManage: canEdit,
                            onCreate: { showingDeckCreationPicker = true },
                            onOpen: { design in deckDesignToOpen = design }
                        )
                        .padding(.top, 22)

                        ActivityTimeline(activities: sortedActivities)
                            .padding(.top, 22)

                        StageTimeline(transitions: sortedStageTransitions)
                            .padding(.top, 22)
                    }
                    .padding(.bottom, 200)   // clears the sticky action bar
                }
                .scrollIndicators(.hidden)
            }

            if (canEdit || canConvert) && !opportunity.stage.isTerminal {
                StickyActionBar(
                    canEdit: canEdit,
                    canConvert: canConvert,
                    onMarkLost: onMarkLost,
                    onEdit:     onEdit,
                    onMarkWon:  onMarkWon
                )
                .padding(.bottom, 49)   // clears the custom tab bar (49pt)
            }
        }
        .navigationBarHidden(true)
        .task {
            await vm.loadAll()
        }
        .onAppear {
            if let context = dataController.modelContext {
                LeadImageService.shared.configure(modelContext: context)
            }
            Task { await LeadImageService.shared.drain() }
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

    // MARK: - Share lead summary

    private var shareButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            shareLead()
        } label: {
            Group {
                if isAssemblingShare {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.text2)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.text2)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAssemblingShare)
        .accessibilityLabel("Share lead summary")
    }

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

    /// Soonest unfinished follow-up (status != .completed), ascending by dueAt.
    private var nextFollowUp: FollowUp? {
        vm.followUps
            .filter { $0.status != .completed }
            .sorted { $0.dueAt < $1.dueAt }
            .first
    }

    /// Activities ordered newest first — ActivityTimeline trims to its maxItems.
    private var sortedActivities: [Activity] {
        vm.activities.sorted { $0.createdAt > $1.createdAt }
    }

    /// Stage transitions ordered oldest first — StageTimeline reads them in
    /// that order so the chain reads left-to-right top-to-bottom.
    private var sortedStageTransitions: [StageTransition] {
        vm.stageTransitions.sorted { $0.transitionedAt < $1.transitionedAt }
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
                        .font(.system(size: 16, weight: .regular))
                    Text("LEADS")
                        .font(.custom("JetBrainsMono-Regular", size: 10))
                        .fontWeight(.semibold)
                        .kerning(1.4)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.text2)
                .padding(.leading, OPSStyle.Layout.spacing1)
                .padding(.trailing, 10)
                .padding(.vertical, 6)
                .frame(minHeight: 44)   // meet the 44pt touch floor (review W-10)
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
            .font(.custom("JetBrainsMono-Regular", size: 10))
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
                    .frame(height: 48)
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

private struct SiteVisitLaunchCard: View {
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("SITE VISIT CAPTURE")
                    .foregroundColor(OPSStyle.Colors.tanTextM)
            }
            .font(OPSStyle.Typography.metadata)
            .textCase(.uppercase)

            Text("Capture the site packet before project creation: photos, notes, and measurements.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            Button(action: {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onStart()
            }) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 15, weight: .semibold))
                    Text("START VISIT")
                        .font(OPSStyle.Typography.captionBold)
                        .textCase(.uppercase)
                }
                .foregroundColor(OPSStyle.Colors.invertedText)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
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
        // Solid command surface + mobile-bright tan edge (see WonNotConvertedCard).
        .commandCard()
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.tanLineM, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}

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
