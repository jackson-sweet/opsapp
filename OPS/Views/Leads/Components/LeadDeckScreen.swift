//
//  LeadDeckScreen.swift
//  OPS
//
//  The lead's deck design, given the whole display. Pushed from the DECK row of
//  the lead dossier (`LeadDetailsDocument` → `LeadDeckSection`).
//
//  Why a pushed screen and not a panel in the dossier: a deck drawing is the
//  quoting artifact, and an operator standing in a driveway reads it, rotates
//  it, and talks a homeowner through it. A drawing shrunk into a document row's
//  content region is a thumbnail with a gesture recognizer. The dossier stays
//  ONE scroll — no tab bar, no competing scroll surfaces — and the drawing gets
//  a destination of its own.
//
//  Everything below the header is the SHIPPED deck engine, unchanged:
//  `DeckTabView` with a `.lead` owner renders the same 3D/2D modes, the same
//  level chips, the same EDIT verb, and the same empty state a project's deck
//  tab renders. The screen contributes only what a host contributes on the
//  project side (`ProjectDetailsView`): the fullscreen tool state, the view
//  mode, the pull-up-to-expand gesture, and the permission call behind EDIT.
//  A deck therefore behaves identically wherever it was drawn.
//
//  MATERIALS is absent by construction, not by suppression: `DeckOwner.project`
//  is nil for a lead, so `DeckTabView` builds a two-segment picker and
//  `DeckMaterialsSection` — which reads the project's tasks and product catalog
//  and writes a real vinyl order — can never be constructed here.
//

import SwiftUI
import SwiftData
import UIKit

struct LeadDeckScreen: View {
    let opportunity: Opportunity

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    /// Live local designs for this lead. The screen re-resolves the display
    /// candidate rather than carrying one in from the row it was pushed from —
    /// a builder save has to land in the viewer without a pop-and-re-push.
    @Query private var allDesigns: [DeckDesign]

    // ── Viewer state ────────────────────────────────────────────────────────
    // Owned HERE, exactly as `ProjectDetailsView` owns the pair: the fullscreen
    // viewer's tool state has to outlive any rebuild of the canvas beneath it,
    // and the view mode has to survive the expand so 3D stays 3D.
    @StateObject private var deckToolState = DeckViewerToolState()
    @State private var deckViewMode: DeckTabViewMode = .threeD
    @State private var isDeckFullscreen = false

    // ── Authoring routes ────────────────────────────────────────────────────
    @State private var deckDesignToOpen: DeckDesign?
    @State private var showingDeckCreationPicker = false

    // ── Pull-up-to-expand probe ─────────────────────────────────────────────
    @State private var deckPull: CGFloat = 0
    @State private var deckPullArmed = false
    @State private var deckContentHeight: CGFloat = 0
    @State private var deckViewportHeight: CGFloat = 0

    private let deckScrollSpace = "leadDeckScroll"

