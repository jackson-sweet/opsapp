import OPSDesignKit
import SwiftUI

public struct HouseOpeningScheduleViewModel: Equatable {
    public struct DisplayRow: Equatable, Identifiable {
        public var id: String
        public var calloutTag: String
        public var kindLabel: String
        public var sizeLabel: String
        public var sillLabel: String
        public var edgeLabel: String

        public init(
            id: String,
            calloutTag: String,
            kindLabel: String,
            sizeLabel: String,
            sillLabel: String,
            edgeLabel: String
        ) {
            self.id = id
            self.calloutTag = calloutTag
            self.kindLabel = kindLabel
            self.sizeLabel = sizeLabel
            self.sillLabel = sillLabel
            self.edgeLabel = edgeLabel
        }
    }

    public var displayRows: [DisplayRow]
    public let emptyStateText = "—"

    public var isEmpty: Bool {
        displayRows.isEmpty
    }

    public init(
        rows: [HouseOpeningSchedule.ScheduleRow],
        edgeLabelsById: [String: String] = [:]
    ) {
        self.displayRows = rows.map { row in
            DisplayRow(
                id: row.id,
                calloutTag: row.calloutTag,
                kindLabel: row.kindDisplay.uppercased(),
                sizeLabel: "\(Self.dimensionLabel(row.widthInches)) × \(Self.dimensionLabel(row.heightInches))",
                sillLabel: Self.dimensionLabel(row.sillHeightInches),
                edgeLabel: HouseViewLabelFormatter.scheduleEdgeLabel(
                    edgeId: row.edgeId,
                    labelsById: edgeLabelsById
                )
            )
        }
    }

    public init(
        data: DeckDrawingData,
        capabilities: DeckCapabilities = .full
    ) {
        let canShowHouseOpenings = capabilities.contains(.houseOpenings)
        self.init(
            rows: canShowHouseOpenings ? HouseOpeningSchedule.rows(for: data) : [],
            edgeLabelsById: canShowHouseOpenings ? HouseViewLabelFormatter.edgeLabelsById(data) : [:]
        )
    }

    private static func dimensionLabel(_ rawInches: Double) -> String {
        let rounded = max(0, Int(rawInches.rounded()))
        let feet = rounded / 12
        let inches = rounded % 12

        guard feet > 0 else {
            return "\(inches)″"
        }

        return "\(feet)′-\(inches)″"
    }
}

public struct HouseOpeningScheduleView: View {
    private let model: HouseOpeningScheduleViewModel

    public init(rows: [HouseOpeningSchedule.ScheduleRow]) {
        self.model = HouseOpeningScheduleViewModel(rows: rows)
    }

    public init(
        data: DeckDrawingData,
        capabilities: DeckCapabilities = .full
    ) {
        self.model = HouseOpeningScheduleViewModel(data: data, capabilities: capabilities)
    }

    public init(model: HouseOpeningScheduleViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            header

            if model.isEmpty {
                emptyState
            } else {
                Grid(
                    alignment: .leading,
                    horizontalSpacing: OPSStyle.Layout.spacing2,
                    verticalSpacing: OPSStyle.Layout.spacing2
                ) {
                    scheduleHeader
                    ForEach(model.displayRows) { row in
                        scheduleRow(row)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(panelBackground)
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// DOOR/WINDOW SCHEDULE")
                .font(OPSStyle.Typography.fieldPanelTitle)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)

            Text(model.isEmpty ? model.emptyStateText : "\(model.displayRows.count)")
                .font(OPSStyle.Typography.fieldBadge)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.chipMinHeight)
                .background(OPSStyle.Colors.surfaceActive)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(OPSStyle.Layout.chipRadius)

            Spacer(minLength: 0)
        }
    }

    private var scheduleHeader: some View {
        GridRow {
            headerCell("MARK")
            headerCell("TYPE")
            headerCell("W×H")
            headerCell("SILL")
            headerCell("EDGE")
        }
    }

    private func scheduleRow(_ row: HouseOpeningScheduleViewModel.DisplayRow) -> some View {
        GridRow {
            bodyCell(row.calloutTag, emphasis: true)
            bodyCell(row.kindLabel)
            bodyCell(row.sizeLabel, numeric: true)
            bodyCell(row.sillLabel, numeric: true)
            bodyCell(row.edgeLabel)
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func headerCell(_ value: String) -> some View {
        Text(value)
            .font(OPSStyle.Typography.fieldMetadata)
            .foregroundColor(OPSStyle.Colors.text3)
            .lineLimit(1)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight, alignment: .leading)
    }

    private func bodyCell(
        _ value: String,
        emphasis: Bool = false,
        numeric: Bool = false
    ) -> some View {
        Text(value)
            .font(emphasis ? OPSStyle.Typography.fieldBadge : OPSStyle.Typography.fieldDataValue)
            .monospacedDigit()
            .foregroundColor(emphasis ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
            .lineLimit(1)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
    }

    private var emptyState: some View {
        Text(model.emptyStateText)
            .font(OPSStyle.Typography.fieldDataValueLg)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.text3)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard * 3)
            .background(OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.cardRadius)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
            .fill(OPSStyle.Colors.glassApprox)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
    }
}
