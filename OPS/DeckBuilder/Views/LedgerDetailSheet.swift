// OPS/OPS/DeckBuilder/Views/LedgerDetailSheet.swift

import DeckKit
import SwiftUI

struct LedgerDetailSheet: View {
    @ObservedObject var viewModel: DeckBuilderViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedEdgeId: String
    @State private var fastenerScheduleText: String
    @State private var lateralConnectorCount: Int

    init(viewModel: DeckBuilderViewModel) {
        self.viewModel = viewModel
        let ledger = viewModel.drawingData.house?.ledger
        _selectedEdgeId = State(initialValue: viewModel.houseEdges.first?.id ?? "")
        _fastenerScheduleText = State(initialValue: ledger?.fastenerSchedule ?? "")
        _lateralConnectorCount = State(initialValue: ledger?.lateralConnectors ?? 0)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    if viewModel.houseEdges.isEmpty {
                        noHouseEdges
                    } else {
                        edgeSection
                        strategySection
                        detailSection
                        advisorySection
                        commitButton
                    }
                }
                .padding(OPSStyle.Layout.spacing3_5)
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("// LEDGER DETAIL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var edgeSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// HOUSE EDGE")
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("EDGE")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.text3)
                Picker("EDGE", selection: $selectedEdgeId) {
                    ForEach(Array(viewModel.houseEdges.enumerated()), id: \.element.id) { index, edge in
                        Text("House edge \(index + 1)").tag(edge.id)
                    }
                }
                .pickerStyle(.menu)
                .font(OPSStyle.Typography.dataValue)
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

            if let edge = selectedEdge {
                labeledValue("Cladding", edge.houseEdgeMaterial?.displayName ?? HouseEdgeMaterial.stucco.displayName)
                labeledValue("Span", DimensionEngine.format(edgeLength(edge), system: viewModel.drawingData.config.measurementSystem))
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var strategySection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// STRATEGY")
            if let strategy {
                HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: strategyIcon(strategy))
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                        .foregroundColor(strategyColor(strategy))
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(strategyTitle(strategy))
                            .font(OPSStyle.Typography.category)
                            .foregroundColor(strategyColor(strategy))
                        Text(strategyDetail(strategy))
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                }
                .padding(OPSStyle.Layout.spacing2_5)
                .nestedCard()
            } else {
                emptyLine("SELECT A HOUSE EDGE.")
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface(borderColor: strategyBorder)
    }

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            sectionHeader("// FASTENERS")
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("SCHEDULE")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.text3)
                TextField("—", text: $fastenerScheduleText)
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.text)
                    .textInputAutocapitalization(.characters)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .frame(minHeight: OPSStyle.Layout.inputHeight)
                    .background(OPSStyle.Colors.surfaceInput)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .strokeBorder(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }

            Stepper(value: $lateralConnectorCount, in: connectorRange) {
                labeledValue("Lateral connectors", lateralConnectorCount == 0 ? "—" : String(lateralConnectorCount))
            }
            .tint(OPSStyle.Colors.text)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    private var advisorySection: some View {
        Text("ENGINEER REVIEW REQUIRED. OPS FLAGS ATTACHMENT RISK ONLY. HAVE PLANS REVIEWED BY A LICENSED ENGINEER BEFORE PERMIT OR BUILD.")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface(borderColor: OPSStyle.Colors.tanLineM)
    }

    private var commitButton: some View {
        Button {
            commit()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "checkmark")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .medium))
                Text("COMMIT LEDGER")
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundColor(commitDisabled ? OPSStyle.Colors.textMute : OPSStyle.Colors.invertedText)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.bottomCTAHeight)
            .background(commitDisabled ? OPSStyle.Colors.surfaceInput : OPSStyle.Colors.opsAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .strokeBorder(commitDisabled ? OPSStyle.Colors.nestedBorder : OPSStyle.Colors.opsAccent, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(.plain)
        .disabled(commitDisabled)
    }

    private var noHouseEdges: some View {
        Text("MARK ONE EDGE AS HOUSE EDGE BEFORE RESOLVING LEDGER DETAIL.")
            .font(OPSStyle.Typography.metadata)
            .foregroundColor(OPSStyle.Colors.tanTextM)
            .fixedSize(horizontal: false, vertical: true)
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface(borderColor: OPSStyle.Colors.tanLineM)
    }

    private var selectedEdge: DeckEdge? {
        viewModel.findEdge(byId: selectedEdgeId)
    }

    private var strategy: LedgerStrategyEngine.Strategy? {
        guard let edge = selectedEdge else { return nil }
        return LedgerStrategyEngine.strategy(
            for: edge,
            houseSideBeamSpanInches: edgeLength(edge),
            package: nil
        )
    }

    private var strategyBorder: Color {
        guard let strategy else { return OPSStyle.Colors.line }
        switch strategy {
        case .attach:
            return OPSStyle.Colors.oliveLineM
        case .freestanding:
            return OPSStyle.Colors.tanLineM
        }
    }

    private var commitDisabled: Bool {
        !viewModel.canEditHouseOpenings || selectedEdge == nil
    }

    private var connectorRange: ClosedRange<Int> {
        0...8
    }

    private func commit() {
        guard let edge = selectedEdge else { return }
        let schedule = trimmedNil(fastenerScheduleText)
        let connectors = lateralConnectorCount > 0 ? lateralConnectorCount : nil
        _ = viewModel.resolveLedger(
            forEdge: edge.id,
            houseSideBeamSpanInches: edgeLength(edge),
            fastenerSchedule: schedule,
            lateralConnectors: connectors
        )
        dismiss()
    }

    private func strategyTitle(_ strategy: LedgerStrategyEngine.Strategy) -> String {
        switch strategy {
        case .attach:
            return "LEDGER ATTACHMENT"
        case .freestanding:
            return "FREESTANDING HOUSE-SIDE BEAM"
        }
    }

    private func strategyDetail(_ strategy: LedgerStrategyEngine.Strategy) -> String {
        switch strategy {
        case let .attach(detail):
            return "\(detail.cladding.displayName) accepts ledger attachment in this model."
        case let .freestanding(_, fallback):
            return fallback.rationale
        }
    }

    private func strategyIcon(_ strategy: LedgerStrategyEngine.Strategy) -> String {
        switch strategy {
        case .attach:
            return "link"
        case .freestanding:
            return "exclamationmark.triangle"
        }
    }

    private func strategyColor(_ strategy: LedgerStrategyEngine.Strategy) -> Color {
        switch strategy {
        case .attach:
            return OPSStyle.Colors.oliveTextM
        case .freestanding:
            return OPSStyle.Colors.tanTextM
        }
    }

    private func edgeLength(_ edge: DeckEdge) -> Double {
        WallOpeningGeometry.wallLengthInches(edge: edge, in: viewModel.drawingData)
    }

    private func trimmedNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
}
