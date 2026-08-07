//
//  DaySheetLeadCard.swift
//  OPS
//
//  The day sheet's accordion cell: the collapsed row (scan) plus, behind one
//  tap, everything the runner needs to work the lead without leaving the sheet
//  (act). Both live under ONE L1 glass shell — the row renders `embedded` so it
//  never draws a second panel inside that shell.
//
//  COLLAPSED, the face IS the card: no fill of its own, no seam, nothing but
//  the row. OPEN, the face becomes a HEADER — a `surfaceHover` band and an L1
//  `line` rule under it (bug 594da411: shipped without either, the open card
//  read as one undifferentiated column and nothing marked where scanning ended
//  and working began). The treatment is expansion-scoped on purpose: a rule
//  drawn on a collapsed row would be chrome on a pure scan surface, separating
//  a header from a body that is not there.
//
//  Section order is the spec's and is not negotiable (§3.4): photos → deck →
//  visit → summary → contact → quick actions → milestone → est → footer. It is
//  ordered the way a person walks the job: see it, see the drawing, see whether
//  anyone has been out there, read what happened last, get the address and the
//  number, make the call, stamp what you did.
//
//  The visit row is the one addition to the spec's list, and it sits inside the
//  spec's opening ARTIFACT run rather than after it: photos, drawing and visit
//  are one thought — evidence of the job — and a runner scans them together.
//  Nothing else moved.
//
//  Everything is state-aware — a lead with no photos shows no strip, a lead
//  with no email shows no EMAIL button and no EMAIL row. Absent blocks are
//  ABSENT, never empty frames holding a `—`. The card a runner opens shows his
//  lead's reality, not the union of every lead's possibilities.
//
//  The milestone button is the ONLY accent element on the whole screen, and it
//  appears only when this operator may edit this lead (the transform already
//  gates `row.milestone` on edit scope).
//
//  Motion is two opacity transitions and nothing else (spec §7). The expanded
//  body fades in over the 250ms transaction the SCREEN opens — this card never
//  animates its own expansion, because the height change that pushes every row
//  below it belongs to the sheet's layout, not to one cell. The milestone
//  control crossfades idle ↔ pending in 150ms, scoped to that control by
//  `.animation(_:value:)` so a stamp never animates the card around it. Both
//  ride `OPSStyle.Animation` tokens, which resolve to a 150ms crossfade under
//  Reduce Motion with no call-site branch.
//
//  Spec: docs/superpowers/specs/2026-07-27-my-leads-day-sheet-design.md §3.4
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit

struct DaySheetLeadCard: View {

    /// Where the deck panel's design comes from.
    ///
    /// `resolve` is production: a `@Query` over local designs plus a one-shot
    /// remote self-repair. Both need a ModelContainer in the environment, which
    /// a bare snapshot host and an Xcode preview do not have — so harnesses
    /// hand the card its design (or explicitly none) and the resolver, and its
    /// `@Query`, is never constructed at all.
    ///
    /// `preview` is the second half of the same seam: the panel's image comes
    /// from an S3 URL, which a harness cannot fetch, so a rendered preview can
    /// be handed in alongside the design. Nil renders the panel's own
    /// placeholder — which is exactly what an offline device shows too.
    enum DeckSource {
        case resolve
        case injected(DeckDesign?, preview: UIImage?)
    }

    /// Where the site-visit row's state comes from. Same seam as `DeckSource`,
    /// for the same reason: `resolve` reads SwiftData through `@Query`, which
    /// needs a ModelContainer a bare snapshot host and an Xcode preview do not
    /// have. Handing the state in means the resolver — and its query — is never
    /// constructed at all.
    enum SiteVisitSource {
        case resolve
        case injected(LeadSiteVisitPanel.State)
    }

