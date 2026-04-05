// OPS/OPS/DeckBuilder/Views/DeckBuilderView.swift

import SwiftUI
import SwiftData

struct DeckBuilderView: View {
    @StateObject private var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var showingTemplatePicker = false
    @State private var showingSketchCapture = false
    @State private var showingARPerimeter = false
    @State private var hideVerifiedBanner = false
    @State private var showingEstimateDetail = false
    @StateObject private var scene3DController = Scene3DController()
    @State private var showing3DScreenshotShare = false
    @State private var screenshotImage: UIImage?
    @StateObject private var estimateVM = EstimateViewModel()

    let projectId: String?
    let companyId: String

    init(deckDesign: DeckDesign, modelContext: ModelContext) {
        self._viewModel = StateObject(wrappedValue: DeckBuilderViewModel(
            deckDesign: deckDesign,
            modelContext: modelContext
        ))
        self.projectId = deckDesign.projectId
        self.companyId = deckDesign.companyId
    }

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.is3DMode {
                // 3D mode: title bar is solid (not floating)
                titleBar
                    .background(OPSStyle.Colors.cardBackground)

                DeckScene3DView(drawingData: viewModel.drawingData, controller: scene3DController)
                    .transition(.opacity)

                CameraPresetBar { preset in
                    scene3DController.setCameraPreset(preset)
                }
                .transition(.opacity)
            } else {
                // 2D mode: canvas fills screen, title bar floats on top
                ZStack(alignment: .top) {
                    // Full-bleed canvas
                    ZStack(alignment: .bottomTrailing) {
                        DeckCanvasView(viewModel: viewModel)

                    // Assignment wheel — visible when any element is selected
                    if !viewModel.selection.isEmpty {
                        AssignmentWheelView(viewModel: viewModel)
                            .padding(.trailing, 20)
                            .padding(.bottom, 20)
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showMeasurementToast)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showLaserErrorToast)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.showDisconnectToast)
                    } // end canvas ZStack (bottomTrailing)

                    // Floating title bar — glass pill over the canvas
                    VStack(spacing: 0) {
                        titleBar
                            .background(.ultraThinMaterial)

                        // AR accuracy banner
                        arAccuracyBanner

                        // Level tab bar
                        if viewModel.isMultiLevel || viewModel.drawingData.vertices.count >= 3 {
                            LevelTabBar(viewModel: viewModel)
                        }

                        Spacer()
                    }
                    .allowsHitTesting(true)
                } // end ZStack (top-aligned, floating title over canvas)

                // Toolbar — below the canvas
                DeckToolbar(viewModel: viewModel)
            }
        }
        .background(OPSStyle.Colors.background)
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
        // Estimate created toast — tappable to navigate
        .overlay(alignment: .bottom) {
            if viewModel.estimateCreated, let number = viewModel.createdEstimateNumber {
                Button {
                    viewModel.estimateCreated = false
                    estimateVM.setup(companyId: companyId)
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
        .statusBarHidden(true)
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

            // Title + save status — takes all available space
            VStack(alignment: .leading, spacing: 1) {
                Text(viewModel.deckDesign.title)
                    .font(OPSStyle.Typography.bodyEmphasis)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(viewModel.deckDesign.needsSync ? "Unsaved changes" : "Saved")
                    .font(OPSStyle.Typography.microLabel)
                    .foregroundColor(viewModel.deckDesign.needsSync ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 2D/3D toggle
            Picker("View Mode", selection: Binding(
                get: { viewModel.is3DMode },
                set: { newValue in
                    withAnimation(OPSStyle.Animation.standard) {
                        viewModel.is3DMode = newValue
                    }
                }
            )) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "cube").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .disabled(!viewModel.can3DMode)

            // Undo / Redo
            if !viewModel.is3DMode {
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
            } else {
                // Import menu
                Menu {
                    Button { showingTemplatePicker = true } label: {
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
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .padding(.vertical, OPSStyle.Layout.spacing1)
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
