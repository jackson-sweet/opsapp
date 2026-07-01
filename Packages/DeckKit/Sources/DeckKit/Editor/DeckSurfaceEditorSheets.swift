import OPSDesignKit
import SwiftUI

public struct SurfacePatternSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSurfaceId: String?

    public init(model: DeckDrawingEditorModel) {
        self.model = model
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "SURFACE PATTERN"),
            subtitle: String(localized: "Pick the surface, then commit the board field.")
        ) {
            if model.drawingData.detectedSurfaces.isEmpty {
                DeckSurfaceEditorEmptyState(
                    title: String(localized: "No closed surface"),
                    message: String(localized: "Close a deck outline before assigning board direction.")
                )
            } else {
                surfaceSelector
                patternList
            }
        }
        .onAppear {
            selectedSurfaceId = selectedSurfaceId ?? model.drawingData.detectedSurfaces.first?.id
        }
    }

    private var surfaceSelector: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// SURFACE"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(model.drawingData.detectedSurfaces.enumerated()), id: \.element.id) { index, surface in
                        DeckSurfaceEditorChip(
                            title: String(localized: "SURFACE \(index + 1)"),
                            value: DimensionEngine.formatArea(
                                PolygonMath.area(vertices: surface.positions) / pow(model.drawingData.effectiveScaleFactor, 2),
                                system: model.drawingData.config.measurementSystem
                            ),
                            isActive: selectedSurfaceId == surface.id
                        ) {
                            selectedSurfaceId = surface.id
                        }
                    }
                }
            }
        }
    }

    private var patternList: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// PATTERN"))

            VStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(DeckingPattern.allCases, id: \.rawValue) { pattern in
                    Button {
                        guard let selectedSurfaceId else { return }
                        _ = model.setSurfacePattern(pattern, forSurfaceId: selectedSurfaceId)
                        dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
                                DeckPatternPreview(pattern: pattern)
                                    .frame(
                                        width: OPSStyle.Layout.touchTargetLarge * 2,
                                        height: OPSStyle.Layout.touchTargetLarge
                                    )

                                Spacer(minLength: OPSStyle.Layout.spacing2)

                                DeckSurfaceEditorStatusMark(isActive: isSelected(pattern))
                            }

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                Text(pattern.editorTitle.uppercased())
                                    .font(OPSStyle.Typography.fieldButtonLabel)
                                    .foregroundStyle(OPSStyle.Colors.text)
                                Text(pattern.editorSubtitle)
                                    .font(OPSStyle.Typography.fieldMetadata)
                                    .foregroundStyle(OPSStyle.Colors.text2)
                            }
                        }
                        .padding(OPSStyle.Layout.spacing2)
                        .frame(minHeight: OPSStyle.Layout.touchTargetLarge)
                        .background(OPSStyle.Colors.surfaceInput)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(isSelected(pattern) ? OPSStyle.Colors.line : OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func isSelected(_ pattern: DeckingPattern) -> Bool {
        guard let selectedSurfaceId else { return false }
        return model.drawingData.surfaceFeatures?.patterns.contains {
            $0.surfaceId == selectedSurfaceId && $0.pattern == pattern
        } ?? false
    }
}