    let row: DaySheetViewModel.Row
    let canEdit: Bool
    let canConvert: Bool
    /// The screen holds the one-open-id; the card just renders the state.
    let isExpanded: Bool
    var onExpand: () -> Void = {}
    /// The press. The screen routes it — `committer.press` for a stamp, the won
    /// flow for WON — because only the screen holds the operator id.
    var onMilestone: (LeadMilestone) -> Void = { _ in }
    /// The open undo window, if there is one. Defaulted so previews, snapshot
    /// harnesses and the sheet's own idle rows construct the card unchanged;
    /// the screen owns the one instance and hands it to every card.
    var committer: LeadMilestoneCommitter?
    var onFullLead: () -> Void = {}
    /// Expand the drawing. The screen presents `DeckFullscreenViewer` — it owns
    /// the viewer's tool state, which has to outlive this card (a milestone
    /// press re-derives the groups and rebuilds the row's view).
    var onViewDeck: (DeckDesign) -> Void = { _ in }
    var onStage: (PipelineStage) -> Void = { _ in }
    var onWon: () -> Void = {}
    var onLost: () -> Void = {}
    var onArchive: () -> Void = {}
    var onDiscard: () -> Void = {}
    /// Start or resume the site-visit capture. The SCREEN routes it into the
    /// tab's ONE `activeSiteVisitLead` cover — the card never presents capture
    /// itself, because a second presentation path for the same flow is how two
    /// visits get opened on one lead.
    ///
    /// Nil means this operator may not capture on this lead, and a lead with no
    /// visit then shows nothing at all.
    var onStartSiteVisit: (() -> Void)?
    /// Production leaves this `.resolve`.
    var deckSource: DeckSource = .resolve
    /// Production leaves this `.resolve`.
    var siteVisitSource: SiteVisitSource = .resolve

    /// Read the INJECTED store, never `PermissionStore.shared`: the shared
    /// store fails closed before hydration, which would blank the deck panel and
    /// the EST line on a cold-launch race and in every preview.
    @EnvironmentObject private var permissionStore: PermissionStore

    private var lead: Opportunity { row.lead }

