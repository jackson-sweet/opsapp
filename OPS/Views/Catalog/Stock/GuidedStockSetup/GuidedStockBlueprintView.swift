import SwiftUI

// MARK: - GuidedStockBlueprintView
//
// BLUEPRINT stage — pre-commit review phase of the wizard (spec §7.3).
// Renders a scrollable, per-family summary. Tapping a family card routes back to
// the STRUCTURE stage so the operator can refine before committing.
//
// The BUILD IT → CTA is owned by GuidedStockSetupFlow's bottom bar.
// This view renders CARD CONTENT only — no commit trigger lives here.

struct GuidedStockBlueprintView: View {

    @ObservedObject var model: GuidedStockSetupModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        Group {
            if model.groups.isEmpty {
                emptyState
            } else {
                scrollContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(OPSStyle.Typography.dataValueLg)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("// NOTHING TO BUILD YET")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing4)
    }

    // MARK: - Scroll content

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: OPSStyle.Layout.spacing3) {
                // Page header
                pageHeader

                // Per-family cards
                ForEach(model.groups) { group in
                    BlueprintFamilyCard(
                        group: group,
                        capturedItems: model.capturedItems,
                        onEdit: { routeToStructure() }
                    )
                }

                // Bottom spacer so last card clears the CTA bar
                Color.clear.frame(height: OPSStyle.Layout.spacing5)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
        }
    }

    // MARK: - Page header

    private var pageHeader: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("YOUR BLUEPRINT")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Here's how we'll set it up. Tap anything to change it.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, OPSStyle.Layout.spacing1)
    }

    // MARK: - Edit routing

    private func routeToStructure() {
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
        withAnimation(reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page) {
            model.stage = .structure
        }
    }
}

// MARK: - BlueprintFamilyCard

private struct BlueprintFamilyCard: View {

    let group: GuidedStructuredGroup
    let capturedItems: [GuidedCapturedItem]
    let onEdit: () -> Void

    @State private var isPressed: Bool = false

    var body: some View {
        Button(action: onEdit) {
            cardContent
        }
        .buttonStyle(BlueprintCardButtonStyle())
        .accessibilityLabel("\(group.familyName) — tap to edit")
        .accessibilityHint("Returns to the structure step")
    }

