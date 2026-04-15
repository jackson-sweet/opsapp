//
//  DeckTabView.swift
//  OPS
//
//  Deck tab for project details. Shows 3D/2D interactive model of the
//  project's deck design, or an empty state with CTA to create one.
//

import SwiftUI
import SwiftData

enum DeckTabViewMode: String {
    case threeD = "3D"
    case twoD = "2D"
}

struct DeckTabView: View {
    let project: Project
    let onCreateDeckDesign: () -> Void
    let onEditDeckDesign: (DeckDesign) -> Void

    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var viewMode: DeckTabViewMode = .threeD
    @State private var deckDesign: DeckDesign?
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if !hasLoaded {
                Color.clear
            } else if let design = deckDesign, hasVertices(design) {
                designViewer(design: design)
            } else {
                emptyState
            }
        }
        .onAppear { loadDesign() }
        .onChange(of: project.id) { _, _ in loadDesign() }
    }

    // MARK: - Design Viewer

    private func designViewer(design: DeckDesign) -> some View {
        VStack(spacing: 0) {
            controlBar(design: design)

            Group {
                switch viewMode {
                case .threeD:
                    if design.drawingData.isClosed {
                        DeckTab3DView(drawingData: design.drawingData)
                    } else {
                        incompleteDesignMessage
                    }
                case .twoD:
                    DeckTab2DView(drawingData: design.drawingData)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(OPSStyle.Animation.fast, value: viewMode)

            infoBar(design: design)
        }
    }

    // MARK: - Control Bar

    private func controlBar(design: DeckDesign) -> some View {
        HStack {
            SegmentedControl(
                selection: $viewMode,
                options: [
                    (DeckTabViewMode.threeD, "3D"),
                    (DeckTabViewMode.twoD, "2D")
                ]
            )
            .frame(width: 120)
            .onChange(of: viewMode) { _, _ in
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }

            Spacer()

            if permissionStore.can("deck_builder.edit") {
                Button {
                    onEditDeckDesign(design)
                } label: {
                    Text("EDIT DESIGN")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Info Bar

    private func infoBar(design: DeckDesign) -> some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorderSubtle)
                .frame(height: 1)

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(design.title)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    HStack(spacing: 12) {
                        if let area = computeArea(design: design) {
                            Text(area)
                                .font(OPSStyle.Typography.cardBody)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }

                        let edgeCount = design.drawingData.isMultiLevel
                            ? (design.drawingData.levels.first?.edges.count ?? 0)
                            : design.drawingData.edges.count
                        Text("\(edgeCount) edges")
                            .font(OPSStyle.Typography.cardBody)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        if let elevation = design.drawingData.overallElevation {
                            Text(String(format: "%.1f ft", elevation))
                                .font(OPSStyle.Typography.cardBody)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: "cube.transparent")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.wizardAccent)

                    Text("DECK DESIGN")
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, 16)

                Text("Create a deck design to visualize your build, generate estimates, and share with clients.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
                    .padding(.bottom, 24)

                if permissionStore.can("deck_builder.create") {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onCreateDeckDesign()
                    } label: {
                        HStack {
                            Text("CREATE DECK DESIGN")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.buttonText)

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.buttonText)
                        }
                        .padding(.horizontal, 20)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.wizardAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
            .padding(28)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
            )
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .padding(.horizontal, 20)

            Spacer()
        }
    }

    // MARK: - Incomplete Design Message

    private var incompleteDesignMessage: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "square.dashed")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("CLOSE THE POLYGON TO SEE THE 3D MODEL")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(1)
            Text("Switch to 2D to see the current design")
                .font(OPSStyle.Typography.cardBody)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func loadDesign() {
        let projectId = project.id
        let descriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate { $0.projectId == projectId && $0.deletedAt == nil },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        deckDesign = try? modelContext.fetch(descriptor).first
        hasLoaded = true

        // Debug: log what we found
        if let d = deckDesign {
            let dd = d.drawingData
            print("[DECK_TAB] Found design '\(d.title)' for project \(projectId)")
            print("[DECK_TAB] scaleFactor: \(dd.scaleFactor ?? -1)")
            print("[DECK_TAB] vertices: \(dd.vertices.count), edges: \(dd.edges.count)")
            print("[DECK_TAB] isClosed: \(dd.isClosed), isMultiLevel: \(dd.isMultiLevel)")
            if dd.isMultiLevel {
                for (i, level) in dd.levels.enumerated() {
                    print("[DECK_TAB] level[\(i)] '\(level.name)': \(level.vertices.count) verts, \(level.edges.count) edges, closed: \(level.isClosed)")
                }
            }
            if !dd.vertices.isEmpty {
                let positions = dd.vertices.map(\.position)
                let xs = positions.map(\.x)
                let ys = positions.map(\.y)
                print("[DECK_TAB] vertex X range: \(xs.min()!) .. \(xs.max()!)")
                print("[DECK_TAB] vertex Y range: \(ys.min()!) .. \(ys.max()!)")
            }
            print("[DECK_TAB] hasVertices: \(hasVertices(d))")
        } else {
            print("[DECK_TAB] No design found for project \(projectId)")
        }
    }

    private func hasVertices(_ design: DeckDesign) -> Bool {
        if design.drawingData.isMultiLevel {
            return design.drawingData.levels.contains(where: { !$0.vertices.isEmpty })
        }
        return !design.drawingData.vertices.isEmpty
    }

    private func computeArea(design: DeckDesign) -> String? {
        let positions = design.drawingData.isMultiLevel
            ? (design.drawingData.levels.first?.orderedPositions ?? [])
            : design.drawingData.orderedPositions

        guard positions.count >= 3,
              let scale = design.drawingData.scaleFactor, scale > 0 else { return nil }

        // Shoelace formula for polygon area
        var sum: CGFloat = 0
        for i in 0..<positions.count {
            let j = (i + 1) % positions.count
            sum += positions[i].x * positions[j].y
            sum -= positions[j].x * positions[i].y
        }
        let areaPoints = abs(sum) / 2
        let inchesPerPoint = 1.0 / scale
        let areaInches = areaPoints * inchesPerPoint * inchesPerPoint
        let areaFt = areaInches / 144.0

        return String(format: "%.0f ft²", areaFt)
    }
}