    var body: some View {
        VStack(spacing: 0) {
            face
                .modifier(DaySheetCardHeaderShell(isExpanded: isExpanded))
            if isExpanded {
                // Opacity only. A move/slide on top of the height change would
                // give one tap two motions, and the clip below already keeps
                // the growing body inside the panel while it fades up.
                expandedContent
                    .transition(.opacity)
            }
        }
        .commandCard()
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous))
    }

    // MARK: - Face

    private var face: some View {
        DaySheetLeadRow(
            row: row,
            canEdit: canEdit,
            canConvert: canConvert,
            isExpanded: isExpanded,
            embedded: true,
            onExpand: onExpand,
            onStage: onStage,
            onWon: onWon,
            onLost: onLost,
            onArchive: onArchive,
            onDiscard: onDiscard
        )
    }

    // MARK: - Expanded body

    /// One rhythm for the whole body (`spacing2_5`), the same beat the shipped
    /// lead card uses between its blocks. The footer sits outside the padded
    /// column so its hairline runs the full width of the card.
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                photoStrip
                deckPanel
                siteVisitPanel
                summaryBand
                contactBlock
                quickActions
                milestoneButton
                estimateLine
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing3)

            footer
        }
    }

    // MARK: - 1 · Photos

    private var photoStrip: some View {
        DaySheetPhotoStrip(opportunity: lead, canEdit: canEdit)
    }

    // MARK: - 2 · Deck

    @ViewBuilder
    private var deckPanel: some View {
        if permissionStore.isFeatureEnabled("deck_builder") {
            switch deckSource {
            case .resolve:
                DaySheetDeckResolver(opportunity: lead, onOpen: onViewDeck)
            case .injected(let design, let preview):
                if let design = design {
                    LeadDeckPanel(design: design,
                                  displayTitle: lead.deckDesignTitle,
                                  injectedPreview: preview,
                                  onOpen: onViewDeck)
                }
            }
        }
    }

    // MARK: - 3 · Site visit

    /// Last of the three artifact blocks. State-aware to the point of silence:
    /// an operator who cannot capture on a lead that has never been visited
    /// gets no row, not a disabled one.
    @ViewBuilder
    private var siteVisitPanel: some View {
        switch siteVisitSource {
        case .resolve:
            LeadSiteVisitResolver(opportunity: lead, onCapture: onStartSiteVisit)
        case .injected(let state):
            LeadSiteVisitPanel(
                state: state,
                onCapture: onStartSiteVisit,
                // A harness renders the record row without presenting the
                // record — the sheet needs the artifacts only the resolver has.
                onOpenRecord: {}
            )
        }
    }

    // MARK: - 4 · Summary

    /// Rendered open, always. The collapsed row is the fold; a second fold
    /// inside the surface the operator just opened is a tap that buys nothing.
    ///
    /// The agent rail is an OVERLAY, not a sibling in an HStack. A `Rectangle`
    /// beside the text is height-flexible, so it soaks up every spare point the
    /// parent has to give and the band balloons to fill the card (caught in the
    /// first render of this view). As an overlay it is sized BY the text block
    /// instead of competing with it.
    @ViewBuilder
    private var summaryBand: some View {
        if let summary = trimmedSummary {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                summaryHead
                Text(summary)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(OPSStyle.Layout.spacing2_5)
            // Clears the rail so the head and body share one left edge.
            .padding(.leading, OPSStyle.Layout.Border.thick)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.agentSoft)
            .overlay(alignment: .leading) {
                Rectangle()
                    .fill(OPSStyle.Colors.agentLine)
                    .frame(width: OPSStyle.Layout.Border.thick)
            }
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    private var summaryHead: some View {
        HStack(spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text("SUMMARY")
                .foregroundColor(OPSStyle.Colors.agent)
            if let stamp = summaryStamp {
                Text(" · \(stamp)")
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .monospacedDigit()
            }
        }
        .font(OPSStyle.Typography.miniLabelBold)
        .tracking(1.2)
        .textCase(.uppercase)
    }

    // MARK: - 5 · Contact

    private var contactBlock: some View {
        LeadContactBlock(
            lead: lead,
            onCall: placeCall,
            onText: touchText,
            onEmail: touchEmail
        )
    }

    // MARK: - 6 · Quick actions

    /// Survivors flex wider — a lead with no email gets two half-width buttons,
    /// not two buttons and a dead grey third.
    @ViewBuilder
    private var quickActions: some View {
        if hasPhone || hasEmail {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if hasPhone {
                    DaySheetQuickAction(label: "CALL", action: placeCall)
                    DaySheetQuickAction(label: "TEXT", action: touchText)
                }
                if hasEmail {
                    DaySheetQuickAction(label: "EMAIL", action: touchEmail)
                }
            }
        }
    }

    // MARK: - 7 · Milestone

    @ViewBuilder
    private var milestoneButton: some View {
        if let milestone = row.milestone {
            if let committer {
                DaySheetMilestoneStamp(
                    milestone: milestone,
                    leadId: lead.id,
                    committer: committer,
                    onPress: onMilestone
                )
            } else {
                DaySheetMilestoneControl(
                    milestone: milestone,
                    pending: nil,
                    onPress: { onMilestone(milestone) },
                    onUndo: {}
                )
            }
        }
    }

    // MARK: - 8 · Estimated value

    /// Quiet, and never on the collapsed row: a runner scanning his day is
    /// choosing who to call next, not ranking his leads by size.
    @ViewBuilder
    private var estimateLine: some View {
        if permissionStore.can("finances.view"),
           let value = lead.estimatedValue, value > 0 {
            HStack(spacing: 0) {
                Text("EST ")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(BooksFormat.currency(value))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - 9 · Footer

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: OPSStyle.Layout.Border.standard)

            Button {
                onFullLead()
            } label: {
                Text("FULL LEAD →")
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Open full lead")
        }
    }

    // MARK: - Contact contracts (verbatim LeadTriageCard)

    /// Record the outbound intent only when this operator can edit the lead,
    /// then dial — the post-call prompt / auto-log picks it up on return.
    private func placeCall() {
        guard hasPhone else { return }
        if PermissionStore.shared.isFeatureEnabled("pipeline"), canEdit {
            CallLogStore.shared.recordOutbound(
                opportunityId: lead.id,
                contactName: lead.contactName,
                phone: lead.contactPhone ?? sanitizedPhone
            )
        }
        guard let url = URL(string: "tel:\(sanitizedPhone)") else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        UIApplication.shared.open(url)
    }

    /// TEXT/EMAIL do-and-stamp. A viewer without edit rights still gets the
    /// conversation (open only) — the stamp write is edit-gated so a doomed
    /// RLS insert never produces an error toast for an allowed action.
    private func touchText() {
        guard hasPhone else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(.text, lead: lead, companyId: lead.companyId)
        } else if let url = URL(string: LeadQuickTouchLogger.smsURLString(phone: lead.contactPhone ?? "")) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    private func touchEmail() {
        guard hasEmail else { return }
        if canEdit {
            LeadQuickTouchLogger.touch(.email, lead: lead, companyId: lead.companyId)
        } else if let url = URL(string: LeadQuickTouchLogger.mailtoURLString(email: lead.contactEmail ?? "", threadSubject: nil)) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
        }
    }

    // MARK: - Derived

    private var hasPhone: Bool {
        guard let phone = lead.contactPhone else { return false }
        return !phone.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasEmail: Bool {
        guard let email = lead.contactEmail else { return false }
        return !email.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var sanitizedPhone: String {
        (lead.contactPhone ?? "").filter { "0123456789+".contains($0) }
    }

    private var trimmedSummary: String? {
        guard let summary = lead.aiSummary?.trimmingCharacters(in: .whitespacesAndNewlines),
              !summary.isEmpty
        else { return nil }
        return summary
    }

    /// NOW / 3H AGO / 2D AGO — the shipped triage-card summary vocabulary, now
    /// spoken by the one type that owns it (`DaySheetDateToken`) rather than by
    /// a second copy of the same four lines living here.
    private var summaryStamp: String? {
        guard let updated = lead.aiSummaryUpdatedAt else { return nil }
        return DaySheetDateToken.age(updated)
    }
}

// MARK: - Header shell

/// Turns the face into a HEADER for the duration of the expansion, and into
/// nothing at all the rest of the time.
///
/// Two marks, because one does not carry it: `surfaceHover` lifts the whole
/// 80pt band a step off `surfaceRaised` so the eye reads two zones before it
/// reads any text, and the rule under it draws the actual seam. The rule is
/// `line`, not the footer's `lineSoft` — this separates the card's two ZONES,
/// while the footer's rule fences off one tertiary link, and the weights say
/// so. Both are inside the card's clip, so the band runs edge to edge and the
/// rule terminates on the panel's own hairline rather than floating short of
/// it.
///
/// Collapsed returns `content` untouched — byte-identical to the shipped scan
/// row, which is the point.
private struct DaySheetCardHeaderShell: ViewModifier {
    let isExpanded: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isExpanded {
            content
                .background(OPSStyle.Colors.surfaceHover)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(OPSStyle.Colors.line)
                        .frame(height: OPSStyle.Layout.Border.standard)
                }
        } else {
            content
        }
    }
}