public struct StairDetailSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var selectedEdgeId: String?
    @State private var draftConfig = StairConfig(width: StairDetailDefaults.widths.first ?? 48)

    public init(model: DeckDrawingEditorModel) {
        self.model = model
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "STAIR DETAIL"),
            subtitle: String(localized: "One flight. Width, stringers, tread stock.")
        ) {
            if eligibleEdges.isEmpty {
                DeckSurfaceEditorEmptyState(
                    title: String(localized: "No deck edge"),
                    message: String(localized: "Draw an edge before adding a stair flight.")
                )
            } else {
                edgeSelector
                stairControls
            }
        }
        .onAppear {
            selectedEdgeId = selectedEdgeId ?? eligibleEdges.first?.id
            loadDraftConfig()
        }
        .onChange(of: selectedEdgeId) { _, _ in
            loadDraftConfig()
        }
    }

    private var eligibleEdges: [DeckEdge] {
        model.drawingData.edges.filter { $0.edgeType != .houseEdge }
    }

    private var edgeSelector: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// FLIGHT"))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(Array(eligibleEdges.enumerated()), id: \.element.id) { index, edge in
                        DeckSurfaceEditorChip(
                            title: String(localized: "FLIGHT \(index + 1)"),
                            value: edge.dimension.map {
                                DimensionEngine.format($0, system: model.drawingData.config.measurementSystem)
                            } ?? String(localized: "—"),
                            isActive: selectedEdgeId == edge.id
                        ) {
                            selectedEdgeId = edge.id
                        }
                    }
                }
            }
        }
    }

    private var stairControls: some View {
        DeckSurfaceEditorPanel {
            DeckSurfaceEditorSectionHeader(String(localized: "// CONFIGURE"))

            VStack(spacing: OPSStyle.Layout.spacing2) {
                DeckSurfaceEditorOptionMenu(
                    title: String(localized: "WIDTH"),
                    value: DimensionEngine.format(draftConfig.width, system: model.drawingData.config.measurementSystem)
                ) {
                    ForEach(StairDetailDefaults.widths, id: \.self) { width in
                        Button(DimensionEngine.format(width, system: model.drawingData.config.measurementSystem)) {
                            draftConfig.width = width
                        }
                    }
                }

                DeckSurfaceEditorPickerRow(
                    title: String(localized: "STRINGER"),
                    options: StairStringerStyle.allCases,
                    selection: $draftConfig.stringerStyle,
                    titleForOption: \.editorTitle
                )

                DeckSurfaceEditorPickerRow(
                    title: String(localized: "MATERIAL"),
                    options: StairStringerMaterial.allCases,
                    selection: $draftConfig.stringerMaterial,
                    titleForOption: \.editorTitle
                )

                DeckSurfaceEditorPickerRow(
                    title: String(localized: "TREAD"),
                    options: StairTreadMaterial.allCases,
                    selection: $draftConfig.treadMaterial,
                    titleForOption: \.editorTitle
                )

                DeckSurfaceEditorChip(
                    title: String(localized: "LANDING SIDE"),
                    value: draftConfig.flipDirection ? String(localized: "Reverse") : String(localized: "Standard"),
                    isActive: draftConfig.flipDirection
                ) {
                    draftConfig.flipDirection.toggle()
                }

                Button {
                    guard let selectedEdgeId else { return }
                    _ = model.configureStairDetail(edgeId: selectedEdgeId, config: draftConfig, package: nil)
                    dismiss()
                } label: {
                    DeckSurfaceEditorPrimaryLabel(String(localized: "COMMIT STAIR"))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadDraftConfig() {
        guard let selectedEdgeId,
              let edge = eligibleEdges.first(where: { $0.id == selectedEdgeId }),
              let config = edge.stairConfig else { return }
        draftConfig = config
    }
}

public struct SurfaceFeaturesSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var fastenerSystem: FastenerSystem? = .hiddenClip
    @State private var fascia = false
    @State private var skirting: SkirtingSpec?
    @State private var finish: FinishSpec?
    @State private var builtInKind: BuiltInKind?
    @State private var lighting: LightingPlan?

    public init(model: DeckDrawingEditorModel) {
        self.model = model
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "SURFACE FEATURES"),
            subtitle: String(localized: "Fascia, skirting, fasteners, finish, lighting.")
        ) {
            DeckSurfaceEditorPanel {
                DeckSurfaceEditorSectionHeader(String(localized: "// FEATURES"))

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    DeckSurfaceEditorPickerRow(
                        title: String(localized: "FASTENER"),
                        options: FastenerSystem.allCases,
                        selection: Binding(
                            get: { fastenerSystem ?? .hiddenClip },
                            set: { fastenerSystem = $0 }
                        ),
                        titleForOption: \.editorTitle
                    )

                    DeckSurfaceEditorChip(
                        title: String(localized: "FASCIA"),
                        value: fascia ? String(localized: "Included") : String(localized: "None"),
                        isActive: fascia
                    ) {
                        fascia.toggle()
                    }

                    DeckSurfaceEditorOptionMenu(
                        title: String(localized: "SKIRTING"),
                        value: skirting?.material ?? String(localized: "—")
                    ) {
                        Button(String(localized: "None")) { skirting = nil }
                        Button(String(localized: "Ventilated lattice")) {
                            skirting = SkirtingSpec(material: String(localized: "ventilated lattice"), ventilated: true)
                        }
                        Button(String(localized: "Solid board")) {
                            skirting = SkirtingSpec(material: String(localized: "solid board"), ventilated: false)
                        }
                    }

                    DeckSurfaceEditorOptionMenu(
                        title: String(localized: "FINISH"),
                        value: finish?.kind ?? String(localized: "—")
                    ) {
                        Button(String(localized: "None")) { finish = nil }
                        Button(String(localized: "Cut-end seal")) {
                            finish = FinishSpec(kind: String(localized: "cut-end seal"), coats: 2)
                        }
                        Button(String(localized: "Stain")) {
                            finish = FinishSpec(kind: String(localized: "stain"), coats: 2)
                        }
                        Button(String(localized: "Oil")) {
                            finish = FinishSpec(kind: String(localized: "oil"), coats: 1)
                        }
                    }

                    DeckSurfaceEditorOptionMenu(
                        title: String(localized: "BUILT-IN"),
                        value: builtInKind?.editorTitle ?? String(localized: "—")
                    ) {
                        Button(String(localized: "None")) { builtInKind = nil }
                        ForEach(BuiltInKind.allCases, id: \.rawValue) { kind in
                            Button(kind.editorTitle) {
                                builtInKind = kind
                            }
                        }
                    }

                    DeckSurfaceEditorOptionMenu(
                        title: String(localized: "LIGHTING"),
                        value: lighting == nil ? String(localized: "—") : String(localized: "Perimeter")
                    ) {
                        Button(String(localized: "None")) { lighting = nil }
                        Button(String(localized: "Perimeter")) {
                            lighting = perimeterLightingPlan()
                        }
                    }

                    Button {
                        _ = model.setSurfaceFeatures(
                            fastenerSystem: fastenerSystem,
                            fascia: fascia,
                            skirting: skirting,
                            finish: finish,
                            builtIn: builtInFeature(),
                            lighting: lighting
                        )
                        dismiss()
                    } label: {
                        DeckSurfaceEditorPrimaryLabel(String(localized: "COMMIT FEATURES"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear(perform: loadFeatures)
    }

    private func loadFeatures() {
        fastenerSystem = model.drawingData.surfaceFeatures?.fastenerSystem ?? .hiddenClip
        fascia = model.drawingData.surfaceFeatures?.fascia ?? false
        skirting = model.drawingData.surfaceFeatures?.skirting
        finish = model.drawingData.surfaceFeatures?.finishes.first
        builtInKind = model.drawingData.surfaceFeatures?.builtIns.first?.kind
        lighting = model.drawingData.surfaceFeatures?.lighting
    }

    private func builtInFeature() -> BuiltInFeature? {
        guard let builtInKind else { return nil }
        return BuiltInFeature(
            kind: builtInKind,
            polygon: model.drawingData.detectedSurfaces.first?.positions ?? model.drawingData.orderedPositions,
            heightInches: builtInKind.defaultHeightInches
        )
    }

    private func perimeterLightingPlan() -> LightingPlan {
        let polygon = model.drawingData.detectedSurfaces.first?.positions ?? model.drawingData.orderedPositions
        return LightingPlan(
            fixtures: Array(polygon.prefix(LightingDefaults.maxPreviewFixtures)),
            transformerWatts: LightingDefaults.transformerWatts,
            receptacles: []
        )
    }
}

public struct OverheadStructureSheet: View {
    @ObservedObject private var model: DeckDrawingEditorModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind: OverheadKind = .pergola
    @State private var roofShape: RoofShape = .shed
    @State private var shadePercent = OverheadDefaults.shadePercents.first ?? 40

    public init(model: DeckDrawingEditorModel) {
        self.model = model
    }

    public var body: some View {
        DeckSurfaceEditorShell(
            title: String(localized: "OVERHEAD"),
            subtitle: String(localized: "One connect point for pergola or roof scope.")
        ) {
            DeckSurfaceEditorPanel {
                DeckSurfaceEditorSectionHeader(String(localized: "// CONNECT"))

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    DeckSurfaceEditorPickerRow(
                        title: String(localized: "TYPE"),
                        options: OverheadKind.allCases,
                        selection: $kind,
                        titleForOption: \.editorTitle
                    )

                    DeckSurfaceEditorPickerRow(
                        title: String(localized: "ROOF"),
                        options: RoofShape.allCases,
                        selection: $roofShape,
                        titleForOption: \.editorTitle
                    )

                    DeckSurfaceEditorOptionMenu(
                        title: String(localized: "SHADE"),
                        value: "\(Int(shadePercent))%"
                    ) {
                        ForEach(OverheadDefaults.shadePercents, id: \.self) { percent in
                            Button("\(Int(percent))%") {
                                shadePercent = percent
                            }
                        }
                    }

                    Button {
                        _ = model.upsertOverheadStructure(nextStructure, package: nil)
                        dismiss()
                    } label: {
                        DeckSurfaceEditorPrimaryLabel(String(localized: "CONNECT OVERHEAD"))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .onAppear(perform: loadOverhead)
    }

    private var nextStructure: OverheadStructure {
        let existing = model.drawingData.overhead?.structures.first
        return OverheadStructure(
            id: existing?.id ?? UUID().uuidString,
            kind: kind,
            roofShape: kind == .pergola ? nil : roofShape,
            footprint: model.drawingData.detectedSurfaces.first?.positions ?? model.drawingData.orderedPositions,
            framing: existing?.framing ?? [],
            shadePercent: kind == .pergola ? shadePercent : nil,
            productModel: existing?.productModel
        )
    }

    private func loadOverhead() {
        guard let existing = model.drawingData.overhead?.structures.first else { return }
        kind = existing.kind
        roofShape = existing.roofShape ?? .shed
        shadePercent = existing.shadePercent ?? shadePercent
    }
}

private enum StairDetailDefaults {
    static let widths: [Double] = [36, 42, 48, 60]
}

private enum OverheadDefaults {
    static let shadePercents: [Double] = [30, 40, 50, 60, 70]
}

private enum LightingDefaults {
    static let maxPreviewFixtures = 8
    static let transformerWatts = 60.0
}

struct DeckSurfaceEditorShell<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(title)
                        .font(OPSStyle.Typography.screenTitle(for: title))
                        .foregroundStyle(OPSStyle.Colors.text)
                    Text(subtitle)
                        .font(OPSStyle.Typography.fieldMetadata)
                        .foregroundStyle(OPSStyle.Colors.text2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                content
            }
            .padding(OPSStyle.Layout.spacing3)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
    }
}

struct DeckSurfaceEditorPanel<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            content
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.glassApprox)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius)
                .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius))
    }
}

