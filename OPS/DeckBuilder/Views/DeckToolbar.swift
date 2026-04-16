// OPS/OPS/DeckBuilder/Views/DeckToolbar.swift

import SwiftUI
import UIKit

struct DeckToolbar: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    private let permissionStore = PermissionStore.shared

    /// True when user has view-only access (no create or edit permission)
    private var isViewOnly: Bool {
        !permissionStore.can("deck_builder.edit") && !permissionStore.can("deck_builder.create")
    }

    /// True when user can generate estimates
    private var canCreate: Bool {
        permissionStore.can("deck_builder.create")
    }

    /// True when user can draw/edit the deck design
    private var canEdit: Bool {
        permissionStore.can("deck_builder.edit")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Context-sensitive action bar — changes based on what's selected
            if canEdit, viewModel.selection.hasVertices {
                vertexTools
            } else if canEdit, viewModel.selection.hasEdges {
                edgeTools
            } else if canEdit, viewModel.selection.selectedFootprint {
                footprintTools
            } else {
                defaultTools
            }
        }
        .background(OPSStyle.Colors.cardBackground)
    }

    // MARK: - Default Tools (no selection)

    private var defaultTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isViewOnly {
                    // View Only badge — no drawing tools
                    Text("VIEW ONLY")
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.secondaryText.opacity(0.12))
                        .cornerRadius(4)
                } else if canEdit {
                    toolButton(icon: "pencil.and.outline", label: "Draw", tool: .draw)
                    toolButton(icon: "rectangle.dashed", label: "Select", tool: .select)
                    toolButton(icon: "lasso", label: "Lasso", tool: .lasso)

                    toolDivider

                    actionButton(icon: "arrow.up.and.down.circle", label: "Height") {
                        viewModel.showingElevationInput = true
                    }

                    if viewModel.canAddLevel {
                        actionButton(icon: "plus.square.on.square", label: "Add Level") {
                            viewModel.addLevel()
                        }
                    }

                    toolDivider

                    actionButton(icon: "trash", label: "Clear", tint: OPSStyle.Colors.errorStatus) {
                        viewModel.showingClearConfirm = true
                    }
                }

                if !isViewOnly {
                    toolDivider
                }

                if canCreate {
                    labeledButton(icon: "doc.text", label: "Estimate",
                                  tint: viewModel.canGenerateEstimate ? Color.white : OPSStyle.Colors.tertiaryText,
                                  enabled: viewModel.canGenerateEstimate) {
                        viewModel.showingEstimatePreview = true
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    }
                }

                labeledButton(icon: "square.and.arrow.up", label: "Share",
                              tint: Color.white, enabled: true) {
                    viewModel.showingShareOptions = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                labeledButton(icon: "photo.on.rectangle.angled", label: "Overlay",
                              tint: viewModel.canShowOverlay ? Color.white : OPSStyle.Colors.tertiaryText,
                              enabled: viewModel.canShowOverlay) {
                    viewModel.showingPhotoSourcePicker = true
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }

                labeledButton(icon: "arkit", label: "AR",
                              tint: viewModel.canViewInAR ? Color.white : OPSStyle.Colors.tertiaryText,
                              enabled: viewModel.canViewInAR) {
                    viewModel.showingARVisualization = true
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }

                if viewModel.isLaserConnected {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .frame(width: 28, height: OPSStyle.Layout.touchTargetMin)
                }

                Divider()
                    .frame(height: 24)
                    .overlay(OPSStyle.Colors.cardBorder)

                Button {
                    viewModel.showingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Vertex Tools (vertex selected)

    private var vertexTools: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            contextLabel("Vertex")

            toolDivider

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "info.circle", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                viewModel.deleteSelectedVertices()
            }

            clearSelectionButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Edge Tools (edge selected)

    private var edgeTools: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                contextLabel("Edge")

                toolDivider

                actionButton(icon: "ruler", label: "Dimension") {
                    viewModel.showingDimensionInput = true
                }

                actionButton(icon: "stairs", label: "Stairs") {
                    viewModel.showingStairConfig = true
                }

                actionButton(icon: "square.grid.3x3", label: "Material") {
                    viewModel.showingMaterialPicker = true
                }

                actionButton(icon: "info.circle", label: "Properties") {
                    viewModel.showingPropertySheet = true
                }

                Spacer()

                actionButton(icon: "trash", label: "Delete", tint: OPSStyle.Colors.errorStatus) {
                    viewModel.deleteSelectedEdges()
                }

                clearSelectionButton
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Footprint Tools (area selected)

    private var footprintTools: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            contextLabel("Surface")

            toolDivider

            actionButton(icon: "square.grid.3x3", label: "Material") {
                viewModel.showingMaterialPicker = true
            }

            actionButton(icon: "arrow.up.and.down.circle", label: "Elevation") {
                viewModel.showingElevationInput = true
            }

            actionButton(icon: "info.circle", label: "Properties") {
                viewModel.showingPropertySheet = true
            }

            Spacer()

            clearSelectionButton
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    // MARK: - Context Label

    private func contextLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(OPSStyle.Typography.miniLabel)
            .foregroundColor(OPSStyle.Colors.primaryAccent)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(OPSStyle.Colors.primaryAccent.opacity(0.12))
            .cornerRadius(4)
    }

    // MARK: - Clear Selection Button

    private var clearSelectionButton: some View {
        Button {
            viewModel.selection.clear()
            viewModel.editingEdgeId = nil
            viewModel.editingVertexId = nil
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
        }
    }

    // MARK: - Drawing Tool Button

    private func toolButton(icon: String, label: String, tool: DrawingTool) -> some View {
        let isActive = viewModel.activeTool == tool
        return Button {
            viewModel.activeTool = tool
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : Color.white)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            .background(isActive ? OPSStyle.Colors.primaryAccent.opacity(0.12) : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }

    // MARK: - Context Action Button

    private func actionButton(
        icon: String, label: String,
        tint: Color = Color.white,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: {
            action()
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(tint)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
        }
    }

    // MARK: - Labeled Feature Button

    private func labeledButton(
        icon: String, label: String,
        tint: Color, enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                    .foregroundColor(tint)
                Text(label)
                    .font(OPSStyle.Typography.miniLabel)
                    .foregroundColor(tint == Color.white ? OPSStyle.Colors.secondaryText : tint)
            }
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
        }
        .disabled(!enabled)
    }

    // MARK: - Helpers

    private var toolDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.separator)
            .frame(width: 1, height: 32)
    }
}
