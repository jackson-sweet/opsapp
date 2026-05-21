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
    @State private var remoteFetchAttemptedProjectId: String?

    // Bug 4 fix: use @Query so SwiftData automatically invalidates this view
    // when a DeckDesign is inserted/updated for this project — no manual
    // loadDesign() or onAppear dance needed. The previous @State + loadDesign()
    // pattern missed the case where DeckBuilderView saves and dismisses while
    // ProjectDetailsView stays alive, leaving the deck tab stale until the
    // user navigated away and back.
    @Query private var allDesigns: [DeckDesign]

    /// Most-recently-updated non-deleted design for this project.
    private var deckDesign: DeckDesign? {
        DeckDesign.displayCandidate(in: allDesigns, forProjectId: project.id)
    }

    var body: some View {
        Group {
            if let design = deckDesign, design.hasRenderableGeometry {
                designViewer(design: design)
            } else {
                emptyState
            }
        }
        .task(id: project.id) {
            await fetchRemoteDeckDesignIfNeeded()
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
                    // `hasAnyClosedSurface` rather than `isClosed` — the latter
                    // requires a single Hamiltonian cycle (false for two
                    // disjoint deck footprints, false for any multi-level
                    // design where the top-level vertices/edges arrays are
                    // empty). `hasAnyClosedSurface` returns true as soon as
                    // any face is closed on any level. Bug ee787f29 follow-up.
                    if design.drawingData.hasAnyClosedSurface {
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
            // viewport with surface metadata below it. Replaces the previous
            // bottom infoBar so the viewport owns its identifying chrome.
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

    /// Title and surface metadata anchored to the top-leading corner of the
    /// rendering viewport.
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

            // Surface stats only, rendered as plain metadata rather than
            // chips. Edges/posts are construction metadata and were removed
            // from this project-detail viewer per bug 38c8c58c.
            HStack(spacing: 8) {
                if let area = computeArea(design: design) {
                    metadataText(area)
                }

                // Level count — only when there's more than one. Helps
                // the user spot multi-level designs at a glance.
                if design.drawingData.isMultiLevel, design.drawingData.levels.count > 1 {
                    metadataText("\(design.drawingData.levels.count) levels")
                }

                if let elevation = design.drawingData.overallElevation {
                    metadataText(String(format: "%.1f ft", elevation))
                }
            }
        }
    }

    private func metadataText(_ value: String) -> some View {
        Text(value.uppercased())
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(OPSStyle.Colors.secondaryText)
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

            if permissionStore.can("deck_builder.edit", requiredScope: "assigned") {
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

                if permissionStore.can("deck_builder.create", requiredScope: "assigned") {
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

    private func computeArea(design: DeckDesign) -> String? {
        guard let scale = design.drawingData.scaleFactor, scale > 0 else { return nil }
        let totalAreaFt = design.drawingData.totalRealWorldArea(scaleFactor: scale) / 144.0
        guard totalAreaFt > 0 else { return nil }
        return String(format: "%.0f ft²", totalAreaFt)
    }

    @MainActor
    private func fetchRemoteDeckDesignIfNeeded() async {
        guard deckDesign?.hasRenderableGeometry != true else { return }
        guard remoteFetchAttemptedProjectId != project.id else { return }
        guard let companyId = effectiveCompanyId else {
            print("[DeckTabView] Skipping deck design repair fetch — no company id")
            return
        }

        remoteFetchAttemptedProjectId = project.id

        do {
            let dtos = try await DeckDesignRepository(companyId: companyId)
                .fetchForProject(DeckDesign.canonicalUUIDString(project.id))
            guard !dtos.isEmpty else { return }

            try mergeRemoteDeckDesigns(dtos)
            print("[DeckTabView] Repaired \(dtos.count) deck design(s) for project \(project.id)")
        } catch {
            print("[DeckTabView] Deck design repair fetch failed for project \(project.id): \(error)")
        }
    }

    private var effectiveCompanyId: String? {
        [
            project.companyId,
            dataController.currentUser?.companyId,
            UserDefaults.standard.string(forKey: "currentUserCompanyId"),
            UserDefaults.standard.string(forKey: "company_id")
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    @MainActor
    private func mergeRemoteDeckDesigns(_ dtos: [SupabaseDeckDesignDTO]) throws {
        for dto in dtos {
            let pendingFields = pendingDeckFields(for: dto.id)
            let acceptedFields = Set(DeckDesign.serverMergeFields).subtracting(pendingFields)

            if let existing = try localDeckDesign(matching: dto.id) {
                existing.applyServerSnapshot(dto, accepting: acceptedFields)
                existing.lastSyncedAt = Date()
                existing.needsSync = !pendingFields.isEmpty
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }

        try modelContext.save()
    }

    @MainActor
    private func localDeckDesign(matching id: String) throws -> DeckDesign? {
        let canonicalId = DeckDesign.canonicalUUIDString(id)
        let lowercasedId = canonicalId.lowercased()
        let uppercasedId = canonicalId.uppercased()
        let exactDescriptor = FetchDescriptor<DeckDesign>(
            predicate: #Predicate {
                $0.id == canonicalId || $0.id == lowercasedId || $0.id == uppercasedId
            }
        )

        if let exactMatch = try modelContext.fetch(exactDescriptor).first {
            return exactMatch
        }

        let allDescriptor = FetchDescriptor<DeckDesign>()
        return try modelContext.fetch(allDescriptor).first {
            DeckDesign.canonicalUUIDString($0.id) == canonicalId
        }
    }

    @MainActor
    private func pendingDeckFields(for id: String) -> Set<String> {
        let entityType = SyncEntityType.deckDesign.rawValue
        let canonicalId = DeckDesign.canonicalUUIDString(id)
        let lowercasedId = canonicalId.lowercased()
        let uppercasedId = canonicalId.uppercased()
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate {
                $0.entityType == entityType &&
                ($0.entityId == canonicalId || $0.entityId == lowercasedId || $0.entityId == uppercasedId) &&
                $0.status == "pending"
            }
        )

        guard let operations = try? modelContext.fetch(descriptor) else { return [] }

        var fields = Set<String>()
        for operation in operations {
            fields.formUnion(operation.getChangedFields())
        }
        return fields
    }
}
