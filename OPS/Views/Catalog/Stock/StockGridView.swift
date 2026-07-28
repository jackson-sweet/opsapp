//
//  StockGridView.swift
//  OPS
//
//  GRID is the family-finder mode. It shows one tile per family, uses the
//  family image when available, and drills into variants only when needed.
//  LIST remains the all-variant adjustment register; TABLE remains comparison.
//

import SwiftUI

struct StockFamilyGridGroup: Identifiable {
    let id: String
    let family: CatalogItem
    let rows: [EnrichedVariantRow]

    var criticalCount: Int { rows.filter { $0.thresholdStatus == .critical }.count }
    var warningCount: Int { rows.filter { $0.thresholdStatus == .warning }.count }
    var lowCount: Int { criticalCount + warningCount }
}

enum StockGridRoute: Equatable {
    case adjust(EnrichedVariantRow)
    case detail(EnrichedVariantRow)
}

struct StockGridRouteHandoff {
    private(set) var pending: StockGridRoute?

    mutating func stage(_ route: StockGridRoute) {
        pending = route
    }

    mutating func takeAfterDismissal() -> StockGridRoute? {
        defer { pending = nil }
        return pending
    }
}

struct StockGridView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let rows: [EnrichedVariantRow]
    var onTap: ((EnrichedVariantRow) -> Void)? = nil
    var onOpenDetail: ((EnrichedVariantRow) -> Void)? = nil

    @AppStorage("catalog.stock.cardScale") private var cardScale: Double = 1.0
    @State private var gestureStartScale: Double = 1.0
    @State private var selectedFamily: StockFamilyGridGroup?
    @State private var routeHandoff = StockGridRouteHandoff()

    private var layout: StockGridLayout {
        if dynamicTypeSize.isAccessibilitySize {
            return StockGridLayout(columnCount: 1, showsSecondaryMetadata: true)
        }
        return StockGridDensity.layout(for: cardScale)
    }

    private var densityAccessibilityValue: String {
        if dynamicTypeSize.isAccessibilitySize {
            return "Expanded, 1 column"
        }
        return StockGridDensity.accessibilityValue(for: cardScale)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            count: layout.columnCount
        )
    }

    private var families: [StockFamilyGridGroup] {
        var rowsByFamily: [String: [EnrichedVariantRow]] = [:]
        var orderedFamilyIds: [String] = []

        for row in rows {
            if rowsByFamily[row.family.id] == nil {
                orderedFamilyIds.append(row.family.id)
            }
            rowsByFamily[row.family.id, default: []].append(row)
        }

        return orderedFamilyIds.compactMap { familyId in
            guard let familyRows = rowsByFamily[familyId], let firstRow = familyRows.first else { return nil }
            return StockFamilyGridGroup(id: familyId, family: firstRow.family, rows: familyRows)
        }
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: OPSStyle.Layout.spacing2) {
                ForEach(families) { group in
                    Button {
                        open(group)
                    } label: {
                        StockFamilyTile(group: group, layout: layout)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("catalog.stock.family.\(group.id)")
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing1)

            Color.clear.frame(height: OPSStyle.Layout.spacing5)
        }
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    guard !dynamicTypeSize.isAccessibilitySize else { return }
                    cardScale = StockGridDensity.clampedScale(gestureStartScale * Double(value))
                }
                .onEnded { _ in
                    guard !dynamicTypeSize.isAccessibilitySize else { return }
                    gestureStartScale = cardScale
                }
        )
        .onAppear {
            cardScale = StockGridDensity.clampedScale(cardScale)
            gestureStartScale = cardScale
        }
        .modifier(
            StockGridDensityAccessibilityModifier(
                isAccessibilitySize: dynamicTypeSize.isAccessibilitySize,
                value: densityAccessibilityValue,
                onAdjust: adjustDensity
            )
        )
        .sheet(item: $selectedFamily, onDismiss: deliverPendingRoute) { group in
            StockFamilyVariantsSheet(
                group: group,
                onSelect: { row in
                    routeHandoff.stage(.adjust(row))
                    selectedFamily = nil
                },
                onOpenDetail: { row in
                    routeHandoff.stage(.detail(row))
                    selectedFamily = nil
                }
            )
        }
    }

    private func open(_ group: StockFamilyGridGroup) {
        if let onlyRow = group.rows.first, group.rows.count == 1 {
            onTap?(onlyRow)
        } else {
            selectedFamily = group
        }
    }

    private func adjustDensity(_ direction: AccessibilityAdjustmentDirection) {
        guard !dynamicTypeSize.isAccessibilitySize else { return }
        switch direction {
        case .increment:
            cardScale = StockGridDensity.adjustedScale(from: cardScale, towardLargerCards: true)
        case .decrement:
            cardScale = StockGridDensity.adjustedScale(from: cardScale, towardLargerCards: false)
        @unknown default:
            return
        }
        gestureStartScale = cardScale
    }

    private func deliverPendingRoute() {
        guard let route = routeHandoff.takeAfterDismissal() else { return }
        switch route {
        case .adjust(let row):
            onTap?(row)
        case .detail(let row):
            onOpenDetail?(row)
        }
    }
}

