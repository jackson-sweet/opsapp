// OPS/OPS/DeckBuilder/Views/WallOpeningEditorView.swift

import DeckKit
import SwiftUI
import UIKit

struct WallOpeningEditorView: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    private let editingOpening: WallOpening?

    @State private var draftId: String
    @State private var kind: OpeningKind
    @State private var selectedEdgeId: String
    @State private var widthText: String
    @State private var heightText: String
    @State private var sillText: String
    @State private var offsetText: String
    @State private var lastResult: HouseOpeningMutationResult?

    init(
        viewModel: DeckBuilderViewModel,
        opening: WallOpening?,
        initialEdgeId: String?
    ) {
        self.viewModel = viewModel
        self.editingOpening = opening
        let resolvedEdgeId = opening?.edgeId ?? initialEdgeId ?? viewModel.houseEdges.first?.id ?? ""
        _draftId = State(initialValue: opening?.id ?? UUID().uuidString)
        _kind = State(initialValue: opening?.kind ?? .window)
        _selectedEdgeId = State(initialValue: resolvedEdgeId)
        _widthText = State(initialValue: Self.formatDecimal(opening?.widthInches ?? Self.defaultWidthInches))
        _heightText = State(initialValue: Self.formatDecimal(opening?.heightInches ?? Self.defaultHeightInches))
        _sillText = State(initialValue: Self.formatDecimal(opening?.sillHeightInches ?? Self.defaultSillInches))
        _offsetText = State(initialValue: Self.formatDecimal(opening?.offsetAlongEdgeInches ?? Self.defaultOffsetInches))
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    if viewModel.houseEdges.isEmpty {
                        noHouseEdges
                    } else {
                        wallPreviewSection
                        openingFieldsSection
                        validationSection
                        actionSection
                    }
                }
                .padding(OPSStyle.Layout.spacing3_5)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle(editingOpening == nil ? "// ADD OPENING" : "// EDIT OPENING")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.fieldButtonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .onAppear(perform: lightImpact)
    }

    private var wallPreviewSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// WALL STRIP")
            WallOpeningStripPreview(
                opening: draftOpening,
                wallLengthInches: selectedWallLength,
                storyHeightInches: storyHeightInches,
                validation: liveValidation
            )
            if let edge = selectedEdge {
                labeledValue("Wall length", DimensionEngine.format(edgeLength(edge), system: viewModel.drawingData.config.measurementSystem))
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var openingFieldsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// OPENING")
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Picker("TYPE", selection: $kind) {
                    ForEach(OpeningKind.allCases, id: \.self) { option in
                        Text(option.displayName).tag(option)
                    }
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text("HOUSE EDGE")
                        .font(OPSStyle.Typography.fieldCategory)
                        .foregroundColor(OPSStyle.Colors.text3)
                    Picker("HOUSE EDGE", selection: $selectedEdgeId) {
                        ForEach(Array(viewModel.houseEdges.enumerated()), id: \.element.id) { index, edge in
                            Text("House edge \(index + 1)").tag(edge.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(OPSStyle.Typography.fieldDataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.text)
                    .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.inputHeight, alignment: .leading)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.surfaceInput)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }

                tokenTextField(label: "Width in", text: $widthText)
                tokenTextField(label: "Height in", text: $heightText)
                tokenTextField(label: "Offset in", text: $offsetText)

                if isWindow {
                    tokenTextField(label: "Sill in", text: $sillText)
                } else {
                    labeledValue("Sill", "0\"")
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var validationSection: some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: validationIcon)
                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                .foregroundColor(validationColor)
            Text(validationMessage)
                .font(OPSStyle.Typography.fieldMetadata)
                .monospacedDigit()
                .foregroundColor(validationColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface(borderColor: validationBorder)
    }

    private var actionSection: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                saveOpening()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                    Text("COMMIT OPENING")
                        .font(OPSStyle.Typography.fieldButtonLabel)
                }
                .foregroundColor(saveDisabled ? OPSStyle.Colors.textMute : OPSStyle.Colors.invertedText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.bottomCTAHeight)
                .background(saveDisabled ? OPSStyle.Colors.surfaceInput : OPSStyle.Colors.opsAccent)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .strokeBorder(saveDisabled ? OPSStyle.Colors.nestedBorder : OPSStyle.Colors.opsAccent, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(.plain)
            .disabled(saveDisabled)

            if let editingOpening {
                Button {
                    if viewModel.removeOpening(id: editingOpening.id) {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "trash")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        Text("REMOVE")
                            .font(OPSStyle.Typography.fieldButtonLabel)
                    }
                    .foregroundColor(OPSStyle.Colors.roseTextM)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(OPSStyle.Colors.roseFillM)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .strokeBorder(OPSStyle.Colors.roseLineM, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var noHouseEdges: some View {
        Text("MARK ONE EDGE AS HOUSE EDGE BEFORE ADDING OPENINGS.")
            .font(OPSStyle.Typography.fieldMetadata)
            .foregroundColor(OPSStyle.Colors.tanTextM)
            .fixedSize(horizontal: false, vertical: true)
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface(borderColor: OPSStyle.Colors.tanLineM)
    }

    private var draftOpening: WallOpening? {
        guard let width = decimalValue(widthText),
              let height = decimalValue(heightText),
              let offset = decimalValue(offsetText),
              width > 0,
              height > 0,
              !selectedEdgeId.isEmpty else {
            return nil
        }
        return WallOpening(
            id: draftId,
            edgeId: selectedEdgeId,
            kind: kind,
            widthInches: width,
            heightInches: height,
            sillHeightInches: isWindow ? (decimalValue(sillText) ?? 0) : 0,
            offsetAlongEdgeInches: offset
        )
    }

    private var liveValidation: WallOpeningGeometry.Validation? {
        guard let opening = draftOpening,
              let edge = selectedEdge else {
            return nil
        }
        return WallOpeningGeometry.validate(
            opening,
            wallLengthInches: WallOpeningGeometry.wallLengthInches(edge: edge, in: viewModel.drawingData),
            storyHeightInches: storyHeightInches,
            existing: viewModel.drawingData.house?.openings ?? []
        )
    }

    private var saveDisabled: Bool {
        guard viewModel.canEditHouseOpenings,
              draftOpening != nil,
              let validation = liveValidation else {
            return true
        }
        switch validation {
        case .ok, .clampedToWall:
            return false
        case .overlapsOpening, .headExceedsStory, .zeroOrNegativeSize:
            return true
        }
    }

    private var selectedEdge: DeckEdge? {
        viewModel.findEdge(byId: selectedEdgeId)
    }

    private var selectedWallLength: Double {
        selectedEdge.map(edgeLength) ?? 0
    }

    private var storyHeightInches: Double {
        let feet = viewModel.drawingData.house?.storyHeights.first(where: { $0 > 0 })
            ?? HouseEditingIntentEngine.defaultStoryHeightFeet
        return feet * 12
    }

    private var isWindow: Bool {
        kind == .window
    }

    private var validationMessage: String {
        if let lastResult, !lastResult.didMutate {
            return message(for: lastResult)
        }
        guard let validation = liveValidation else {
            return "ENTER OPENING DIMENSIONS."
        }
        switch validation {
        case .ok:
            return "READY."
        case let .clampedToWall(adjustedOffsetInches):
            return "OFFSET WILL CLAMP TO \(DimensionEngine.format(adjustedOffsetInches, system: viewModel.drawingData.config.measurementSystem))."
        case let .overlapsOpening(otherId):
            return "OPENING OVERLAPS \(callout(for: otherId))."
        case let .headExceedsStory(headInches, storyHeightInches):
            return "HEAD \(DimensionEngine.format(headInches, system: viewModel.drawingData.config.measurementSystem)) EXCEEDS STORY \(DimensionEngine.format(storyHeightInches, system: viewModel.drawingData.config.measurementSystem))."
        case .zeroOrNegativeSize:
            return "ENTER WIDTH AND HEIGHT."
        }
    }

    private var validationColor: Color {
        guard let validation = liveValidation else { return OPSStyle.Colors.tanTextM }
        switch validation {
        case .ok:
            return OPSStyle.Colors.oliveTextM
        case .clampedToWall:
            return OPSStyle.Colors.tanTextM
        case .overlapsOpening, .headExceedsStory, .zeroOrNegativeSize:
            return OPSStyle.Colors.roseTextM
        }
    }

    private var validationBorder: Color {
        guard let validation = liveValidation else { return OPSStyle.Colors.tanLineM }
        switch validation {
        case .ok:
            return OPSStyle.Colors.oliveLineM
        case .clampedToWall:
            return OPSStyle.Colors.tanLineM
        case .overlapsOpening, .headExceedsStory, .zeroOrNegativeSize:
            return OPSStyle.Colors.roseLineM
        }
    }

    private var validationIcon: String {
        guard let validation = liveValidation else { return "exclamationmark.triangle" }
        switch validation {
        case .ok:
            return "checkmark.circle"
        case .clampedToWall:
            return "arrow.left.and.right"
        case .overlapsOpening, .headExceedsStory, .zeroOrNegativeSize:
            return "exclamationmark.triangle"
        }
    }

    private func saveOpening() {
        guard let opening = draftOpening else { return }
        let result: HouseOpeningMutationResult
        if editingOpening == nil {
            result = viewModel.addOpening(
                kind,
                onEdge: opening.edgeId,
                widthInches: opening.widthInches,
                heightInches: opening.heightInches,
                sillHeightInches: opening.sillHeightInches,
                offsetAlongEdgeInches: opening.offsetAlongEdgeInches
            )
        } else {
            result = viewModel.updateOpening(opening)
        }
        lastResult = result
        if result.didMutate {
            dismiss()
        }
    }

    private func message(for result: HouseOpeningMutationResult) -> String {
        switch result {
        case .unavailable:
            return "FULL DECKS APP REQUIRED."
        case let .missingHouseEdge(edgeId):
            return "HOUSE EDGE \(edgeId) NOT FOUND."
        case let .openingNotFound(id):
            return "OPENING \(id) NOT FOUND."
        case let .overlapsOpening(otherId):
            return "OPENING OVERLAPS \(callout(for: otherId))."
        case let .headExceedsStory(headInches, storyHeightInches):
            return "HEAD \(DimensionEngine.format(headInches, system: viewModel.drawingData.config.measurementSystem)) EXCEEDS STORY \(DimensionEngine.format(storyHeightInches, system: viewModel.drawingData.config.measurementSystem))."
        case .zeroOrNegativeSize:
            return "ENTER WIDTH AND HEIGHT."
        case .ok, .clampedToWall:
            return "READY."
        }
    }

    private func callout(for openingId: String) -> String {
        HouseOpeningSchedule.calloutTag(for: openingId, in: viewModel.drawingData) ?? openingId
    }

    private func edgeLength(_ edge: DeckEdge) -> Double {
        WallOpeningGeometry.wallLengthInches(edge: edge, in: viewModel.drawingData)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.fieldPanelTitle)
            .foregroundColor(OPSStyle.Colors.text3)
    }

    private func labeledValue(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.fieldCategory)
                .foregroundColor(OPSStyle.Colors.text3)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.fieldDataValue)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
                .multilineTextAlignment(.trailing)
        }
    }

    private func tokenTextField(label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.fieldCategory)
                .foregroundColor(OPSStyle.Colors.text3)
            TextField("0", text: text)
                .font(OPSStyle.Typography.fieldDataValue)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.text)
                .keyboardType(.decimalPad)
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

    private func decimalValue(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func formatDecimal(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() {
            return String(Int(rounded))
        }
        return String(format: "%.2f", rounded)
            .trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private func lightImpact() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private static var defaultWidthInches: Double { 48 }
    private static var defaultHeightInches: Double { 48 }
    private static var defaultSillInches: Double { 36 }
    private static var defaultOffsetInches: Double { 24 }
}

private struct WallOpeningStripPreview: View {
    var opening: WallOpening?
    var wallLengthInches: Double
    var storyHeightInches: Double
    var validation: WallOpeningGeometry.Validation?

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )

                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: OPSStyle.Layout.Border.standard)
                    .frame(maxHeight: .infinity, alignment: .bottom)

                if let opening {
                    openingShape(opening, proxy: proxy)
                }
            }
        }
        .frame(height: OPSStyle.Layout.touchTargetLarge * 2)
    }

    private func openingShape(_ opening: WallOpening, proxy: GeometryProxy) -> some View {
        let rect = WallOpeningGeometry.cutoutRect2D(opening)
        let safeWallLength = max(wallLengthInches, 1)
        let safeStoryHeight = max(storyHeightInches, 1)
        let width = max(OPSStyle.Layout.spacing1, (rect.width / safeWallLength) * proxy.size.width)
        let height = max(OPSStyle.Layout.spacing2, (rect.height / safeStoryHeight) * proxy.size.height)
        let x = (rect.minX / safeWallLength) * proxy.size.width
        let yFromBottom = (rect.minY / safeStoryHeight) * proxy.size.height

        return ZStack {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(OPSStyle.Colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .strokeBorder(openingBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            if opening.kind == .window {
                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: OPSStyle.Layout.Border.standard)
            }
        }
        .frame(width: width, height: height)
        .position(
            x: x + width / 2,
            y: proxy.size.height - yFromBottom - height / 2
        )
    }

    private var openingBorder: Color {
        guard let validation else { return OPSStyle.Colors.text3 }
        switch validation {
        case .ok:
            return OPSStyle.Colors.oliveLineM
        case .clampedToWall:
            return OPSStyle.Colors.tanLineM
        case .overlapsOpening, .headExceedsStory, .zeroOrNegativeSize:
            return OPSStyle.Colors.roseLineM
        }
    }
}