struct DeckSurfaceEditorSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(OPSStyle.Typography.fieldPanelTitle)
            .foregroundStyle(OPSStyle.Colors.text3)
            .textCase(.uppercase)
    }
}

struct DeckSurfaceEditorChip: View {
    let title: String
    let value: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(title)
                    .font(OPSStyle.Typography.fieldCategory)
                    .foregroundStyle(OPSStyle.Colors.text3)
                Text(value)
                    .font(OPSStyle.Typography.fieldDataValue)
                    .foregroundStyle(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(isActive ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(isActive ? OPSStyle.Colors.line : OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        }
        .buttonStyle(.plain)
    }
}

struct DeckSurfaceEditorOptionMenu<Content: View>: View {
    let title: String
    let value: String
    @ViewBuilder var content: Content

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(title)
                        .font(OPSStyle.Typography.fieldCategory)
                        .foregroundStyle(OPSStyle.Colors.text3)
                    Text(value)
                        .font(OPSStyle.Typography.fieldDataValue)
                        .foregroundStyle(OPSStyle.Colors.text)
                }
                Spacer(minLength: OPSStyle.Layout.spacing2)
                Image(systemName: "chevron.up.chevron.down")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundStyle(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
        }
    }
}

struct DeckSurfaceEditorPickerRow<Option: Hashable>: View {
    let title: String
    let options: [Option]
    @Binding var selection: Option
    let titleForOption: KeyPath<Option, String>

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(title)
                .font(OPSStyle.Typography.fieldCategory)
                .foregroundStyle(OPSStyle.Colors.text3)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(options, id: \.self) { option in
                        DeckSurfaceEditorChip(
                            title: option[keyPath: titleForOption].uppercased(),
                            value: selection == option ? String(localized: "Set") : String(localized: "Tap"),
                            isActive: selection == option
                        ) {
                            selection = option
                        }
                    }
                }
            }
        }
    }
}

struct DeckSurfaceEditorPrimaryLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(OPSStyle.Typography.fieldButtonLabel)
            .foregroundStyle(OPSStyle.Colors.background)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.bottomCTAHeight)
            .background(OPSStyle.Colors.opsAccent)
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
    }
}

struct DeckSurfaceEditorStatusMark: View {
    let isActive: Bool

    var body: some View {
        Text(isActive ? String(localized: "SET") : String(localized: "—"))
            .font(OPSStyle.Typography.fieldBadge)
            .foregroundStyle(isActive ? OPSStyle.Colors.oliveTextM : OPSStyle.Colors.text3)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
            .background(isActive ? OPSStyle.Colors.oliveFillM : OPSStyle.Colors.fillNeutralDim)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(isActive ? OPSStyle.Colors.oliveLineM : OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
    }
}

struct DeckSurfaceEditorEmptyState: View {
    let title: String
    let message: String

    var body: some View {
        DeckSurfaceEditorPanel {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                Text(title.uppercased())
                    .font(OPSStyle.Typography.fieldPanelTitle)
                    .foregroundStyle(OPSStyle.Colors.text)
                Text(message)
                    .font(OPSStyle.Typography.fieldMetadata)
                    .foregroundStyle(OPSStyle.Colors.text2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct DeckPatternPreview: View {
    let pattern: DeckingPattern

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let border = Path(roundedRect: rect.insetBy(dx: OPSStyle.Layout.Border.thick, dy: OPSStyle.Layout.Border.thick), cornerRadius: OPSStyle.Layout.chipRadius)
            context.fill(border, with: .color(OPSStyle.Colors.fillNeutralDim))
            context.stroke(border, with: .color(OPSStyle.Colors.line), lineWidth: OPSStyle.Layout.Border.standard)

            switch pattern {
            case .parallel:
                drawParallel(context: context, size: size)
            case .diagonal:
                drawDiagonal(context: context, size: size)
            case .pictureFrame:
                drawParallel(context: context, size: size)
                context.stroke(
                    Path(roundedRect: rect.insetBy(dx: OPSStyle.Layout.spacing1, dy: OPSStyle.Layout.spacing1), cornerRadius: OPSStyle.Layout.progressBarRadius),
                    with: .color(OPSStyle.Colors.text2),
                    lineWidth: OPSStyle.Layout.Border.thick
                )
            case .herringbone:
                drawHerringbone(context: context, size: size)
            case .chevron:
                drawChevron(context: context, size: size)
            }
        }
    }

    private func drawParallel(context: GraphicsContext, size: CGSize) {
        var x = OPSStyle.Layout.spacing2
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: OPSStyle.Layout.spacing1))
            path.addLine(to: CGPoint(x: x, y: size.height - OPSStyle.Layout.spacing1))
            context.stroke(path, with: .color(OPSStyle.Colors.text3), lineWidth: OPSStyle.Layout.Border.standard)
            x += OPSStyle.Layout.spacing2
        }
    }