// MARK: - Photo strip (52pt, shipped strip + shipped add flow)

/// Wraps the ONE lead photo strip the app ships (`LeadPhotosSection`) at the
/// card's tile density, and carries the same add flow `LeadDetailView` uses —
/// camera batch or library, reservation IDs for the placeholder tiles, upload
/// through `LeadImageService` (instant online, durably queued offline).
///
/// The presenters live here rather than on the screen because only ONE card is
/// ever expanded, so exactly one of these exists at a time; hanging a
/// confirmation dialog, a camera cover and a photo picker off every row of a
/// scrolling list would be the wrong trade.
private struct DaySheetPhotoStrip: View {

    let opportunity: Opportunity
    let canEdit: Bool

    /// Spec §3.4.1 — 52pt tiles on the card (the detail document uses 84).
    private static let tileSize: CGFloat = 52

    @ObservedObject private var imageService = LeadImageService.shared

    @State private var showingAddDialog = false
    @State private var showingCamera = false
    @State private var showingLibrary = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var importingPhotoIDs: [String] = []
    @State private var viewerState: LeadPhotoViewerState?

    /// Hidden only when there is nothing to see AND nothing to add — a viewer
    /// without edit rights still sees the photos.
    private var isPresent: Bool {
        canEdit || hasPhotos
    }