    init(opportunity: Opportunity) {
        self.opportunity = opportunity
        // The SAME three-way id match `DeckTabView`'s lead branch makes:
        // `DeckDesign` canonicalises every id it stores while `Opportunity.id`
        // arrives in whatever case its source produced, so a raw `==` can
        // silently miss a lead's own deck. `displayCandidate` re-filters
        // canonically below, so the wider net costs nothing.
        let canonical = DeckDesign.canonicalUUIDString(opportunity.id)
        let exact: String? = canonical
        let lowered: String? = canonical.lowercased()
        let uppered: String? = canonical.uppercased()
        self._allDesigns = Query(
            filter: #Predicate<DeckDesign> {
                $0.opportunityId == exact
                    || $0.opportunityId == lowered
                    || $0.opportunityId == uppered
            }
        )
    }

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header
                deckScroll
            }

            // Pull cue — floats over the canvas while the operator drags past
            // the bottom, and never eats the drag that summoned it.
            if isDeckOverscrolling {
                deckPullCue
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                    .allowsHitTesting(false)
                    .zIndex(24)
            }

            // Focus mode. A ZStack layer rather than a cover, matching
            // `ProjectDetailsView` — the expand reads as the canvas growing
            // into the screen, and the viewer hides the global tab bar itself.
            if isDeckFullscreen, let design = displayedDeckDesign {
                fullscreenViewer(design: design)
            }
        }
        .navigationBarHidden(true)
        // The whole display means the whole display. The global tab bar is a
        // 100pt manual overlay that would sit on the bottom of the plan AND on
        // the terminus of the pull-up gesture that expands it — the exact
        // occlusion `.hidesGlobalTabBar()` exists for. Back is the header's job.
        .hidesGlobalTabBar()
        .sheet(isPresented: $showingDeckCreationPicker) {
            deckCreationPicker
        }
        .fullScreenCover(item: $deckDesignToOpen) { design in
            deckBuilder(design: design)
        }
    }

    // MARK: - Header

    /// The canonical screen header (MOBILE.md §2.1/§2.3) titled with the lead —
    /// the same name the dossier, the day-sheet card, and the builder title this
    /// lead's work with, so the drawing is never orphaned from its job.
    private var header: some View {
        OPSScreenHeader(opportunity.displayContactName) {
            OPSHeaderBackButton(label: "LEAD") {
                dismiss()
            }
            .accessibilityLabel("Back to lead")
        }
    }

    // MARK: - Canvas

    private var deckScroll: some View {
        ScrollView {
            VStack(spacing: 0) {
                DeckTabView(
                    owner: .lead(opportunity),
                    onCreateDeckDesign: { showingDeckCreationPicker = true },
                    onEditDeckDesign: { deckDesignToOpen = $0 },
                    viewMode: $deckViewMode,
                    onRequestFullscreen: { presentDeckFullscreen() }
                )
                .padding(.top, OPSStyle.Layout.spacing2_5)

                overscrollProbe
            }
            .background(
                GeometryReader { g in
                    Color.clear.onChange(of: g.size.height, initial: true) { _, h in
                        deckContentHeight = h
                    }
                }
            )
        }
        .coordinateSpace(name: deckScrollSpace)
        .scrollIndicators(.hidden)
        // Force the bottom rubber-band even when the canvas fits the viewport,
        // so pull-up-to-expand is always available.
        .scrollBounceBehavior(.always, axes: .vertical)
        .background(
            GeometryReader { g in
                Color.clear.onChange(of: g.size.height, initial: true) { _, h in
                    deckViewportHeight = h
                }
            }
        )
    }

    /// Zero-height reader at the BOTTOM of the content. Scrolling to the end and
    /// pulling UP lifts this child above the viewport bottom; the difference is
    /// the overscroll distance that drives the expand.
    private var overscrollProbe: some View {
        GeometryReader { geo in
            Color.clear
                .onChange(of: geo.frame(in: .named(deckScrollSpace)).maxY) { _, maxY in
                    let restBottom = min(deckContentHeight, deckViewportHeight)
                    updateDeckPull(max(0, restBottom - maxY))
                }
        }
        .frame(height: 0)
    }

    // MARK: - Fullscreen

    private func fullscreenViewer(design: DeckDesign) -> some View {
        DeckFullscreenViewer(
            title: opportunity.displayContactName,
            drawingData: design.drawingData,
            viewMode: $deckViewMode,
            toolState: deckToolState,
            onClose: { dismissDeckFullscreen() },
            onEdit: canEditDeckDesign
                ? { editDeckDesignFromFullscreen(design) }
                : nil
        )
        .zIndex(30)
        .transition(reduceMotion ? .opacity : .scale(scale: 0.92).combined(with: .opacity))
    }

    // MARK: - Deck resolution + expand gate

    /// The design the canvas is currently showing — mirrors `DeckTabView`'s own
    /// selection so the viewer can never expand a different drawing.
    private var displayedDeckDesign: DeckDesign? {
        DeckDesign.displayCandidate(in: allDesigns, forOpportunityId: opportunity.id)
    }

    private var hasRenderableDeck: Bool {
        displayedDeckDesign?.hasRenderableGeometry == true
    }

    /// The canvas is being pulled past its end — the cue-visible window.
    private var isDeckOverscrolling: Bool {
        !isDeckFullscreen && hasRenderableDeck && deckViewMode != .materials && deckPull > 1
    }

    private var deckExpandProgress: CGFloat { DeckOverscrollMath.progress(pull: deckPull) }

    /// Called on every scroll change with the bottom-edge overscroll amount in
    /// points. The instant the pull crosses the threshold, fire the haptic and
    /// open fullscreen (one-shot via `deckPullArmed`); below the threshold the
    /// scroll rubber-bands back on its own.
    ///
    /// `.materials` is unreachable for a lead (the segment is never built), but
    /// the gate is kept identical to the project host's: fullscreen has no
    /// materials form, and the guard also absorbs the content-height collapse a
    /// mode swap would read as a huge "pull" for one frame.
    private func updateDeckPull(_ pull: CGFloat) {
        guard hasRenderableDeck, !isDeckFullscreen, deckViewMode != .materials else {
            if deckPull != 0 { deckPull = 0 }
            deckPullArmed = false
            return
        }
        deckPull = pull
        if DeckOverscrollMath.isCommitted(pull: pull), !deckPullArmed {
            deckPullArmed = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            presentDeckFullscreen()
        } else if pull < DeckOverscrollMath.commitThreshold {
            deckPullArmed = false
        }
    }

    /// Expand, from the pull gesture or the VoiceOver action.
    ///
    /// The tool-state reset runs BEFORE the present rather than after the
    /// dismiss (`ProjectDetailsView` cleans up on the way out): the drawing then
    /// always arrives in a read state — no stale measurement, no leftover
    /// selection, no isolated level — no matter how the last session ended.
    private func presentDeckFullscreen() {
        if deckViewMode == .materials { deckViewMode = .twoD }
        deckToolState.mode = .none
        deckToolState.clearSelection()
        deckToolState.isolatedLevelId = nil
        deckToolState.showDimensions = true
        // The token is already reduce-motion aware; `reduceMotion` is still read
        // for the transition's CHARACTER (scale vs. plain crossfade), which no
        // duration token can express.
        withAnimation(OPSStyle.Animation.page) {
            isDeckFullscreen = true
        }
    }

    private func dismissDeckFullscreen() {
        withAnimation(OPSStyle.Animation.page) {
            isDeckFullscreen = false
        }
    }

    // MARK: - Edit

    /// May this operator edit THIS lead's deck? The same three shipped gates the
    /// day-sheet viewer makes, no new rule: the deck-builder feature flag, the
    /// deck-builder edit grant (the call the deck tab's own EDIT verb makes),
    /// and the lead's assignment policy — `assigned` scope is entity-relative,
    /// so a delegate may edit the deck on HIS lead and not on someone else's.
    private var canEditDeckDesign: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
            && permissionStore.can("deck_builder.edit", requiredScope: "assigned")
            && permissionStore.leadAccessPolicy.can(.edit, assignedTo: opportunity.assignedTo)
    }

    /// EDIT from the fullscreen viewer: close the viewer, THEN open the builder.
    /// The builder is a `.fullScreenCover` and iOS will not present a modal
    /// while another presentation is still animating, so the handoff waits out
    /// the expand's animate-out rather than racing it.
    private func editDeckDesignFromFullscreen(_ design: DeckDesign) {
        dismissDeckFullscreen()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            deckDesignToOpen = design
        }
    }

    // MARK: - Pull cue

    /// Cue shown over the canvas during the bottom overscroll.
    ///
    /// Rendered on the design system's own transient surface (`.glassDense` —
    /// the toast/popover treatment) rather than the project host's hand-mixed
    /// black capsule, so every value here traces to a token.
    @ViewBuilder
    private var deckPullCue: some View {
        let committed = deckExpandProgress >= 1
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: "chevron.up")
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                .foregroundColor(committed ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            Text(committed ? "RELEASE TO EXPAND" : "PULL TO EXPAND")
                .font(OPSStyle.Typography.metadata)
                .tracking(1)
                .foregroundColor(committed ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .glassDense(cornerRadius: OPSStyle.Layout.modalRadius)
        .opacity(Double(min(1, deckExpandProgress * 1.4)))
    }

    // MARK: - Authoring

    /// Reached only from the deck tab's empty state — a design row exists but
    /// nothing was ever drawn into it. Picker dismisses BEFORE the builder
    /// presents; iOS cannot stack two modals.
    @ViewBuilder
    private var deckCreationPicker: some View {
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
}
