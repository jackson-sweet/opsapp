import CoreGraphics
import OPSDesignKit
import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

public struct HouseElevationViewModel: Equatable {
    public struct Face: Equatable, Identifiable {
        public var id: String { edgeId }
        public var edgeId: String
        public var label: String
        public var elevation: HouseElevationProjector.Elevation

        public init(
            edgeId: String,
            label: String,
            elevation: HouseElevationProjector.Elevation
        ) {
            self.edgeId = edgeId
            self.label = label
            self.elevation = elevation
        }
    }

    public var faces: [Face]
    public let emptyStateText = "—"

    public var isEmpty: Bool {
        faces.isEmpty
    }

    public init(
        data: DeckDrawingData,
        capabilities: DeckCapabilities = .full
    ) {
        guard capabilities.contains(.houseOpenings) else {
            self.faces = []
            return
        }

        let labelsById = HouseViewLabelFormatter.edgeLabelsById(data)
        self.faces = HouseElevationProjector.projectAllFaces(data)
            .enumerated()
            .map { index, elevation in
                Face(
                    edgeId: elevation.edgeId,
                    label: HouseViewLabelFormatter.faceLabel(
                        edgeId: elevation.edgeId,
                        labelsById: labelsById,
                        index: index
                    ),
                    elevation: elevation
                )
            }
    }
}

public struct HouseElevationView: View {
    private let model: HouseElevationViewModel

    public init(
        data: DeckDrawingData,
        capabilities: DeckCapabilities = .full
    ) {
        self.model = HouseElevationViewModel(data: data, capabilities: capabilities)
    }

    public init(model: HouseElevationViewModel) {
        self.model = model
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            header

            if model.isEmpty {
                emptyState
            } else {
                facesContent
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(panelBackground)
    }

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// HOUSE ELEVATION")
                .font(OPSStyle.Typography.panelTitle)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)

            Text(model.isEmpty ? model.emptyStateText : "\(model.faces.count)")
                .font(OPSStyle.Typography.badgeCake)
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

    private var emptyState: some View {
        Text(model.emptyStateText)
            .font(OPSStyle.Typography.dataValueLg)
            .monospacedDigit()
            .foregroundColor(OPSStyle.Colors.text3)
            .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetStandard * 4)
            .background(OPSStyle.Colors.surfaceInput)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .cornerRadius(OPSStyle.Layout.cardRadius)
    }

    @ViewBuilder
    private var facesContent: some View {
        #if os(iOS)
        TabView {
            ForEach(model.faces) { face in
                elevationPage(face)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard * 8)
        #else
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                ForEach(model.faces) { face in
                    elevationPage(face)
                        .frame(minWidth: OPSStyle.Layout.touchTargetStandard * 8)
                }
            }
            .padding(.bottom, OPSStyle.Layout.spacing2)
        }
        #endif
    }

    private func elevationPage(_ face: HouseElevationViewModel.Face) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text(face.label)
                    .font(OPSStyle.Typography.badgeCake)
                    .foregroundColor(OPSStyle.Colors.text)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(DimensionEngine.formatImperial(face.elevation.wallLengthInches))
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.text2)
                    .lineLimit(1)
            }

            elevationImage(face.elevation)
                .background(OPSStyle.Colors.background)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .cornerRadius(OPSStyle.Layout.cardRadius)
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.surfaceInput)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .stroke(OPSStyle.Colors.nestedBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardRadius)
    }

    private func elevationImage(_ elevation: HouseElevationProjector.Elevation) -> some View {
        GeometryReader { proxy in
            let imageSize = CGSize(
                width: max(proxy.size.width, OPSStyle.Layout.touchTargetStandard),
                height: max(proxy.size.height, OPSStyle.Layout.touchTargetStandard)
            )

            renderedImage(elevation, size: imageSize)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minHeight: OPSStyle.Layout.touchTargetStandard * 6)
    }

    private func renderedImage(
        _ elevation: HouseElevationProjector.Elevation,
        size: CGSize
    ) -> Image {
        #if canImport(UIKit)
        return Image(uiImage: HouseElevationRenderer.render(elevation, size: size))
        #elseif canImport(AppKit)
        return Image(nsImage: HouseElevationRenderer.render(elevation, size: size))
        #else
        return Image(systemName: "ruler")
        #endif
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

enum HouseViewLabelFormatter {
    static func edgeLabelsById(_ data: DeckDrawingData) -> [String: String] {
        var labels: [String: String] = [:]
        for edge in data.edges {
            labels[edge.id] = edge.label
        }
        for level in data.levels {
            for edge in level.edges {
                labels[edge.id] = edge.label
            }
        }
        return labels
    }

    static func faceLabel(
        edgeId: String,
        labelsById: [String: String],
        index: Int
    ) -> String {
        let trimmed = labelsById[edgeId]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed.uppercased()
        }
        return "FACE \(index + 1)"
    }

    static func scheduleEdgeLabel(
        edgeId: String,
        labelsById: [String: String]
    ) -> String {
        let trimmed = labelsById[edgeId]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            return trimmed.uppercased()
        }
        return edgeId.uppercased()
    }
}
