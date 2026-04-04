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
            arAccuracyBanner

            // Canvas + Assignment Wheel overlay
            ZStack(alignment: .bottomTrailing) {
                DeckCanvasView(viewModel: viewModel)

                // Assignment wheel — visible when any element is selected
                if !viewModel.selection.isEmpty {
                    AssignmentWheelView(viewModel: viewModel)
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            // Toolbar
            DeckToolbar(viewModel: viewModel)
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

            // Title
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

            Spacer()

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

                Button(action: {}) {
                    Label("Connect Laser Meter", systemImage: "antenna.radiowaves.left.and.right")
                }
                .disabled(true)
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

            // Elevation entry
            Button {
                viewModel.showingElevationInput = true
            } label: {
                Image(systemName: "arrow.up.and.down.circle")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
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
}
