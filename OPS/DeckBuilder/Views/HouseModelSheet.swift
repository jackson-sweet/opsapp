// OPS/OPS/DeckBuilder/Views/HouseModelSheet.swift

import DeckKit
import SwiftUI

struct HouseModelSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var floorLineText: String = ""
    @State private var storyHeightsText: String = ""
    @State private var openingEditor: HouseOpeningEditorContext?
    @State private var showingLedgerDetail = false

    private var house: HouseModel {
        viewModel.drawingData.house ?? HouseModel()
    }

    private var rows: [HouseOpeningSchedule.ScheduleRow] {
        HouseOpeningSchedule.rows(for: viewModel.drawingData)
    }

    private var defaultHouseEdgeId: String? {
        viewModel.houseEdges.first?.id
    }

    private var houseCapabilities: DeckCapabilities {
        viewModel.canEditHouseOpenings ? .full : .light
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    capabilityGate
                    datumSection
                    houseEdgesSection
                    openingsSection
                    elevationSection
                    scheduleSection
                    ledgerSection
                    advisorySection
                }
                .padding(OPSStyle.Layout.spacing3_5)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("// HOUSE MODEL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("DONE") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $openingEditor) { context in
            switch context {
            case let .add(edgeId):
                WallOpeningEditorView(
                    viewModel: viewModel,
                    opening: nil,
                    initialEdgeId: edgeId
                )
            case let .edit(opening):
                WallOpeningEditorView(
                    viewModel: viewModel,
                    opening: opening,
                    initialEdgeId: opening.edgeId
                )
            }
        }
        .sheet(isPresented: $showingLedgerDetail) {
            LedgerDetailSheet(viewModel: viewModel)
        }
        .onAppear(perform: syncFields)
        .onChange(of: viewModel.drawingData.house) { _, _ in
            syncFields()
        }
    }

    @ViewBuilder
    private var capabilityGate: some View {
        if !viewModel.canEditHouseOpenings {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "lock")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                Text("FULL DECKS APP REQUIRED. OPS CAN VIEW STANDARDIZED DECK OBJECTS ONLY.")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface(borderColor: OPSStyle.Colors.tanLineM)
        }
    }

    private var datumSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// DATUM")
            VStack(spacing: OPSStyle.Layout.spacing2) {
                tokenTextField(
                    label: "Floor line ft",
                    text: $floorLineText,
                    placeholder: "0"
                )
                tokenTextField(
                    label: "Story heights ft",
                    text: $storyHeightsText,
                    placeholder: "8, 8"
                )
            }
            actionButton(
                title: "COMMIT DATUM",
                systemImage: "checkmark",
                isPrimary: true,
                isDisabled: !viewModel.canEditHouseOpenings,
                action: commitDatum
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var houseEdgesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// HOUSE EDGES")
            if viewModel.houseEdges.isEmpty {
                emptyLine("MARK ONE EDGE AS HOUSE EDGE BEFORE ADDING OPENINGS.")
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(viewModel.houseEdges.enumerated()), id: \.element.id) { index, edge in
                        edgeRow(edge: edge, index: index)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var openingsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                sectionHeader("// OPENINGS")
                Spacer()
                Button {
                    if let edgeId = defaultHouseEdgeId {
                        openingEditor = .add(edgeId: edgeId)
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        .foregroundColor(defaultHouseEdgeId == nil ? OPSStyle.Colors.textMute : OPSStyle.Colors.text)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                }
                .buttonStyle(.plain)
                .disabled(defaultHouseEdgeId == nil || !viewModel.canEditHouseOpenings)
                .accessibilityLabel("ADD OPENING")
            }

            if rows.isEmpty {
                emptyLine("NO OPENINGS MODELED.")
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(rows) { row in
                        openingRow(row)
                    }
                }
            }

            actionButton(
                title: "ADD OPENING",
                systemImage: "plus",
                isPrimary: false,
                isDisabled: defaultHouseEdgeId == nil || !viewModel.canEditHouseOpenings,
                action: {
                    if let edgeId = defaultHouseEdgeId {
                        openingEditor = .add(edgeId: edgeId)
                    }
                }
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// LEDGER")
            if let ledger = house.ledger {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    labeledValue("Cladding", ledger.cladding.displayName)
                    labeledValue("Attachment", ledger.attachmentAllowed ? "Ledger allowed" : "Freestanding beam")
                    labeledValue("Fasteners", ledger.fastenerSchedule ?? "—")
                    labeledValue("Lateral connectors", ledger.lateralConnectors.map(String.init) ?? "—")
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .nestedCard()
            } else {
                emptyLine("NO LEDGER STRATEGY RESOLVED.")
            }
            actionButton(
                title: "EDIT LEDGER",
                systemImage: "rectangle.connected.to.line.below",
                isPrimary: false,
                isDisabled: viewModel.houseEdges.isEmpty || !viewModel.canEditHouseOpenings,
                action: { showingLedgerDetail = true }
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var elevationSection: some View {
        HouseElevationView(
            data: viewModel.drawingData,
            capabilities: houseCapabilities
        )
    }

    private var scheduleSection: some View {
        HouseOpeningScheduleView(
            data: viewModel.drawingData,
            capabilities: houseCapabilities
        )
    }

    private var advisorySection: some View {
        Text("ENGINEER REVIEW REQUIRED. OPS FLAGS ATTACHMENT RISK ONLY. HAVE PLANS REVIEWED BY A LICENSED ENGINEER BEFORE PERMIT OR BUILD.")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface(borderColor: OPSStyle.Colors.tanLineM)
    }

    private func openingRow(_ row: HouseOpeningSchedule.ScheduleRow) -> some View {
        Button {
            if let opening = house.openings.first(where: { $0.id == row.id }) {
                openingEditor = .edit(opening)
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Text(row.calloutTag)
                    .font(OPSStyle.Typography.badgeCake)
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.surfaceActive)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(row.kindDisplay.uppercased())
                        .font(OPSStyle.Typography.category)
                        .foregroundColor(OPSStyle.Colors.text)
                    Text("\(formatInches(row.widthInches)) × \(formatInches(row.heightInches)) · sill \(formatInches(row.sillHeightInches))")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .nestedCard()
        }
        .buttonStyle(.plain)
    }

    private func edgeRow(edge: DeckEdge, index: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("HOUSE EDGE \(index + 1)")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.text)
                Text(edge.label?.isEmpty == false ? edge.label ?? edge.id : edge.id)
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .lineLimit(1)
            }
            Spacer()
            Text(edge.dimension.map(formatInches) ?? "—")
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text2)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
        .nestedCard()
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.panelTitle)
            .foregroundColor(OPSStyle.Colors.text3)
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.text3)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func emptyLine(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.text3)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin, alignment: .leading)
    }

    private func tokenTextField(
        label: String,
        text: Binding<String>,
        placeholder: String
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.text3)
            TextField(placeholder, text: text)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
                .keyboardType(.numbersAndPunctuation)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .frame(minHeight: OPSStyle.Layout.inputHeight)
                .background(OPSStyle.Colors.surfaceInput)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private func actionButton(
        title: String,
        systemImage: String,
        isPrimary: Bool,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: systemImage)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                Text(title)
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(buttonForeground(isPrimary: isPrimary, isDisabled: isDisabled))
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.bottomCTAHeight)
            .background(buttonBackground(isPrimary: isPrimary, isDisabled: isDisabled))
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .strokeBorder(buttonBorder(isPrimary: isPrimary, isDisabled: isDisabled), lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }

    private func buttonForeground(isPrimary: Bool, isDisabled: Bool) -> Color {
        if isDisabled { return OPSStyle.Colors.textMute }
        return isPrimary ? OPSStyle.Colors.invertedText : OPSStyle.Colors.text
    }

    private func buttonBackground(isPrimary: Bool, isDisabled: Bool) -> Color {
        if isDisabled { return OPSStyle.Colors.surfaceInput }
        return isPrimary ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.surfaceHover
    }

    private func buttonBorder(isPrimary: Bool, isDisabled: Bool) -> Color {
        if isDisabled { return OPSStyle.Colors.nestedBorder }
        return isPrimary ? OPSStyle.Colors.line.opacity(0) : OPSStyle.Colors.line
    }

    private func syncFields() {
        floorLineText = house.floorLineFeet.map(formatFeet) ?? ""
        storyHeightsText = house.storyHeights.map(formatFeet).joined(separator: ", ")
    }

    private func commitDatum() {
        guard viewModel.canEditHouseOpenings else { return }
        _ = viewModel.setFloorLine(feet: decimalValue(floorLineText))
        _ = viewModel.setStoryHeights(decimalList(storyHeightsText))
    }

    private func decimalValue(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed)
    }

    private func decimalList(_ text: String) -> [Double] {
        text
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .compactMap(Double.init)
            .filter { $0 > 0 }
    }

    private func formatFeet(_ value: Double) -> String {
        formattedDecimal(value)
    }

    private func formatInches(_ value: Double) -> String {
        DimensionEngine.format(value, system: viewModel.drawingData.config.measurementSystem)
    }

    private func formattedDecimal(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.2f", rounded)
            .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

private enum HouseOpeningEditorContext: Identifiable {
    case add(edgeId: String)
    case edit(WallOpening)

    var id: String {
        switch self {
        case let .add(edgeId):
            return "add-\(edgeId)"
        case let .edit(opening):
            return "edit-\(opening.id)"
        }
    }
}