    // MARK: - Card content

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Family name + edit indicator
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                Text(group.familyName)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "pencil")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            // Separator
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: OPSStyle.Layout.Border.standard)

            // Data rows
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                structureLine
                stockLine
                if group.product.sellMode != nil {
                    productLine
                }
            }

            // Inline warnings (non-blocking)
            let warnings = warningMessages
            if !warnings.isEmpty {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    ForEach(warnings, id: \.self) { warning in
                        Text(warning)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.warningText)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Structure line

    @ViewBuilder
    private var structureLine: some View {
        if group.isSingleItem {
            blueprintRow(
                label: "// STRUCTURE",
                value: "one item",
                valueSuffix: nil
            )
        } else {
            let axes = group.attributes.map(\.name).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let count = GuidedStockDraftBuilder.variantCount(for: group)
            if axes.isEmpty {
                blueprintRow(label: "// STRUCTURE", value: "—", valueSuffix: nil)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                    Text("// STRUCTURE")
                        .font(OPSStyle.Typography.panelTitle)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing1) {
                        Text(axes.joined(separator: " × "))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("→")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("\(count)")
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .monospacedDigit()
                        Text("versions")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
        }
    }

    // MARK: - Stock line

    @ViewBuilder
    private var stockLine: some View {
        let allDrafts = group.stockEntries.flatMap { entry in
            GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)
        }

        if allDrafts.isEmpty {
            blueprintRow(label: "// STOCK", value: "—", valueSuffix: nil, valueColor: OPSStyle.Colors.tertiaryText)
        } else {
            let stockSummary = stockSummaryText(drafts: allDrafts)
            blueprintRow(label: "// STOCK", value: stockSummary, valueSuffix: nil)
        }
    }

    private func stockSummaryText(drafts: [CatalogSetupStockUnitDraft]) -> String {
        guard let measurement = group.measurement else {
            return CatalogSetupWorkflow.mirroredQuantityLabel(for: drafts)
        }

        switch measurement {
        case .piece:
            let eachCount = drafts.filter { $0.unitKind == .each }.reduce(0.0) { $0 + ($1.quantityValue ?? 0) }
            if eachCount == 0 { return "—" }
            let formatted = eachCount.formatted(.number.precision(.fractionLength(0...2)))
            return "\(formatted) on hand"

        case .length, .area:
            let rollCount = drafts.filter { $0.unitKind == .roll }.count
            let offcutCount = drafts.filter { $0.unitKind == .offcut }.count

            var parts: [String] = []
            if rollCount > 0 {
                parts.append("\(rollCount) roll\(rollCount == 1 ? "" : "s")")
            }
            if offcutCount > 0 {
                parts.append("\(offcutCount) offcut\(offcutCount == 1 ? "" : "s")")
            }

            if parts.isEmpty {
                return CatalogSetupWorkflow.mirroredQuantityLabel(for: drafts)
            }

            let unitLabel = CatalogSetupWorkflow.mirroredQuantityLabel(for: drafts)
            let breakdown = parts.joined(separator: " + ")
            if unitLabel.isEmpty || unitLabel == "0" {
                return breakdown
            }
            return "\(unitLabel) · \(breakdown)"
        }
    }

    // MARK: - Product line

    @ViewBuilder
    private var productLine: some View {
        if let sellMode = group.product.sellMode {
            productLineContent(sellMode: sellMode)
        }
    }

    @ViewBuilder
    private func productLineContent(sellMode: GuidedSellMode) -> some View {
        switch sellMode {
        case .onItsOwn:
            blueprintRow(
                label: "// PRODUCT",
                value: "Sold as a product",
                valueSuffix: (group.product.sellingUsesStock == true) ? " · consumes its own stock" : nil
            )

        case .inPackage:
            blueprintRow(
                label: "// PACKAGE",
                value: packageValueString(children: group.product.bundleChildren),
                valueSuffix: packageSuggestedSuffix(children: group.product.bundleChildren)
            )

        case .both:
            blueprintRow(
                label: "// PRODUCT",
                value: bothValueString(children: group.product.bundleChildren),
                valueSuffix: (group.product.sellingUsesStock == true) ? " + consumes its own stock" : nil
            )
        }
    }

    private func packageValueString(children: [GuidedBundleChild]) -> String {
        if children.isEmpty { return "—" }
        return "\(children.count) item\(children.count == 1 ? "" : "s")"
    }

    private func packageSuggestedSuffix(children: [GuidedBundleChild]) -> String? {
        let suggested = children.filter { !$0.isRequired }.count
        return suggested > 0 ? " (\(suggested) suggested)" : nil
    }

    private func bothValueString(children: [GuidedBundleChild]) -> String {
        let detail: String
        if children.isEmpty {
            detail = "no items"
        } else {
            let suggested = children.filter { !$0.isRequired }.count
            detail = "\(children.count) item\(children.count == 1 ? "" : "s")"
                + (suggested > 0 ? " (\(suggested) suggested)" : "")
        }
        return "Sold on its own · package \(detail)"
    }

    // MARK: - Warnings

    private var warningMessages: [String] {
        var warnings: [String] = []

        // No stock counted for any entry
        let allDrafts = group.stockEntries.flatMap { entry in
            GuidedStockDraftBuilder.stockUnitDrafts(for: group, entry: entry)
        }
        if allDrafts.isEmpty {
            warnings.append("// no stock counted yet")
        }

        // Package/bundle has no children
        if let sellMode = group.product.sellMode {
            if (sellMode == .inPackage || sellMode == .both) && group.product.bundleChildren.isEmpty {
                warnings.append("// package has no items")
            }
        }

        return warnings
    }

    // MARK: - Helpers

    private func resolvedChildNames(_ children: [GuidedBundleChild]) -> [String] {
        children.compactMap { child in
            capturedItems.first(where: { $0.id == child.capturedItemId })?.name
        }
    }

    @ViewBuilder
    private func blueprintRow(
        label: String,
        value: String,
        valueSuffix: String?,
        valueColor: Color = OPSStyle.Colors.secondaryText
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(valueColor)
                if let suffix = valueSuffix {
                    Text(suffix)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .multilineTextAlignment(.trailing)
        }
    }
}

// MARK: - BlueprintCardButtonStyle

private struct BlueprintCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(OPSStyle.Animation.hover, value: configuration.isPressed)
    }
}
