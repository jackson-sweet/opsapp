// OPS/OPS/DeckBuilder/Views/ScaleConflictSheet.swift

import SwiftUI

/// Bottom sheet shown when the scan pipeline detects disagreement between
/// handwritten dimension annotations and the proportions implied by the drawn sketch.
/// Presents each conflict and lets the user choose a single resolution strategy.
struct ScaleConflictSheet: View {
    let conflicts: [ScaleConflict]
    let onResolve: (ConflictResolution) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            dragIndicator
            scrollableContent
        }
        .background(OPSStyle.Colors.background)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Drag Indicator

    private var dragIndicator: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(OPSStyle.Colors.tertiaryText)
            .frame(width: 36, height: 4)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    // MARK: - Scrollable Content

    private var scrollableContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                header
                conflictList
                actionButtons
            }
            .padding(.horizontal, OPSStyle.Layout.spacing4)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Dimension Mismatch")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Some handwritten dimensions don't match the drawn proportions.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: - Conflict List

    private var conflictList: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(Array(conflicts.enumerated()), id: \.element.segmentId) { _, conflict in
                conflictRow(conflict)
            }
        }
    }

    private func conflictRow(_ conflict: ScaleConflict) -> some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack {
                // Written (annotated) value
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("Written")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(DimensionEngine.formatImperial(conflict.annotatedInches))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }

                Spacer()

                // Difference badge
                Text("\(Int(conflict.percentDifference.rounded()))% off")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(OPSStyle.Colors.warningStatus.opacity(0.12))
                    .cornerRadius(OPSStyle.Layout.smallCornerRadius)

                Spacer()

                // Drawn (scale-derived) value
                VStack(alignment: .trailing, spacing: OPSStyle.Layout.spacing1) {
                    Text("Drawn")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text(DimensionEngine.formatImperial(conflict.scaleDerivedInches))
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            // Primary — use written annotations
            Button {
                resolveAndDismiss(.useAnnotations)
            } label: {
                Text("Use Written Dimensions")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.buttonText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }

            // Secondary — use drawing proportions
            Button {
                resolveAndDismiss(.useScale)
            } label: {
                Text("Use Drawing Proportions")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                    .background(Color.clear)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.buttonBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }

            // Tertiary — enter all manually
            Button {
                resolveAndDismiss(.enterManually)
            } label: {
                Text("Enter All Manually")
                    .font(OPSStyle.Typography.button)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            }
        }
    }

    // MARK: - Resolution

    private func resolveAndDismiss(_ resolution: ConflictResolution) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        onResolve(resolution)
        dismiss()
    }
}
