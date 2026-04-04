// OPS/OPS/DeckBuilder/Views/DeckToolbar.swift

import SwiftUI
import UIKit

struct DeckToolbar: View {
    @ObservedObject var viewModel: DeckBuilderViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Drawing tools
            toolButton(
                icon: "pencil.and.outline",
                label: "Draw",
                tool: .draw
            )

            toolButton(
                icon: "rectangle.dashed",
                label: "Select",
                tool: .select
            )

            toolButton(
                icon: "lasso",
                label: "Lasso",
                tool: .lasso
            )

            Spacer()

            // Generate Estimate
            Button {
                viewModel.showingEstimatePreview = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(viewModel.canGenerateEstimate ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                    Text("Estimate")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(viewModel.canGenerateEstimate ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }
            .disabled(!viewModel.canGenerateEstimate)

            // Share
            Button {
                viewModel.showingShareOptions = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(Color.white)

                    Text("Share")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }

            // Photo Overlay
            Button {
                viewModel.showingPhotoSourcePicker = true
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(viewModel.canShowOverlay ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)

                    Text("Overlay")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(viewModel.canShowOverlay ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }
            .disabled(!viewModel.canShowOverlay)

            // View in AR
            Button {
                viewModel.showingARVisualization = true
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "arkit")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(viewModel.canViewInAR ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)

                    Text("AR")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(viewModel.canViewInAR ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                }
                .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            }
            .disabled(!viewModel.canViewInAR)

            // BLE laser indicator (only when connected)
            if viewModel.isLaserConnected {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .frame(width: 28, height: OPSStyle.Layout.touchTargetMin)
            }

            // Undo / Redo
            Button {
                viewModel.undo()
            } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(viewModel.canUndo ? Color.white : OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!viewModel.canUndo)

            Button {
                viewModel.redo()
            } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(viewModel.canRedo ? Color.white : OPSStyle.Colors.secondaryText)
                    .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
            }
            .disabled(!viewModel.canRedo)

            // Delete (when selection active)
            if !viewModel.selection.isEmpty {
                Button {
                    if viewModel.selection.hasEdges {
                        viewModel.deleteSelectedEdges()
                    } else if viewModel.selection.hasVertices {
                        viewModel.deleteSelectedVertices()
                    }
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackground)
    }

    @ViewBuilder
    private func toolButton(icon: String, label: String, tool: DrawingTool) -> some View {
        let isActive = viewModel.activeTool == tool

        Button {
            viewModel.activeTool = tool
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: isActive ? .bold : .medium))
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : Color.white)

                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(isActive ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
            }
            .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetStandard)
            .background(isActive ? OPSStyle.Colors.primaryAccent.opacity(0.15) : Color.clear)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}