    private func drawDiagonal(context: GraphicsContext, size: CGSize) {
        var x = -size.height
        while x < size.width {
            var path = Path()
            path.move(to: CGPoint(x: x, y: size.height))
            path.addLine(to: CGPoint(x: x + size.height, y: 0))
            context.stroke(path, with: .color(OPSStyle.Colors.text3), lineWidth: OPSStyle.Layout.Border.standard)
            x += OPSStyle.Layout.spacing3
        }
    }

    private func drawHerringbone(context: GraphicsContext, size: CGSize) {
        let midX = size.width / 2
        var y = OPSStyle.Layout.spacing1
        while y < size.height {
            var left = Path()
            left.move(to: CGPoint(x: OPSStyle.Layout.spacing2, y: y))
            left.addLine(to: CGPoint(x: midX, y: y + OPSStyle.Layout.spacing2))
            context.stroke(left, with: .color(OPSStyle.Colors.text3), lineWidth: OPSStyle.Layout.Border.standard)

            var right = Path()
            right.move(to: CGPoint(x: size.width - OPSStyle.Layout.spacing2, y: y))
            right.addLine(to: CGPoint(x: midX, y: y + OPSStyle.Layout.spacing2))
            context.stroke(right, with: .color(OPSStyle.Colors.text3), lineWidth: OPSStyle.Layout.Border.standard)

            y += OPSStyle.Layout.spacing2
        }
    }

    private func drawChevron(context: GraphicsContext, size: CGSize) {
        let midX = size.width / 2
        var y = OPSStyle.Layout.spacing1
        while y < size.height {
            var path = Path()
            path.move(to: CGPoint(x: OPSStyle.Layout.spacing2, y: y + OPSStyle.Layout.spacing2))
            path.addLine(to: CGPoint(x: midX, y: y))
            path.addLine(to: CGPoint(x: size.width - OPSStyle.Layout.spacing2, y: y + OPSStyle.Layout.spacing2))
            context.stroke(path, with: .color(OPSStyle.Colors.text3), lineWidth: OPSStyle.Layout.Border.standard)
            y += OPSStyle.Layout.spacing3
        }
    }
}