    private var hasPhotos: Bool {
        opportunity.images.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            || !imageService.queuedUploads(for: opportunity.id).isEmpty
    }

    var body: some View {
        if isPresent {
            strip
        }
    }

    private var strip: some View {
        LeadPhotosSection(
            opportunity: opportunity,
            canManage: canEdit,
            tileSize: Self.tileSize,
            importingPhotoIDs: importingPhotoIDs,
            onAdd: { showingAddDialog = true },
            onTap: { items, index in
                viewerState = LeadPhotoViewerState(items: items, initialIndex: index)
            }
        )
        .confirmationDialog("ADD PHOTOS", isPresented: $showingAddDialog, titleVisibility: .visible) {
            Button("TAKE PHOTOS") { showingCamera = true }
            Button("CHOOSE FROM LIBRARY") { showingLibrary = true }
            Button("CANCEL", role: .cancel) {}
        }
        .fullScreenCover(isPresented: $showingCamera) {
            CameraBatchView { images in
                showingCamera = false
                guard !images.isEmpty else { return }
                let reservationIDs = images.map { _ in UUID().uuidString }
                importingPhotoIDs.append(contentsOf: reservationIDs)
                addPhotos(images, reservationIDs: reservationIDs)
            }
        }
        .photosPicker(
            isPresented: $showingLibrary,
            selection: $libraryItems,
            maxSelectionCount: 20,
            matching: .images
        )
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            let reservationIDs = items.map { _ in UUID().uuidString }
            importingPhotoIDs.append(contentsOf: reservationIDs)
            libraryItems = []
            Task { await importLibraryItems(items, reservationIDs: reservationIDs) }
        }
        .fullScreenCover(item: $viewerState) { state in
            LeadPhotoViewer(
                opportunity: opportunity,
                canManage: canEdit,
                initialState: state
            )
        }
    }

    // MARK: - Upload (LeadDetailView's contract, unchanged)

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

    private func importLibraryItems(_ items: [PhotosPickerItem], reservationIDs: [String]) async {
        let decoded = await withTaskGroup(
            of: (index: Int, reservationID: String, image: UIImage)?.self
        ) { group in
            for (index, item) in items.enumerated() {
                let reservationID = reservationIDs[index]
                group.addTask {
                    guard let data = try? await item.loadTransferable(type: Data.self),
                          let image = UIImage(data: data) else { return nil }
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

        let result = await LeadImageService.shared.addImages(
            decoded.map(\.image),
            to: opportunity,
            reservationIDs: decoded.map(\.reservationID)
        )
        importingPhotoIDs.removeAll { reservationIDs.contains($0) }

        if decoded.count != items.count || result.failedCount > 0 {
            ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
        } else if result.queuedCount > 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}

// MARK: - Deck resolver

/// `LeadDeckSection`'s resolution, hosted for the card: live local designs via
/// `@Query` (SwiftData invalidates on builder saves) plus a one-shot remote
/// fetch so a cold device pulls a deck drawn elsewhere. Only ever constructed
/// for the open card, and never when the host injects a design.
private struct DaySheetDeckResolver: View {

    let opportunity: Opportunity
    var onOpen: (DeckDesign) -> Void

    @Environment(\.modelContext) private var modelContext
    @Query private var allDesigns: [DeckDesign]
    @State private var remoteFetchAttempted = false

    private var candidate: DeckDesign? {
        DeckDesign.displayCandidate(in: allDesigns, forOpportunityId: opportunity.id)
    }

    var body: some View {
        // VStack, not Group: `.task` on a childless Group never fires, so an
        // empty resolver would never run its self-repair fetch.
        VStack(spacing: 0) {
            if let design = candidate {
                LeadDeckPanel(
                    design: design,
                    displayTitle: opportunity.deckDesignTitle,
                    onOpen: onOpen
                )
            }
        }
        .task(id: opportunity.id) {
            await selfRepairFetchIfNeeded()
        }
    }

    private func selfRepairFetchIfNeeded() async {
        guard candidate == nil, !remoteFetchAttempted else { return }
        remoteFetchAttempted = true

        let repo = DeckDesignRepository(companyId: opportunity.companyId)
        guard let dtos = try? await repo.fetchForOpportunity(opportunity.id) else { return }

        for dto in dtos {
            let designId = DeckDesign.canonicalUUIDString(dto.id)
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate<DeckDesign> { $0.id == designId }
            )
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                existing.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }
        try? modelContext.save()
    }
}

// MARK: - Quick action button

/// One outlined 44pt verb — CALL / TEXT / EMAIL. Neutral surface: the milestone
/// button owns the only accent on this screen.
private struct DaySheetQuickAction: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - Milestone stamp

/// The observing shim. Kept separate so the card itself does not have to hold
/// an `@ObservedObject` it may not have been given — and so exactly one card
/// (the open one) is subscribed to the committer at a time.
private struct DaySheetMilestoneStamp: View {

    let milestone: LeadMilestone
    let leadId: String
    @ObservedObject var committer: LeadMilestoneCommitter
    let onPress: (LeadMilestone) -> Void

    /// Only THIS lead's window. One is open app-wide at any moment, and a card
    /// must never render another lead's confirmation.
    private var pending: LeadMilestoneCommitter.PendingCommit? {
        guard let pending = committer.pending, pending.leadId == leadId else { return nil }
        return pending
    }

    var body: some View {
        DaySheetMilestoneControl(
            milestone: pending?.milestone ?? milestone,
            pending: pending,
            onPress: { onPress(milestone) },
            onUndo: { Task { await committer.undo() } }
        )
        // 150ms crossfade, spec §7. Scoped to THIS control by value: the press
        // that opens the window also flips the lead's stage, and an ambient
        // animation would drag the whole card through that. Idle and pending
        // share a footprint, so there is nothing to animate but opacity — the
        // confirmation settles in place rather than bouncing the column.
        .animation(OPSStyle.Animation.hover, value: pending)
    }
}

/// Two states of one control (spec §4):
///
///   idle     the screen's only accent element — a filled 48pt verb.
///   pending  the same footprint, settled: accent outline instead of accent
///            fill (the app's outlined-accent CTA treatment), the milestone's
///            own confirmation copy, and `UNDO` on the trailing edge.
///
/// The pending state is deliberately NOT one big button. The main body has
/// nothing left to do — pressing it again would not unsend a quote — so only
/// UNDO is tappable, and it owns a full 44pt target of its own.
private struct DaySheetMilestoneControl: View {

    let milestone: LeadMilestone
    let pending: LeadMilestoneCommitter.PendingCommit?
    let onPress: () -> Void
    let onUndo: () -> Void

    var body: some View {
        if let pending {
            confirmation(queued: pending.queuedRequestId != nil)
                .transition(.opacity)
        } else {
            stamp
                .transition(.opacity)
        }
    }

    // MARK: Idle

    private var stamp: some View {
        Button(action: onPress) {
            Text(milestone.label)
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.invertedText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.inputHeight)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                        .fill(OPSStyle.Colors.opsAccent)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Log \(milestone.label.lowercased())")
    }

    // MARK: Pending

    private func confirmation(queued: Bool) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            confirmationLabel
            // Honest and quiet: the stamp is real, it just has not reached the
            // server yet. Neutral tone — accent is spoken for by the outline.
            if queued {
                ToneTag("QUEUED")
            }
            Spacer(minLength: 0)
            undoControl
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .padding(.trailing, OPSStyle.Layout.spacing2)
        .frame(maxWidth: .infinity)
        .frame(height: OPSStyle.Layout.inputHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.opsAccent.opacity(OPSStyle.Layout.Opacity.subtle))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.opsAccent, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var confirmationLabel: some View {
        Text(milestone.confirmationLabel)
            .font(OPSStyle.Typography.buttonLabel)
            .kerning(0.27)
            .textCase(.uppercase)
            .foregroundColor(OPSStyle.Colors.opsAccent)
            .lineLimit(1)
    }

    private var undoControl: some View {
        Button(action: onUndo) {
            Text("UNDO")
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.opsAccent)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin,
                       minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Undo \(milestone.label.lowercased())")
    }
}

// MARK: - Previews

#if DEBUG
#Preview("DaySheetLeadCard / expanded") {
    ScrollView {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Full lead — every block present, edit scope, QUOTE SENT to stamp.
            DaySheetLeadCard(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            title: "Roof tear-off — 28 sq", contactName: "Marcus Webb",
                            stage: .quoting, estimatedValue: 14_200, daysInStage: 5
                        )
                        lead.address = "1841 Beckwith Ave, Burnaby"
                        lead.contactPhone = "604-555-0142"
                        lead.contactEmail = "marcus.webb@example.com"
                        lead.images = ["https://example.com/a.jpg", "https://example.com/b.jpg"]
                        lead.aiSummary = "Quote sent Tuesday. Asked about triple-pane pricing; wife prefers bronze frames. Decision expected after the 15th."
                        lead.aiSummaryUpdatedAt = Calendar.current.date(byAdding: .day, value: -2, to: Date())
                        return lead
                    }(),
                    urgency: .late(days: 3),
                    milestone: .quoteSent
                ),
                canEdit: true,
                canConvert: true,
                isExpanded: true,
                onStartSiteVisit: {},
                // Injected: an Xcode preview has no ModelContainer, so NEITHER
                // resolver's @Query may be constructed here. No preview image
                // either — a canvas render has no network, so the deck panel
                // shows its offline placeholder.
                deckSource: .injected(
                    DeckDesign(companyId: "preview-company",
                               opportunityId: "preview-lead",
                               title: "Back deck — wraparound"),
                    preview: nil
                ),
                siteVisitSource: .injected(
                    .completed(token: "2D AGO",
                               summary: "4 PHOTOS · 2 MEASUREMENTS · NOTES")
                )
            )

            // Sparse + viewer scope — phone only, no strip, no summary, no stamp.
            DaySheetLeadCard(
                row: DaySheetViewModel.Row(
                    lead: {
                        let lead = Opportunity.preview(
                            contactName: "Cedar Ridge HOA", stage: .negotiation, daysInStage: 6
                        )
                        lead.contactPhone = "604-555-0188"
                        return lead
                    }(),
                    urgency: .waiting(back: "BACK FRI"),
                    milestone: nil
                ),
                canEdit: false,
                canConvert: false,
                isExpanded: true,
                // No convert grant → `onStartSiteVisit` stays nil → the visit
                // row is absent entirely, which is the point of this render.
                deckSource: .injected(nil, preview: nil),
                siteVisitSource: .injected(.absent)
            )
        }
        .padding(OPSStyle.Layout.spacing3_5)
    }
    .background(OPSStyle.Colors.background)
    .leadsPreviewEnvironment()
}
#endif
