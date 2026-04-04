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
    @State private var scene3DCoordinator: DeckScene3DView.Coordinator?
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
            // Title bar
            titleBar

            // AR accuracy banner
            if !viewModel.is3DMode {
                arAccuracyBanner
            }

            if viewModel.is3DMode {
                // 3D perspective view
                DeckScene3DView(drawingData: viewModel.drawingData)
                    .onAppear { scene3DCoordinator = DeckScene3DView.Coordinator() }

                CameraPresetBar { preset in
                    scene3DCoordinator?.setCameraPreset(preset, drawingData: viewModel.drawingData)
                }
            } else {
                // Level tab bar (multi-level mode)
                if viewModel.isMultiLevel || viewModel.drawingData.vertices.count >= 3 {
                    LevelTabBar(viewModel: viewModel)
                }

                // Canvas + Assignment Wheel overlay + Laser toast
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
                }

                // Toolbar (hidden in 3D mode)
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
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.successStatus)

                        Text("Estimate created \u{2014} \(number)")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
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
        .statusBarHidden(true)
    }

    // MARK: - Title Bar

    private var titleBar: some View {
        HStack {
            // Close button
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
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .disabled(isSaving)

            Spacer()

            // Title + 2D/3D Toggle
            VStack(spacing: 2) {
                Text(viewModel.deckDesign.title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.white)

                if viewModel.deckDesign.needsSync {
                    Text("Unsaved changes")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                } else {
                    Text("Saved")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            // 2D/3D toggle
            Picker("View Mode", selection: $viewModel.is3DMode) {
                Image(systemName: "square.grid.2x2").tag(false)
                Image(systemName: "cube").tag(true)
            }
            .pickerStyle(.segmented)
            .frame(width: 80)
            .disabled(!viewModel.can3DMode)

            Spacer()

            if viewModel.is3DMode {
                // Screenshot button in 3D mode
                Button {
                    if let screenshot = scene3DCoordinator?.captureScreenshot() {
                        screenshotImage = screenshot
                        showing3DScreenshotShare = true
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            } else {
                // Template picker button
                Button {
                    showingTemplatePicker = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }

                // Import menu (stubs for future methods)
                Menu {
                    Button(action: {}) {
                        Label("From Template", systemImage: "square.grid.2x2")
                    }
                    .disabled(true)

                    Button {
                        showingSketchCapture = true
                    } label: {
                        Label("Scan Paper Sketch", systemImage: "doc.text.viewfinder")
                    }

                    Button {
                        showingARPerimeter = true
                    } label: {
                        Label("Walk Perimeter (AR)", systemImage: "camera.viewfinder")
                    }

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
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }

                // Dimension entry for selected edge
                if viewModel.editingEdgeId != nil {
                    Button {
                        viewModel.showingDimensionInput = true
                    } label: {
                        Image(systemName: "ruler")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                    }
                }
            }

            // Elevation entry
            if !viewModel.is3DMode {
                Button {
                    viewModel.showingElevationInput = true
                } label: {
                    Image(systemName: "arrow.up.and.down.circle")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - AR Accuracy Banner

    @ViewBuilder
    private var arAccuracyBanner: some View {
        let hasAREdges = viewModel.drawingData.edges.contains { $0.accuracyPercent != nil }
        let allVerified = AccuracyModel.allEdgesVerified(viewModel.drawingData)
        let hasAnyARSource = viewModel.drawingData.edges.contains { $0.dimensionSource == .ar }

        if hasAREdges {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("AR Estimate — refine with tape or laser for material ordering")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(OPSStyle.Colors.warningStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(OPSStyle.Colors.warningStatus.opacity(0.15))
        } else if hasAnyARSource && allVerified && !hideVerifiedBanner {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                Text("All dimensions verified")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(OPSStyle.Colors.successStatus)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
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
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(color)

            Text(text)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(color.opacity(0.15))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}
