// OPS/OPS/DeckBuilder/Views/DeckBuilderView.swift

import SwiftUI
import SwiftData

struct DeckBuilderView: View {
    @StateObject private var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false

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

            // Import menu (stubs for future methods)
            Menu {
                Button(action: {}) {
                    Label("From Template", systemImage: "square.grid.2x2")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Scan Paper Sketch", systemImage: "doc.text.viewfinder")
                }
                .disabled(true)

                Button(action: {}) {
                    Label("Walk Perimeter (AR)", systemImage: "camera.viewfinder")
                }
                .disabled(true)

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
}
