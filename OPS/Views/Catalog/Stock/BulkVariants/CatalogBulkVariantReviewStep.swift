//
//  CatalogBulkVariantReviewStep.swift
//  OPS
//

import SwiftUI

struct CatalogBulkVariantReviewStep: View {
    @ObservedObject var model: CatalogBulkVariantExpansionModel
    let preview: CatalogBulkVariantExpansionPreview
    let isOnline: Bool

    @State private var expandedFamilyIds: Set<String> = []

    private var skippedCount: Int {
        preview.familyPlans.reduce(0) { $0 + $1.skippedExistingCombinationCount }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("CHECK THE IMPACT")
                    .font(OPSStyle.Typography.panelTitle)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("OPS will apply this as one catalog update. Nothing saves until you add the variants.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            impactSummary

            if !preview.blockers.isEmpty {
                blockerPanel
            }

            if let errorMessage = model.errorMessage {
                errorPanel(errorMessage)
            }

            rulePanel

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text("AFFECTED FAMILIES")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)

                ForEach(preview.familyPlans, id: \.familyId) { plan in
                    familyRow(plan)
                }
            }

            if !isOnline {
                Text("Connect to add these variants.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.tanFillM)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
                    .overlay {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                            .stroke(OPSStyle.Colors.tanLineM, lineWidth: OPSStyle.Layout.Border.standard)
                    }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var impactSummary: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                metric(value: preview.familyCount, label: "FAMILIES")
                metric(value: preview.existingVariantAssignmentCount, label: "LABELED")
                metric(value: preview.newVariantCount, label: "NEW")
            }
            if skippedCount > 0 {
                HStack {
                    Text("\(skippedCount) combinations already exist and will be skipped.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.text3)
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing1)
            }
        }
    }

    private func metric(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("\(value)")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.text)
                .monospacedDigit()
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(value) \(label.lowercased())")
    }

    private var blockerPanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CHECK BEFORE ADDING")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.roseTextM)
            ForEach(preview.blockers) { blocker in
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.exclamationmarkCircleFill)
                        .foregroundColor(OPSStyle.Colors.roseTextM)
                    Text(blocker.message)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.roseTextM)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.roseFillM)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.roseLineM, lineWidth: OPSStyle.Layout.Border.standard)
        }
    }

    private func errorPanel(_ message: String) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.exclamationmarkCircleFill)
                .foregroundColor(OPSStyle.Colors.roseTextM)
            Text(message)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.roseFillM)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.roseLineM, lineWidth: OPSStyle.Layout.Border.standard)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Could not add variants. \(message)")
    }

    private var rulePanel: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("STOCK RULES")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            Text("Existing stock, SKUs, and settings stay unchanged. New variants start at zero stock with blank SKUs.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassSurface()
    }

    private func familyRow(_ plan: CatalogBulkFamilyExpansionPlan) -> some View {
        let isExpanded = expandedFamilyIds.contains(plan.familyId)
        let beforeCount = plan.source.variants.count
        let afterCount = beforeCount + plan.newVariants.count
        let sourceCount = Set(plan.newVariants.map(\.sourceVariantId)).count

        return VStack(spacing: 0) {
            Button {
                if isExpanded {
                    expandedFamilyIds.remove(plan.familyId)
                } else {
                    expandedFamilyIds.insert(plan.familyId)
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(plan.familyName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(beforeCount) → \(afterCount) VARIANTS")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .monospacedDigit()
                    }
                    Image(systemName: isExpanded ? OPSStyle.Icons.chevronUp : OPSStyle.Icons.chevronDown)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetLarge)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(plan.familyName), \(beforeCount) becomes \(afterCount) variants")
            .accessibilityHint(isExpanded ? "Collapse details" : "Expand details")

            if isExpanded {
                Divider()
                    .overlay(OPSStyle.Colors.line)
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    detailRow(label: "OPTION", value: preview.axisName)
                    detailRow(label: "EXISTING", value: preview.existingValue)
                    detailRow(label: "ADDING", value: preview.newValues.joined(separator: " · "))
                    detailRow(label: "SOURCES", value: "\(sourceCount) variants")
                    if plan.skippedExistingCombinationCount > 0 {
                        detailRow(
                            label: "SKIPPED",
                            value: "\(plan.skippedExistingCombinationCount) already present"
                        )
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
                .transition(.opacity)
            }
        }
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
        .overlay {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        }
        .animation(OPSStyle.Animation.panel, value: isExpanded)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(minWidth: OPSStyle.Layout.touchTargetLarge, alignment: .leading)
            Text(value)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