private struct StockGridDensityAccessibilityModifier: ViewModifier {
    let isAccessibilitySize: Bool
    let value: String
    let onAdjust: (AccessibilityAdjustmentDirection) -> Void

    @ViewBuilder
    func body(content: Content) -> some View {
        if isAccessibilitySize {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Stock grid")
                .accessibilityValue(value)
                .accessibilityHint("Accessibility text uses one expanded column.")
        } else {
            content
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Stock grid tile size")
                .accessibilityValue(value)
                .accessibilityHint("Pinch to resize, or swipe up and down to change column count.")
                .accessibilityAdjustableAction(onAdjust)
        }
    }
}

private struct StockFamilyTile: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let group: StockFamilyGridGroup
    let layout: StockGridLayout

    private var singleQuantity: String? {
        guard group.rows.count == 1, let row = group.rows.first else { return nil }
        let quantity = StockNumberFormatter.quantity(row.variant.quantity)
        guard let unit = row.unit?.display else { return quantity }
        return "\(quantity) \(unit)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                if layout.showsSecondaryMetadata,
                   let imageUrl = group.family.imageUrl,
                   let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            imageFallback
                        }
                    }
                    .frame(
                        width: OPSStyle.Layout.touchTargetMin,
                        height: OPSStyle.Layout.touchTargetMin
                    )
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius))
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(group.family.name)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        .padding(.trailing, group.lowCount > 0 ? OPSStyle.Layout.spacing3 : 0)

                    Text(group.rows.count == 1 ? "1 VARIANT" : "\(group.rows.count) VARIANTS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)

                    if group.criticalCount > 0 {
                        Text("\(group.criticalCount) CRITICAL")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.roseTextM)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    }
                    if group.warningCount > 0 {
                        Text("\(group.warningCount) LOW")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tanTextM)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    }
                }
                .layoutPriority(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if layout.showsSecondaryMetadata {
                Spacer(minLength: 0)
                HStack(alignment: .lastTextBaseline, spacing: OPSStyle.Layout.spacing1) {
                    if let singleQuantity {
                        Text(singleQuantity)
                            .font(OPSStyle.Typography.dataValue)
                            .foregroundColor(group.rows.first?.thresholdStatus.textColor ?? OPSStyle.Colors.text)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    } else if group.criticalCount > 0 {
                        Text("CRITICAL")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.roseTextM)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    } else if group.warningCount > 0 {
                        Text("LOW")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tanTextM)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    } else {
                        Text("ALL CLEAR")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                    }
                    Spacer()
                    Image(systemName: group.rows.count == 1 ? OPSStyle.Icons.adjust : OPSStyle.Icons.forward)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .frame(
            maxWidth: .infinity,
            minHeight: layout.showsSecondaryMetadata
                ? OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5
                : OPSStyle.Layout.touchTargetLarge + OPSStyle.Layout.spacing2,
            alignment: .topLeading
        )
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(
                    group.criticalCount > 0 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.nestedBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .overlay(alignment: .topTrailing) {
            if group.lowCount > 0 {
                Circle()
                    .fill(group.criticalCount > 0 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                    .frame(
                        width: OPSStyle.Layout.Indicator.dotMD,
                        height: OPSStyle.Layout.Indicator.dotMD
                    )
                    .padding(OPSStyle.Layout.spacing2_5)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var imageFallback: some View {
        ZStack {
            OPSStyle.Colors.surfaceActive
            Image(systemName: OPSStyle.Icons.inventory)
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }

    private var accessibilityLabel: String {
        var parts = [group.family.name, "\(group.rows.count) variants"]
        if group.criticalCount > 0 { parts.append("\(group.criticalCount) critical") }
        if group.warningCount > 0 { parts.append("\(group.warningCount) low") }
        if let singleQuantity { parts.append(singleQuantity) }
        return parts.joined(separator: ", ")
    }
}

private struct StockFamilyVariantsSheet: View {
    let group: StockFamilyGridGroup
    let onSelect: (EnrichedVariantRow) -> Void
    let onOpenDetail: (EnrichedVariantRow) -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// \(group.family.name.uppercased())")
                    .font(OPSStyle.Typography.section)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(group.rows.count) VARIANTS")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                        Button { onSelect(row) } label: {
                            StockListRow(row: row)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button { openDetail(row) } label: {
                                Label("OPEN FULL DETAIL", systemImage: OPSStyle.Icons.openDetail)
                            }
                        }

                        if index < group.rows.count - 1 {
                            Divider()
                                .background(OPSStyle.Colors.separator)
                                .padding(.leading, OPSStyle.Layout.spacing5)
                        }
                    }
                }
                .nestedCard()
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassDense(cornerRadius: OPSStyle.Layout.modalRadius)
        .ignoresSafeArea(edges: .bottom)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.clear)
    }

    private func openDetail(_ row: EnrichedVariantRow) {
        onOpenDetail(row)
    }
}
