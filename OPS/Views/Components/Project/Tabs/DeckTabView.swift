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

    // Bug 4 fix: use @Query so SwiftData automatically invalidates this view
    // when a DeckDesign is inserted/updated for this project — no manual
    // loadDesign() or onAppear dance needed. The previous @State + loadDesign()
    // pattern missed the case where DeckBuilderView saves and dismisses while
    // ProjectDetailsView stays alive, leaving the deck tab stale until the
    // user navigated away and back.
    @Query private var allDesigns: [DeckDesign]

    /// Most-recently-updated non-deleted design for this project.
    private var deckDesign: DeckDesign? {
        allDesigns
            .filter { $0.projectId == project.id && $0.deletedAt == nil }
            .sorted { ($0.updatedAt ?? .distantPast) > ($1.updatedAt ?? .distantPast) }
            .first
    }

    var body: some View {
        Group {
            if let design = deckDesign, hasVertices(design) {
                designViewer(design: design)
            } else {
                emptyState
            }
        }
    }

    // MARK: - Design Viewer

    private func designViewer(design: DeckDesign) -> some View {
        VStack(spacing: 0) {
            controlBar(design: design)

            // Bug 9327599a — rendering area sits inside ProjectDetailsView's
            // ScrollView/LazyVStack, where maxHeight: .infinity collapses to
            // the children's intrinsic size (GeometryReader and SCNView both
            // expose ~0 intrinsic height). Result: the 2D/3D viewport got a
            // few-point-tall sliver and the drawing rendered "tiny" even
            // after the centerViewport math zoomed it correctly.
            //
            // Fix: lock the rendering area to a 1:1 aspect ratio against the
            // available width — produces a substantial square viewport that
            // scales to fill the screen width and gives both 2D blueprint and
            // 3D scene enough room to read clearly. Horizontal padding gives
            // the requested breathing room from the screen edges.
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
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            // Floating overlay — title pinned top-left of the rendering
            // viewport with material/geometry counts as compact badges in a
            // line below it. Replaces the previous bottom infoBar so the
            // viewport itself owns its identifying chrome.
            .overlay(alignment: .topLeading) {
                floatingDesignInfo(design: design)
                    .padding(.leading, 12)
                    .padding(.top, 12)
                    .allowsHitTesting(false)
            }
            .padding(.horizontal, 16)
            .animation(OPSStyle.Animation.fast, value: viewMode)
        }
    }

    // MARK: - Floating Design Info (overlay top-left of viewport)

    /// Title chip + horizontal row of count badges. Anchored to the
    /// top-leading corner of the rendering viewport so the user sees
    /// "what is this and what's in it" at a glance without losing canvas
    /// real estate to a bottom info bar.
    private func floatingDesignInfo(design: DeckDesign) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title pill — single line, ellipsis on overflow so very long
            // names don't push the badges off the viewport.
            Text(design.title)
                .font(OPSStyle.Typography.cardBody)
                .fontWeight(.semibold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(OPSStyle.Colors.cardBackground.opacity(0.9))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(OPSStyle.Colors.cardBorder.opacity(0.6), lineWidth: 0.5)
                        )
                )

            // Count badges — area, edges, posts, elevation. Each is a
            // self-contained mini-pill so the row reads as discrete chips
            // rather than a sentence.
            HStack(spacing: 4) {
                if let area = computeArea(design: design) {
                    countBadge(icon: "square.dashed", value: area)
                }

                let edgeCount = design.drawingData.isMultiLevel
                    ? (design.drawingData.levels.first?.edges.count ?? 0)
                    : design.drawingData.edges.count
                if edgeCount > 0 {
                    countBadge(icon: "lineweight", value: "\(edgeCount) edges")
                }

                let postCount = design.drawingData.isMultiLevel
                    ? (design.drawingData.levels.first?.vertices.count ?? 0)
                    : design.drawingData.vertices.count
                if postCount > 0 {
                    countBadge(icon: "circle.fill", value: "\(postCount) posts")
                }

                if let elevation = design.drawingData.overallElevation {
                    countBadge(icon: "arrow.up.and.down", value: String(format: "%.1f ft", elevation))
                }
            }
        }
    }

    private func countBadge(icon: String, value: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
        }
        .foregroundColor(OPSStyle.Colors.secondaryText)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(OPSStyle.Colors.cardBorder.opacity(0.5), lineWidth: 0.5)
                )
        )
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
