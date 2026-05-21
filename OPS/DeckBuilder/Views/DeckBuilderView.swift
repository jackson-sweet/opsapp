// OPS/OPS/DeckBuilder/Views/DeckBuilderView.swift

import SwiftUI
import SwiftData
import UIKit

struct DeckBuilderView: View {
    @StateObject private var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showingTemplatePicker = false
    @State private var showingTemplateReplaceConfirm = false
    @State private var showingSketchCapture = false
    @State private var showingARPerimeter = false
    @State private var hideVerifiedBanner = false
    @State private var showingEstimateDetail = false
    @StateObject private var scene3DController = Scene3DController()
    @State private var showing3DScreenshotShare = false
    @State private var screenshotImage: UIImage?
    @State private var editingTitleText: String = ""
    @StateObject private var estimateVM = EstimateViewModel()
    @Environment(\.modelContext) private var env_modelContext
    @Query(sort: \TaskType.displayOrder) private var taskTypes: [TaskType]

    let projectId: String?
    let companyId: String

    /// Top safe-area inset for the current key window. Read at usage time so
    /// devices with a Dynamic Island (top inset ~59pt) and notched iPhones
    /// (~47pt) both clear the hardware cutout — `.statusBarHidden(true)`
    /// only hides the clock, it does NOT shrink the system-reserved top
    /// region. Bug 55083a46.
    private var topSafeAreaInset: CGFloat {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let keyWindow = scenes.flatMap { $0.windows }.first(where: { $0.isKeyWindow })
        return keyWindow?.safeAreaInsets.top ?? 0
    }

    /// Extra top padding applied to every floating canvas overlay (title
    /// pill, edit cluster, live-dim pill, screenshot button) ON TOP of the
    /// inherited safe-area inset. The container ZStack/VStack already
    /// pushes its children below the safe-area top, so this only needs to
    /// top up to a minimum visual gap on devices without a hardware cutout
    /// (e.g. iPhone SE with the status bar hidden). On Dynamic Island /
    /// notch devices the inherited inset already covers the minimum and
    /// this returns 0 — bug 432a4e34 fixed the double-padding that pushed
    /// the title visibly far below the island.
    private var floatingHeaderTopPadding: CGFloat {
        max(0, OPSStyle.Layout.spacing3 - topSafeAreaInset)
    }

