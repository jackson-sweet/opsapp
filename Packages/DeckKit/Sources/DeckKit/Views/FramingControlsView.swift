import SwiftUI

public struct FramingControlsView: View {
    private let framing: FramingPlan?
    private let loadPreset: LoadPreset
    private let selectedGroundCover: GroundCover
    private let framingNeedsRegeneration: Bool
    private let canGenerateFrame: Bool
    private let canPickGround: Bool
    @Binding private var layerVisibility: FramingLayer
    private let onGenerateFrame: () -> Void
    private let onLoadPresetChange: (LoadPreset) -> Void
    private let onGroundCoverChange: (GroundCover) -> Void

    public init(
        framing: FramingPlan?,
        loadPreset: LoadPreset,
        selectedGroundCover: GroundCover,
        framingNeedsRegeneration: Bool,
        canGenerateFrame: Bool,
        canPickGround: Bool,
        layerVisibility: Binding<FramingLayer>,
        onGenerateFrame: @escaping () -> Void,
        onLoadPresetChange: @escaping (LoadPreset) -> Void,
        onGroundCoverChange: @escaping (GroundCover) -> Void
    ) {
        self.framing = framing
        self.loadPreset = loadPreset
        self.selectedGroundCover = selectedGroundCover
        self.framingNeedsRegeneration = framingNeedsRegeneration
        self.canGenerateFrame = canGenerateFrame
        self.canPickGround = canPickGround
        self._layerVisibility = layerVisibility
        self.onGenerateFrame = onGenerateFrame
        self.onLoadPresetChange = onLoadPresetChange
        self.onGroundCoverChange = onGroundCoverChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            header

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if canGenerateFrame {
                    generateButton
                }
                loadMenu
                speciesMenu
                gradeMenu
                if canPickGround {
                    groundMenu
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if framing != nil {
                layerToggleBar
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.glassApprox)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.glassBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        )
        .animation(OPSStyle.Animation.panel, value: framing != nil)
        .animation(OPSStyle.Animation.hover, value: framingNeedsRegeneration)
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// FRAMING")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)

            statusBadge

            Spacer(minLength: 0)

            Text(assumptionSummary)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text2)
                .lineLimit(1)
        }
    }

    private var statusBadge: some View {
        Text(statusLabel)
            .font(OPSStyle.Typography.badgeCake)
            .foregroundColor(statusColor)
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.chipMinHeight)
            .background(statusFill)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(statusLine, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.chipRadius)
    }

    private var generateButton: some View {
        Button {
            onGenerateFrame()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: "hammer")
                    .font(OPSStyle.Typography.metadata)
                Text(generateButtonLabel)
                    .font(OPSStyle.Typography.buttonLabel)
                    .lineLimit(2)
            }
            .foregroundColor(OPSStyle.Colors.background)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.opsAccent)
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
        .buttonStyle(.plain)
    }

    private var loadMenu: some View {
        Menu {
            ForEach(LoadOption.allCases) { option in
                Button(option.label) {
                    var next = loadPreset
                    next.liveLoadPSF = option.liveLoadPSF
                    next.deadLoadPSF = option.deadLoadPSF
                    next.snowLoadPSF = option.snowLoadPSF
                    onLoadPresetChange(next)
                }
            }
        } label: {
            chip(label: "LOAD", value: loadLabel(loadPreset), icon: "gauge.with.dots.needle.67percent")
        }
    }

    private var speciesMenu: some View {
        Menu {
            ForEach(WoodSpecies.allCases, id: \.rawValue) { species in
                Button(species.displayLabel) {
                    var next = loadPreset
                    next.species = species
                    onLoadPresetChange(next)
                }
            }
        } label: {
            chip(label: "SPECIES", value: loadPreset.species.displayLabel, icon: "tree")
        }
    }

    private var gradeMenu: some View {
        Menu {
            ForEach(LumberGrade.allCases, id: \.rawValue) { grade in
                Button(grade.displayLabel) {
                    var next = loadPreset
                    next.grade = grade
                    onLoadPresetChange(next)
                }
            }
        } label: {
            chip(label: "GRADE", value: loadPreset.grade.displayLabel, icon: "number")
        }
    }

    private var groundMenu: some View {
        Menu {
            ForEach(GroundCover.allCases, id: \.rawValue) { cover in
                Button(cover.displayLabel) {
                    onGroundCoverChange(cover)
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                groundSwatch(selectedGroundCover)
                chipText(label: "GROUND", value: selectedGroundCover.displayLabel)
            }
            .padding(.horizontal, OPSStyle.Layout.spacing2)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
    }

    private var layerToggleBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(FramingLayer.displayOrder, id: \.rawValue) { layer in
                    Button {
                        toggleLayer(layer)
                    } label: {
                        Text(layer.displayLabel)
                            .font(OPSStyle.Typography.badgeCake)
                            .foregroundColor(layerVisibility.contains(layer) ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                            .background(layerVisibility.contains(layer) ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .stroke(
                                        layerVisibility.contains(layer) ? OPSStyle.Colors.line : OPSStyle.Colors.nestedBorder,
                                        lineWidth: OPSStyle.Layout.Border.standard
                                    )
                            )
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func chip(label: String, value: String, icon: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            chipText(label: label, value: value)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.buttonRadius)
    }

    private func chipText(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .lineLimit(1)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(1)
        }
    }

    private func groundSwatch(_ cover: GroundCover) -> some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
            .fill(cover.swatchColor)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
    }

    private func toggleLayer(_ layer: FramingLayer) {
        if layerVisibility.contains(layer) {
            layerVisibility.remove(layer)
        } else {
            layerVisibility.insert(layer)
        }
    }

    private var statusLabel: String {
        guard framing != nil else { return "NO FRAME" }
        return framingNeedsRegeneration ? "STALE" : "READY"
    }

    private var statusColor: Color {
        guard framing != nil else { return OPSStyle.Colors.text3 }
        return framingNeedsRegeneration ? OPSStyle.Colors.tanTextM : OPSStyle.Colors.oliveTextM
    }

    private var statusFill: Color {
        guard framing != nil else { return OPSStyle.Colors.fillNeutralDim }
        return framingNeedsRegeneration ? OPSStyle.Colors.tanFillM : OPSStyle.Colors.oliveFillM
    }

    private var statusLine: Color {
        guard framing != nil else { return OPSStyle.Colors.nestedBorder }
        return framingNeedsRegeneration ? OPSStyle.Colors.tanLineM : OPSStyle.Colors.oliveLineM
    }

    private var generateButtonLabel: String {
        framing == nil ? "GENERATE FRAMING" : "REGENERATE FRAME"
    }

    private var assumptionSummary: String {
        "\(loadPreset.species.displayLabel) · \(loadPreset.grade.displayLabel) · \(loadLabel(loadPreset))"
    }

    private func loadLabel(_ preset: LoadPreset) -> String {
        let base = "\(Int(preset.liveLoadPSF))/\(Int(preset.deadLoadPSF)) PSF"
        guard let snow = preset.snowLoadPSF else { return base }
        return "\(base) · SNOW \(Int(snow))"
    }
}

private enum LoadOption: CaseIterable, Identifiable {
    case standard
    case heavy
    case snow

    var id: Self { self }

    var liveLoadPSF: Double {
        switch self {
        case .standard, .snow:
            return 40
        case .heavy:
            return 60
        }
    }

    var deadLoadPSF: Double {
        switch self {
        case .standard, .snow:
            return 10
        case .heavy:
            return 15
        }
    }

    var snowLoadPSF: Double? {
        switch self {
        case .standard, .heavy:
            return nil
        case .snow:
            return 40
        }
    }

    var label: String {
        switch self {
        case .standard:
            return "STANDARD 40/10 PSF"
        case .heavy:
            return "HEAVY 60/15 PSF"
        case .snow:
            return "SNOW 40/10 PSF · SNOW 40"
        }
    }
}

private extension FramingLayer {
    var displayLabel: String {
        switch self {
        case .decking:
            return "DECKING"
        case .joists:
            return "JOISTS"
        case .beams:
            return "BEAMS"
        case .posts:
            return "POSTS"
        case .footings:
            return "FOOTINGS"
        case .rim:
            return "RIM"
        case .blocking:
            return "BLOCKING"
        default:
            return "LAYER"
        }
    }
}

private extension WoodSpecies {
    var displayLabel: String {
        switch self {
        case .southernPine:
            return "SYP"
        case .douglasFirLarch:
            return "DF-L"
        case .hemFir:
            return "HEM-FIR"
        case .sprucePineFir:
            return "SPF"
        case .redwoodCedar:
            return "REDWOOD/CEDAR"
        }
    }
}

private extension LumberGrade {
    var displayLabel: String {
        switch self {
        case .select:
            return "SELECT"
        case .no1:
            return "NO. 1"
        case .no2:
            return "NO. 2"
        }
    }
}

private extension GroundCover {
    var displayLabel: String {
        switch self {
        case .grass:
            return "GRASS"
        case .dirt:
            return "DIRT"
        case .gravel:
            return "GRAVEL"
        case .rock:
            return "ROCK"
        case .concrete:
            return "CONCRETE"
        case .pavers:
            return "PAVERS"
        }
    }

    var swatchColor: Color {
        switch self {
        case .grass:
            return OPSStyle.Colors.olive
        case .dirt:
            return OPSStyle.Colors.tan
        case .gravel:
            return OPSStyle.Colors.text3
        case .rock:
            return OPSStyle.Colors.textMute
        case .concrete:
            return OPSStyle.Colors.text2
        case .pavers:
            return OPSStyle.Colors.tanTextM
        }
    }
}
