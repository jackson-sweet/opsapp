// OPS/OPS/DeckBuilder/Views/DeckBuilderView.swift

import SwiftUI
import SwiftData

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
                // 3D mode: title bar is a contained pill, matching the 2D
                // floating-header aesthetic. Previously rendered as a
                // full-width bar bleeding to the screen edges. Bug 0a5f3fe1
                // follow-up.
                titleBar
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
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
                    .padding(.top, OPSStyle.Layout.spacing2)

                DeckScene3DView(drawingData: viewModel.drawingData, controller: scene3DController)
                    .transition(.opacity)

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

                    // Assignment wheel — visible when any element is selected.
                    // Padding bumped from 20 → spacing4 (24pt) so the 56pt circle
                    // doesn't kiss the rounded screen corner on modern iPhones —
                    // canvas behind it ignores horizontal safe area, so the wheel
                    // is the only thing keeping itself off the bezel.
                    if !viewModel.selection.isEmpty {
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

                    // Floating header stack — title chip + AR banner + level bar as a single
                    // consistent column with shared horizontal margins. No overlapping layers.
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        titleBar
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
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

                        // Title pill — sits directly below title bar, left aligned to the same
                        // column so it reads as part of the header stack (no more "floating
                        // over" the title bar via padding tricks).
                        floatingTitlePill

                        // At-a-glance metrics — sqft + linear feet pill floats below
                        // the title badge when the polygon is closed. Moved here from
                        // DeckCanvasView so it doesn't overlap with the titleBar. Bug 11.
                        if viewModel.isClosed, let area = viewModel.totalArea {
                            metricspill(area: area)
                        }

                        // AR accuracy banner — spans full width under title bar
                        arAccuracyBanner

                        // Level tab bar — only when the design actually has
                        // levels. The previous fallback to vertices.count >= 3
                        // showed the bar in single-level mode the moment a
                        // second line was drawn, but the bar's body had nothing
                        // to render (no levels in the ForEach, canConnectLevels
                        // requires 2+ levels), leaving a 44pt cardBackground
                        // rectangle floating below the title — bug 59c76731.
                        if viewModel.isMultiLevel {
                            LevelTabBar(viewModel: viewModel)
                        }

                        Spacer(minLength: 0)
                    }
                    // Floating header sits inside the safe area while the canvas
                    // extends under it. Use spacing4 horizontal so the title pill
                    // has breathing room from the screen edge (previously
                    // spacing3, which read as flush once the canvas went full
                    // bleed) and spacing3 top so it clears the dynamic island /
                    // status bar without being smashed against it. Bug 0a5f3fe1.
                    .padding(.horizontal, OPSStyle.Layout.spacing4)
                    .padding(.top, OPSStyle.Layout.spacing3)
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
        .sheet(isPresented: $viewModel.showingPropertySheet) {
            PropertySheetView(viewModel: viewModel)
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

    // MARK: - Floating Title

    @ViewBuilder
    private var floatingTitlePill: some View {
        HStack {
            Group {
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
                        }
                    }
                } else {
                    Button {
                        editingTitleText = viewModel.deckDesign.title
                        viewModel.isEditingTitle = true
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text(viewModel.deckDesign.title)
                                .font(OPSStyle.Typography.bodyEmphasis)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineLimit(1)
                            Image(systemName: "pencil")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.6))
                        }
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackground.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .shadow(color: Color.black.opacity(0.2), radius: 6, y: 2)
            )

            Spacer()
        }
    }

    private func commitTitleEdit() {
        viewModel.renameDesign(to: editingTitleText)
        viewModel.isEditingTitle = false
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack(spacing: 8) {
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

            // Save status — tracks local persistence, not remote sync
            HStack(spacing: 4) {
                Circle()
                    .fill(viewModel.isLocallySaved ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                    .frame(width: 6, height: 6)
                Text(viewModel.isLocallySaved ? "Saved" : "Saving…")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 2D/3D toggle
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
            .frame(width: 96)
            .disabled(!viewModel.can3DMode)

            // Undo / Redo — edit permission required
            if !viewModel.is3DMode && PermissionStore.shared.can("deck_builder.edit") {
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                        .foregroundColor(viewModel.canUndo ? Color.white : OPSStyle.Colors.tertiaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(!viewModel.canUndo)

                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                        .foregroundColor(viewModel.canRedo ? Color.white : OPSStyle.Colors.tertiaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .disabled(!viewModel.canRedo)
            }

            // Right-most buttons
            if viewModel.is3DMode {
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
            } else if PermissionStore.shared.can("deck_builder.edit") {
                // Import menu — edit permission required
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

            // Always-visible canvas settings — reachable from ANY tool/selection state.
            // Field fix: the toolbar gear was hidden whenever anything was selected.
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

    // MARK: - Metrics Pill (sqft + lin ft, below title when polygon is closed)

    @ViewBuilder
    private func metricspill(area: Double) -> some View {
        HStack {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                Label(DimensionEngine.formatArea(area, system: viewModel.drawingData.config.measurementSystem),
                      systemImage: "square.dashed")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(Color.white)
                if let perimeter = viewModel.totalPerimeter {
                    Label(DimensionEngine.format(perimeter, system: viewModel.drawingData.config.measurementSystem),
                          systemImage: "ruler")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
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
            Spacer()
        }
    }

    // MARK: - AR Accuracy Banner

    @ViewBuilder
    private var arAccuracyBanner: some View {
        let hasAREdges = viewModel.drawingData.edges.contains { $0.accuracyPercent != nil }
        let allVerified = AccuracyModel.allEdgesVerified(viewModel.drawingData)
        let hasAnyARSource = viewModel.drawingData.edges.contains { $0.dimensionSource == .ar }

        if hasAREdges {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.exclamationmarkTriangleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                Text("AR Estimate — refine with tape or laser for material ordering")
                    .font(OPSStyle.Typography.smallCaption)
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.warningStatus.opacity(0.15))
        } else if hasAnyARSource && allVerified && !hideVerifiedBanner {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                Text("All dimensions verified")
                    .font(OPSStyle.Typography.smallCaption)
            }
            .foregroundColor(OPSStyle.Colors.successStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.successStatus.opacity(0.1))
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