    init(deckDesign: DeckDesign, modelContext: ModelContext, syncEngine: SyncEngine? = nil) {
        // Bug ab554b5f — pass the SyncEngine to the view model so saves
        // enqueue Supabase pushes. Optional so test/preview call sites that
        // don't have a configured engine still compile and run.
        self._viewModel = StateObject(wrappedValue: DeckBuilderViewModel(
            deckDesign: deckDesign,
            modelContext: modelContext,
            syncEngine: syncEngine
        ))
        self.projectId = deckDesign.projectId
        self.companyId = deckDesign.companyId
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.is3DMode {
                // 3D mode: contained title pill, screenshot button floats over
                // the scene as a separate canvas-aligned cluster (matches the
                // 2D layout's floating-cluster pattern).
                titleBar
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.top, floatingHeaderTopPadding)

                ZStack(alignment: .topTrailing) {
                    DeckScene3DView(drawingData: viewModel.drawingData, controller: scene3DController)
                        .transition(.opacity)

                    screenshot3DButton
                        .padding(.trailing, OPSStyle.Layout.spacing4)
                        .padding(.top, OPSStyle.Layout.spacing2)
                }
                .ignoresSafeArea(edges: .horizontal)

                CameraPresetBar { preset in
                    scene3DController.setCameraPreset(preset)
                }
                .transition(.opacity)
            } else {
                // 2D mode: canvas fills screen, title bar floats on top
                ZStack(alignment: .top) {
                    // Full-bleed canvas — extends under the status bar / dynamic
                    // island and to the screen edges. The bottom DeckToolbar is
                    // a sibling of this ZStack so the bottom safe-area inset is
                    // preserved for the home indicator. Bug 0a5f3fe1.
                    ZStack(alignment: .bottomTrailing) {
                        DeckCanvasView(viewModel: viewModel)
                            .ignoresSafeArea(edges: [.top, .horizontal])

                    // Assignment wheel — visible only when there are edges in the
                    // selection. The wheel exposes edge-specific choices
                    // (railing styles, edge type, add stairs, dimension) that
                    // aren't in the toolbar quick-access. For surface-only
                    // selections it would collapse to a single "Material"
                    // button floating in the canvas — duplicating the
                    // toolbar's material button — so we hide it there
                    // (DECK-NEW-2). 24pt margin keeps the 56pt center circle
                    // off the rounded screen corner on modern iPhones.
                    if viewModel.selection.hasEdges {
                        AssignmentWheelView(viewModel: viewModel)
                            .padding(.trailing, OPSStyle.Layout.spacing4)
                            .padding(.bottom, OPSStyle.Layout.spacing4)
                            .transition(.scale.combined(with: .opacity))
                    }

                    // Laser toasts
                    VStack(spacing: 6) {
                        Spacer()

                        // Disconnect / reconnecting toast
                        if viewModel.showDisconnectToast {
                            laserToast(
                                icon: "antenna.radiowaves.left.and.right.slash",
                                text: viewModel.disconnectToastText,
                                color: OPSStyle.Colors.errorStatus
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Measurement error toast
                        if viewModel.showLaserErrorToast {
                            laserToast(
                                icon: "exclamationmark.triangle.fill",
                                text: viewModel.laserErrorText,
                                color: OPSStyle.Colors.errorStatus
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Buffered measurement toast
                        if viewModel.showMeasurementToast {
                            laserToast(
                                icon: "antenna.radiowaves.left.and.right",
                                text: viewModel.measurementToastText,
                                color: OPSStyle.Colors.warningStatus
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Material assignment confirmation toast
                        if viewModel.showAssignmentToast {
                            laserToast(
                                icon: "checkmark.circle.fill",
                                text: viewModel.assignmentToastText,
                                color: OPSStyle.Colors.primaryAccent
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showMeasurementToast)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showLaserErrorToast)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showDisconnectToast)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showAssignmentToast)
                    } // end canvas ZStack (bottomTrailing)

                    // Floating header — compact stack. The title bar and the
                    // (optional) level tab bar share a single rounded card so
                    // the levels read as an extension of the title overlay
                    // instead of a separate floating bar. The card height is
                    // measured live and the edit cluster + live-dim pill
                    // anchor immediately below the card, so they slide down
                    // when the level row appears and back up when it hides.
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        // Unified header card. Levels live inside it; the
                        // previous fallback to vertices.count >= 3 showed
                        // the bar in single-level mode the moment a second
                        // line was drawn, but the bar's body had nothing to
                        // render — bug 59c76731.
                        VStack(alignment: .leading, spacing: 0) {
                            titleBar
                                .padding(.horizontal, OPSStyle.Layout.spacing2)
                                .padding(.vertical, OPSStyle.Layout.spacing2)

                            if viewModel.isMultiLevel {
                                // Edge-to-edge hairline so the level row
                                // reads as an extension of the card, not a
                                // floating sibling.
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorder.opacity(0.6))
                                    .frame(height: OPSStyle.Layout.Border.standard)

                                LevelTabBar(viewModel: viewModel)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                                )
                                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                        .animation(OPSStyle.Animation.fast, value: viewModel.isMultiLevel)

                        // Edit cluster / live-dim row — sits in the VStack
                        // flow immediately below the header card so it can
                        // never overlap (the prior absolute-positioned
                        // approach raced the PreferenceKey measurement and
                        // landed the cluster on top of the title bar on first
                        // render — bug ee787f29 follow-up). Edit cluster
                        // anchors trailing; live-dim pill anchors leading per
                        // the reporter's request — the drawing finger sits on
                        // the right edge of the canvas, so the live-dim
                        // readout works harder on the opposite side.
                        if PermissionStore.shared.can("deck_builder.edit"),
                           viewModel.liveDimensionLabel == nil {
                            HStack(spacing: 0) {
                                Spacer(minLength: 0)
                                editCluster2D
                            }
                        }
                        if let liveLabel = viewModel.liveDimensionLabel {
                            HStack(spacing: 0) {
                                liveDimensionPill(label: liveLabel)
                                Spacer(minLength: 0)
                            }
                            .transition(.opacity)
                            .animation(OPSStyle.Animation.fast, value: viewModel.liveDimensionLabel)
                        }

                        // Combined metrics + AR row — when both apply they
                        // share a single horizontal row instead of stacking
                        // as two rows. Lives outside the card so the card
                        // stays compact and the metrics float on the canvas.
                        metricsAndARRow

                        Spacer(minLength: 0)
                    }
                    // Floating header sits inside the safe area while the canvas
                    // extends under it. Horizontal: spacing4 from screen edge so
                    // the title pill clears the rounded corners and never bleeds
                    // off-screen. Top: `floatingHeaderTopPadding` reads the device
                    // safe-area inset so the pill always sits below the Dynamic
                    // Island / notch instead of being clipped by it (bug
                    // 55083a46). spacing3 is the minimum on devices without a
                    // hardware cutout (small iPhone SE).
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.top, floatingHeaderTopPadding)
                    .allowsHitTesting(true)

                } // end ZStack (top-aligned, floating title over canvas)

                // Toolbar — below the canvas. Wrapped in horizontal padding +
                // bottom gap + clipped corners so its cardBackground reads as a
                // contained pill instead of a full-width bar bleeding to the
                // screen edges. Matches the floating header pill aesthetic.
                // Bug 0a5f3fe1 follow-up.
                DeckToolbar(viewModel: viewModel)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.bottom, OPSStyle.Layout.spacing2)
            }
        }
        .background(OPSStyle.Colors.background)
        .sheet(isPresented: $viewModel.showingSettings) {
            DeckSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingDimensionInput) {
            DimensionInputView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingElevationInput) {
            ElevationInputView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingStairConfig) {
            StairConfigView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingMaterialPicker) {
            MaterialPickerSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingVinylOrderSheet) {
            VinylOrderSheet(
                viewModel: viewModel,
                projectId: projectId,
                companyId: companyId
            )
        }
        .sheet(isPresented: $viewModel.showingPropertySheet) {
            PropertySheetView(viewModel: viewModel)
        }
        .sheet(isPresented: $viewModel.showingLevelConnectionSheet) {
            LevelConnectionSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showingTemplatePicker) {
            TemplatePickerView(
                initialTab: 0,
                projectId: viewModel.deckDesign.projectId,
                companyId: viewModel.deckDesign.companyId,
                userId: viewModel.deckDesign.createdBy,
                onDesignCreated: { newDesign in
                    viewModel.drawingData = newDesign.drawingData
                    viewModel.save()
                    showingTemplatePicker = false
                }
            )
        }
        .fullScreenCover(isPresented: $showingSketchCapture) {
            SketchCaptureView(
                projectId: viewModel.deckDesign.projectId,
                companyId: viewModel.deckDesign.companyId,
                userId: viewModel.deckDesign.createdBy
            ) { scanResult in
                let drawingData = scanResult.toDeckDrawingData(
                    canvasWidth: 600,
                    canvasHeight: 400
                )
                viewModel.drawingData = drawingData
                viewModel.save()
                showingSketchCapture = false
            }
        }
        .fullScreenCover(isPresented: $showingARPerimeter) {
            ARPerimeterView { drawingData in
                guard !drawingData.vertices.isEmpty else {
                    showingARPerimeter = false
                    return
                }
                viewModel.drawingData = drawingData
                viewModel.save()
                showingARPerimeter = false
            }
        }
        .fullScreenCover(isPresented: $viewModel.showingARVisualization) {
            ARVisualizationView(drawingData: viewModel.drawingData)
        }
        // Photo source picker
        .sheet(isPresented: $viewModel.showingPhotoSourcePicker) {
            PhotoSourcePickerView(
                projectId: viewModel.deckDesign.projectId,
                onPhotoSelected: { photo in
                    viewModel.selectedSitePhoto = photo
                    viewModel.showingPhotoSourcePicker = false
                    viewModel.showingPhotoOverlayEditor = true
                }
            )
        }
        // Photo overlay editor
        .fullScreenCover(isPresented: $viewModel.showingPhotoOverlayEditor) {
            if let photo = viewModel.selectedSitePhoto {
                PhotoOverlayEditorView(
                    initialSitePhoto: photo,
                    drawingData: viewModel.drawingData,
                    projectId: viewModel.deckDesign.projectId,
                    companyId: viewModel.deckDesign.companyId,
                    userId: viewModel.deckDesign.createdBy,
                    deckTitle: viewModel.deckDesign.title,
                    onSave: { state in
                        viewModel.savePhotoOverlayState(state)
                        viewModel.showingPhotoOverlayEditor = false
                    },
                    onDismiss: {
                        viewModel.showingPhotoOverlayEditor = false
                    }
                )
            }
        }
        // Estimate preview sheet
        .sheet(isPresented: $viewModel.showingEstimatePreview) {
            EstimatePreviewSheet(viewModel: viewModel)
        }
        // Duplicate estimate alert
        .alert("Replace Current Drawing?", isPresented: $showingTemplateReplaceConfirm) {
            Button("Replace", role: .destructive) {
                showingTemplatePicker = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will replace your current drawing with a template.")
        }
        .alert("Estimate Already Exists", isPresented: $viewModel.showingDuplicateAlert) {
            Button("Create New Version") {
                Task { await viewModel.generateEstimate() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("An estimate already exists for this deck. Create a new version?")
        }
        // Share options dialog
        .confirmationDialog("Share Deck Design", isPresented: $viewModel.showingShareOptions) {
            Button("Share Image") {
                viewModel.shareIncludesMaterialList = false
                Task { await viewModel.prepareShareImage() }
            }
            Button("Share with Material List") {
                viewModel.shareIncludesMaterialList = true
                Task { await viewModel.prepareShareImage() }
            }
            Button("Export PDF") {
                Task { await viewModel.prepareSharePDF() }
            }
            Button("Cancel", role: .cancel) {}
        }
        // Share sheet (image or PDF)
        .sheet(isPresented: $viewModel.showingShareSheet) {
            if let image = viewModel.shareImage {
                if viewModel.shareIncludesMaterialList {
                    let text = viewModel.materialSummaryText()
                    ActivityView(items: [image, text])
                        .onDisappear { viewModel.shareImage = nil }
                } else {
                    ActivityView(items: [image])
                        .onDisappear { viewModel.shareImage = nil }
                }
            } else if let pdfData = viewModel.sharePDFData {
                ActivityView(items: [pdfData])
                    .onDisappear { viewModel.sharePDFData = nil }
            }
        }
        // 3D screenshot share
        .sheet(isPresented: $showing3DScreenshotShare) {
            if let image = screenshotImage {
                ActivityView(items: [image])
                    .onDisappear { screenshotImage = nil }
            }
        }
        // Estimate detail sheet (opened from toast tap)
        .sheet(isPresented: $showingEstimateDetail) {
            if let estimate = viewModel.createdEstimate {
                NavigationStack {
                    EstimateDetailView(estimate: estimate, viewModel: estimateVM)
                }
            }
        }
        .alert("Missing Scale", isPresented: .init(
            get: { viewModel.estimateValidationError != nil },
            set: { if !$0 { viewModel.estimateValidationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.estimateValidationError ?? "")
        }
        // Estimate created toast — tappable to navigate
        .overlay(alignment: .bottom) {
            if viewModel.estimateCreated, let number = viewModel.createdEstimateNumber {
                Button {
                    viewModel.estimateCreated = false
                    estimateVM.setup(companyId: companyId, modelContext: env_modelContext)
                    showingEstimateDetail = true
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.successStatus)

                        Text("Estimate created \u{2014} \(number)")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                }
                .padding(.bottom, 80)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: viewModel.estimateCreated)
            }
        }
        // Save error toast
        .overlay(alignment: .top) {
            if let error = viewModel.saveError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    Text(error)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                .padding(.top, 60)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation { viewModel.saveError = nil }
                    }
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.saveError)
        // Undo-affects-all-levels toast
        .overlay(alignment: .top) {
            if viewModel.showUndoLevelToast {
                Text("Undo affects all levels.")
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
                    .padding(.top, 100)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                            withAnimation { viewModel.showUndoLevelToast = false }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.showUndoLevelToast)
        .alert("Clear this design?", isPresented: $viewModel.showingClearConfirm) {
            Button("Clear", role: .destructive) {
                viewModel.clearDesign()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
        // Bug 2b1f1a9e — autosave prompt for EXISTING drawings on first edit.
        // New drawings autosave silently; existing drawings opt in here so the
        // user knows their working copy will be saved every couple of minutes
        // without a manual commit.
        .alert("Save your edits automatically?", isPresented: $viewModel.showingAutosavePrompt) {
            Button("Yes, every 2 minutes") {
                viewModel.enableAutosave()
            }
            Button("Not now", role: .cancel) {
                viewModel.declineAutosave()
            }
        } message: {
            Text("OPS can save your changes to this drawing every 2 minutes so you don't lose work.")
        }
        .statusBarHidden(true)
        .onAppear {
            // Defense-in-depth: prevent deep-link or programmatic access bypassing UI gate
            if !PermissionStore.shared.isFeatureEnabled("deck_builder") {
                dismiss()
            }
            viewModel.taskTypes = taskTypes.filter { $0.deletedAt == nil }
        }
        .onChange(of: taskTypes.count) { _, _ in
            viewModel.taskTypes = taskTypes.filter { $0.deletedAt == nil }
        }
    }

    // MARK: - Live Dimension Pill

    /// Live dimension pill — floats on the canvas at top-center while a
    /// draw is in flight. Used to live in a header row beside the title;
    /// moved to canvas overlay so the header row 2 could be deleted.
    @ViewBuilder
    private func liveDimensionPill(label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "ruler")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Text(label)
                .font(.system(size: 14, weight: .bold, design: .monospaced))
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
        )
        .allowsHitTesting(false)
    }

    private func commitTitleEdit() {
        viewModel.renameDesign(to: editingTitleText)
        viewModel.isEditingTitle = false
    }

    // MARK: - Title Bar

    /// Compact single-row title bar used in both 2D and 3D modes.
    /// Layout: close | save-dot | title (flex, editable) | 2D/3D | gear.
    /// Import (2D) and screenshot (3D) live in a separate floating cluster
    /// over the canvas — keeps this bar narrow enough to fit on iPhone SE
    /// without bleeding past the pill edges.
    private var titleBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Close
            Button {
                guard !isSaving else { return }
                isSaving = true
                Task {
                    await viewModel.renderAndSave()
                    dismiss()
                }
            } label: {
                if isSaving {
                    ProgressView()
                        .tint(.white)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                } else {
                    Image(systemName: OPSStyle.Icons.xmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .disabled(isSaving)

            // Save status dot — tracks local persistence, not remote sync.
            // Color encodes state (green = saved, amber = saving). Text label
            // intentionally absent so the bar fits in portrait without the
            // pill bleeding past the screen edge.
            Circle()
                .fill(viewModel.isLocallySaved ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                .frame(width: 8, height: 8)
                .accessibilityLabel(viewModel.isLocallySaved ? "Saved" : "Saving")

            // Title — flex content. Tap to edit when edit permission allows.
            inlineTitleEditor

            // 2D/3D toggle. 80pt is enough for "2D"/"3D" labels and saves
            // 16pt vs the previous 96pt — meaningful margin on iPhone SE.
            SegmentedControl(
                selection: Binding(
                    get: { viewModel.is3DMode },
                    set: { newValue in
                        withAnimation(OPSStyle.Animation.standard) {
                            viewModel.is3DMode = newValue
                        }
                    }
                ),
                options: [
                    (false, "2D"),
                    (true, "3D")
                ]
            )
            .frame(width: 80)
            .disabled(!viewModel.can3DMode)

            // Always-visible canvas settings — reachable from ANY tool/selection state.
            Button {
                viewModel.showingSettings = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    /// In-bar title editor. Read state shows `Title • pencil` (tap to edit
    /// when allowed). Edit state shows a TextField with a confirm checkmark.
    /// Truncates with ellipsis on narrow screens.
    @ViewBuilder
    private var inlineTitleEditor: some View {
        if viewModel.isEditingTitle {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                TextField("Design name", text: $editingTitleText)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .textFieldStyle(.plain)
                    .submitLabel(.done)
                    .onSubmit { commitTitleEdit() }

                Button {
                    commitTitleEdit()
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 28, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            let canEditTitle = PermissionStore.shared.can("deck_builder.edit")
            Button {
                guard canEditTitle else { return }
                editingTitleText = viewModel.deckDesign.title
                viewModel.isEditingTitle = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(viewModel.deckDesign.title)
                        .font(OPSStyle.Typography.bodyEmphasis)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if canEditTitle {
                        Image(systemName: "pencil")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.6))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .disabled(!canEditTitle)
        }
    }

    // MARK: - Floating Canvas Clusters

    /// Edit cluster — undo, redo, import menu — floats over the 2D canvas
    /// just below the title bar. Removed from the header VStack so it no
    /// longer occupies a permanent 44pt row when the user isn't actively
    /// editing.
    @ViewBuilder
    private var editCluster2D: some View {
        HStack(spacing: 0) {
            Button { viewModel.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(viewModel.canUndo ? Color.white : OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!viewModel.canUndo)

            Divider()
                .frame(width: 1, height: 24)
                .overlay(OPSStyle.Colors.cardBorder.opacity(0.4))

            Button { viewModel.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(viewModel.canRedo ? Color.white : OPSStyle.Colors.tertiaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!viewModel.canRedo)

            Divider()
                .frame(width: 1, height: 24)
                .overlay(OPSStyle.Colors.cardBorder.opacity(0.4))

            Menu {
                Button {
                    if viewModel.drawingData.allVertices.count > 0 {
                        showingTemplateReplaceConfirm = true
                    } else {
                        showingTemplatePicker = true
                    }
                } label: {
                    Label("From Template", systemImage: "square.grid.2x2")
                }
                Button { showingSketchCapture = true } label: {
                    Label("Scan Paper Sketch", systemImage: "doc.text.viewfinder")
                }
                Button { showingARPerimeter = true } label: {
                    Label("Walk Perimeter (AR)", systemImage: "camera.viewfinder")
                }
                Divider()
                if viewModel.isLaserConnected {
                    Label("Laser Connected", systemImage: "antenna.radiowaves.left.and.right")
                } else {
                    Button(action: {}) {
                        Label("Connect Laser Meter", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    .disabled(true)
                }
            } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
        )
    }

    /// 3D screenshot button — single-button floating cluster matching the
    /// 2D edit cluster's styling. Replaces the previous in-titleBar camera
    /// button so the title bar layout stays identical across modes.
    @ViewBuilder
    private var screenshot3DButton: some View {
        Button {
            if let screenshot = scene3DController.captureScreenshot() {
                screenshotImage = screenshot
                showing3DScreenshotShare = true
            }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            Image(systemName: "camera.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                )
                .shadow(color: Color.black.opacity(0.25), radius: 10, y: 4)
        )
    }

    // MARK: - Combined metrics + AR row

    /// Renders metrics and AR banner on a single horizontal row when both
    /// apply, or just one of them when the other is absent. Replaces the
    /// previous two stacked rows so the floating header is shorter.
    @ViewBuilder
    private var metricsAndARRow: some View {
        let showMetrics = viewModel.isClosed && viewModel.totalArea != nil
        let arState = arBannerState
        let showAR = arState != .none

        if showMetrics || showAR {
            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                if showMetrics, let area = viewModel.totalArea {
                    metricsContent(area: area)
                }
                if showAR {
                    arBannerContent(state: arState)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: - Metrics + AR content (compact, single-row)

    /// Pill-shaped metrics content (sqft + lin ft). Sized to its intrinsic
    /// width; the parent decides whether to share a row with the AR banner.
    @ViewBuilder
    private func metricsContent(area: Double) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Label(DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem),
                  systemImage: "square.dashed")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(Color.white)
                .lineLimit(1)
            if let perimeter = viewModel.totalPerimeter {
                Label(DimensionEngine.format(perimeter, system: viewModel.drawingData.config.measurementSystem),
                      systemImage: "ruler")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground.opacity(0.96))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
        )
        .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
        .fixedSize(horizontal: true, vertical: false)
    }

    /// State of the AR-derived dimensions banner.
    private enum ARBannerState {
        case none
        case warning   // AR estimate; refine for material ordering
        case verified  // All edges verified after AR
    }

    private var arBannerState: ARBannerState {
        let hasAREdges = viewModel.drawingData.edges.contains { $0.accuracyPercent != nil }
        if hasAREdges { return .warning }
        let hasAnyARSource = viewModel.drawingData.edges.contains { $0.dimensionSource == .ar }
        let allVerified = AccuracyModel.allEdgesVerified(viewModel.drawingData)
        if hasAnyARSource && allVerified && !hideVerifiedBanner { return .verified }
        return .none
    }

    /// AR banner content with no outer padding/background of its own beyond
    /// what the row provides. Tinted by state.
    @ViewBuilder
    private func arBannerContent(state: ARBannerState) -> some View {
        switch state {
        case .none:
            EmptyView()
        case .warning:
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                Text("AR Estimate — refine with tape or laser")
                    .font(OPSStyle.Typography.smallCaption)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.warningStatus.opacity(0.15))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        case .verified:
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                Text("All dimensions verified")
                    .font(OPSStyle.Typography.smallCaption)
                    .lineLimit(1)
            }
            .foregroundColor(OPSStyle.Colors.successStatus)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.successStatus.opacity(0.1))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation { hideVerifiedBanner = true }
                }
            }
        }
    }

    // MARK: - Laser Toast Helper

    private func laserToast(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(color)

            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.15))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}
