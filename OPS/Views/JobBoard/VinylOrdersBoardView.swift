//
//  VinylOrdersBoardView.swift
//  OPS
//
//  The VINYL ORDERS board — a cross-project vinyl procurement console
//  presented from the Job Board's VINYL pill (spec 2026-07-16). One scrolling
//  list, two groups: // TO ORDER (soonest crew need first) and // ORDERED
//  (latest first). Rows are scan surfaces — glance state only; details,
//  actions, and the click-through live behind tap-to-expand. SELECT mode adds
//  checkboxes on TO ORDER rows and a bottom action bar with bulk MARK ORDERED
//  and the one-job-at-a-time ORDER wizard.
//
//  Glance data is marker-driven (ProjectVinylOrderMarker + the vinyl_color /
//  vinyl_po projections) — zero geometry work at list render. Materials
//  resolve lazily on expand and at commit time.
//

import SwiftData
import SwiftUI
import UIKit

struct VinylOrdersBoardView: View {
    /// Preview/proof seam: when set, list assembly bypasses the live queries
    /// (offscreen render harnesses cannot drive @Query). nil in production —
    /// the Job Board presents this view with no arguments.
    private let fixedInputs: [VinylBoardRowInput]?

    init(fixedInputs: [VinylBoardRowInput]? = nil, initiallyExpanded: Set<String> = []) {
        self.fixedInputs = fixedInputs
        _expandedProjectIds = State(initialValue: initiallyExpanded)
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var appState: AppState

    @Query private var allProjects: [Project]
    @Query private var taskTypes: [TaskType]
    @Query private var vinylOrderMarkers: [ProjectVinylOrderMarker]
    @Query private var deckDesigns: [DeckDesign]

    @State private var expandedProjectIds: Set<String> = []
    @State private var selectionMode = false
    @State private var selectedProjectIds: Set<String> = []
    @State private var isCommitting = false
    @State private var showingMarkConfirm = false
    @State private var clearTarget: VinylBoardRowInput?
    @State private var resultBanner: VinylBoardResultBanner?
    @State private var retryItems: [VinylBulkMarkItem] = []
    @State private var wizardContext: VinylBulkOrderWizardContext?
    /// Memoized frozen snapshots keyed by design id + updatedAt so expanded
    /// rows never re-decode drawing JSON on every body pass.
    @State private var snapshotCache: [String: DeckMaterialsSnapshot?] = [:]

    private var companyId: String? { dataController.currentUser?.companyId }

    /// The signed-in operator's users.id — same uuid discipline as the order
    /// sheet (never a Firebase UID).
    private var currentUserId: String? {
        dataController.currentUser?.id.lowercased()
    }

    private var canMark: Bool {
        permissionStore.can("projects.edit")
    }

    /// ORDER wizard gate — parity with the single-project order sheet.
    private var canRunOrderWizard: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
            && permissionStore.can("deck_builder.view", requiredScope: "assigned")
            && permissionStore.can("projects.edit")
    }

    private var vinylTaskTypeIds: Set<String> {
        guard let companyId else { return [] }
        let displaysById = Dictionary(
            taskTypes
                .filter { $0.companyId == companyId && $0.deletedAt == nil }
                .map { ($0.id, $0.display) },
            uniquingKeysWith: { first, _ in first }
        )
        return VinylTaskFilter.vinylTaskTypeIds(displaysById: displaysById)
    }

    private var markersByProjectId: [String: ProjectVinylOrderMarker] {
        Dictionary(vinylOrderMarkers.map { ($0.projectId, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Plain inputs for the pure board model — markers + task facts only.
    private var boardInputs: [VinylBoardRowInput] {
        if let fixedInputs { return fixedInputs }
        let vinylIds = vinylTaskTypeIds
        guard !vinylIds.isEmpty else { return [] }
        let markers = markersByProjectId

        return allProjects
            .filter { $0.deletedAt == nil }
            .map { project in
                let incompleteVinylTasks = project.tasks.filter { task in
                    task.deletedAt == nil
                        && task.status != .completed
                        && vinylIds.contains(task.taskTypeId)
                }
                let marker = markers[project.id]
                return VinylBoardRowInput(
                    projectId: project.id,
                    title: project.title,
                    status: project.status,
                    vinylTaskStartDates: incompleteVinylTasks.map(\.startDate),
                    hasIncompleteVinylTask: !incompleteVinylTasks.isEmpty,
                    createdAt: project.createdAt,
                    ordered: marker?.isOrdered ?? false,
                    orderedAt: marker?.orderedAt
                )
            }
    }

    private var rows: (toOrder: [VinylBoardRowInput], ordered: [VinylBoardRowInput]) {
        VinylOrdersBoardModel.rows(from: boardInputs)
    }

    /// Selected TO ORDER rows in board order — the bulk actions' job list.
    private var selectedRows: [VinylBoardRowInput] {
        rows.toOrder.filter { selectedProjectIds.contains($0.projectId) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                let grouped = rows
                if grouped.toOrder.isEmpty && grouped.ordered.isEmpty {
                    emptyBoard
                } else {
                    boardList(grouped)
                }

                VStack {
                    Spacer()
                    if selectionMode && !selectedRows.isEmpty {
                        selectionActionBar
                    }
                }
            }
            .navigationTitle("VINYL ORDERS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !rows.toOrder.isEmpty && canMark {
                        Button(selectionMode ? "DONE" : "SELECT") {
                            withAnimation(OPSStyle.Animation.panel) {
                                selectionMode.toggle()
                                if !selectionMode { selectedProjectIds.removeAll() }
                            }
                        }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("CLOSE") { dismiss() }
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .confirmationDialog(
                "MARK \(selectedRows.count) ORDERED?",
                isPresented: $showingMarkConfirm,
                titleVisibility: .visible
            ) {
                Button("MARK ORDERED") { runBulkMark(items: assembleItems(for: selectedRows)) }
                Button("CANCEL", role: .cancel) {}
            } message: {
                Text("STAMPS TODAY'S DATE ON EVERY SELECTED JOB.")
            }
            .confirmationDialog(
                "CLEAR ORDERED?",
                isPresented: Binding(
                    get: { clearTarget != nil },
                    set: { if !$0 { clearTarget = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("CLEAR ORDERED", role: .destructive) {
                    if let target = clearTarget { runClearOrdered(target) }
                }
                Button("CANCEL", role: .cancel) {}
            } message: {
                Text("REMOVES THE ORDER RECORD. THE DESIGN IS UNTOUCHED.")
            }
            .sheet(item: $wizardContext) { context in
                VinylBulkOrderWizardView(
                    context: context,
                    onCommitted: { outcome, failedItems in
                        wizardContext = nil
                        retryItems = failedItems
                        if outcome.failed.isEmpty {
                            selectionMode = false
                            selectedProjectIds.removeAll()
                        }
                        presentOutcome(outcome, verb: "MARKED", orderSent: true)
                    }
                )
                .environmentObject(dataController)
            }
        }
    }

    // MARK: - List

    private func boardList(_ grouped: (toOrder: [VinylBoardRowInput], ordered: [VinylBoardRowInput])) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                if let banner = resultBanner {
                    resultBannerView(banner)
                }

                boardSection(title: "TO ORDER") {
                    if grouped.toOrder.isEmpty {
                        Text("ALL VINYL ORDERED")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, OPSStyle.Layout.spacing2)
                    } else {
                        rowStack(grouped.toOrder, selectable: true)
                    }
                }

                if !grouped.ordered.isEmpty {
                    boardSection(title: "ORDERED") {
                        rowStack(grouped.ordered, selectable: false)
                    }
                }

                Color.clear.frame(height: OPSStyle.Layout.touchTargetLarge * 2)
            }
            .padding(OPSStyle.Layout.spacing3)
        }
    }

    private func rowStack(_ inputs: [VinylBoardRowInput], selectable: Bool) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(inputs.enumerated()), id: \.element.projectId) { index, input in
                VStack(spacing: 0) {
                    glanceRow(input, selectable: selectable)
                    if expandedProjectIds.contains(input.projectId) {
                        VinylOrderRowDetail(
                            input: input,
                            project: project(for: input.projectId),
                            marker: markersByProjectId[input.projectId],
                            snapshot: frozenSnapshot(for: input.projectId),
                            onOpenProject: { openProject(input.projectId) },
                            onClearOrdered: input.ordered ? { clearTarget = input } : nil
                        )
                    }
                }
                if index < inputs.count - 1 {
                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: OPSStyle.Layout.Border.standard)
                }
            }
        }
    }

    private func glanceRow(_ input: VinylBoardRowInput, selectable: Bool) -> some View {
        Button {
            if selectionMode && selectable {
                toggleSelection(input.projectId)
            } else {
                toggleExpansion(input.projectId)
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if selectionMode && selectable {
                    Image(systemName: selectedProjectIds.contains(input.projectId) ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                Circle()
                    .fill(input.ordered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
                    .frame(width: OPSStyle.Layout.spacing2, height: OPSStyle.Layout.spacing2)

                Text(input.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: OPSStyle.Layout.spacing2)

                Text(statusLabel(for: input))
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(input.ordered ? OPSStyle.Colors.successStatus : OPSStyle.Colors.secondaryText)
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func statusLabel(for input: VinylBoardRowInput) -> String {
        guard input.ordered else { return "NOT ORDERED" }
        if let orderedAt = input.orderedAt {
            return "ORDERED \(DateHelper.simpleDateString(from: orderedAt).uppercased())"
        }
        return "ORDERED"
    }

    private func boardSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(title)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            content()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var emptyBoard: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO ACTIVE VINYL WORK")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.1)
            Text("JOBS WITH A VINYL TASK LAND HERE.")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Selection + bulk actions

    private var selectionActionBar: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                showingMarkConfirm = true
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    if isCommitting {
                        ProgressView().tint(OPSStyle.Colors.primaryText)
                    }
                    Text("MARK ORDERED (\(selectedRows.count))")
                        .font(OPSStyle.Typography.buttonLabel)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(.plain)
            .disabled(isCommitting || currentUserId == nil)

            if canRunOrderWizard {
                Button {
                    startOrderWizard()
                } label: {
                    Text("ORDER (\(selectedRows.count))")
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.background)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.primaryAccent)
                        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                }
                .buttonStyle(.plain)
                .disabled(isCommitting || currentUserId == nil)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background.opacity(0.96))
    }

    private func toggleSelection(_ projectId: String) {
        if selectedProjectIds.contains(projectId) {
            selectedProjectIds.remove(projectId)
        } else {
            selectedProjectIds.insert(projectId)
        }
    }

    private func toggleExpansion(_ projectId: String) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(OPSStyle.Animation.panel) {
            if expandedProjectIds.contains(projectId) {
                expandedProjectIds.remove(projectId)
            } else {
                expandedProjectIds.insert(projectId)
            }
        }
    }

    // MARK: - Result banner

    private func resultBannerView(_ banner: VinylBoardResultBanner) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: banner.failedCount == 0 ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
            Text(banner.text)
                .font(OPSStyle.Typography.captionBold)
                .tracking(0.8)
            Spacer(minLength: 0)
            if banner.failedCount > 0 && !retryItems.isEmpty {
                Button("RETRY") {
                    runBulkMark(items: retryItems)
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .buttonStyle(.plain)
            }
        }
        .foregroundColor(banner.failedCount == 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus)
        .padding(OPSStyle.Layout.spacing2)
        .background((banner.failedCount == 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus).opacity(0.10))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(
                    (banner.failedCount == 0 ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus).opacity(0.45),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
    }

    // MARK: - Data plumbing

    private func project(for projectId: String) -> Project? {
        allProjects.first { $0.id == projectId }
    }

    /// Display-candidate design for a project, or nil when none exists.
    private func displayDesign(for projectId: String) -> DeckDesign? {
        DeckDesign.displayCandidate(in: deckDesigns, forProjectId: projectId)
    }

    /// Frozen order snapshot for an expanded row, memoized per design revision.
    private func frozenSnapshot(for projectId: String) -> DeckMaterialsSnapshot? {
        guard let design = displayDesign(for: projectId) else { return nil }
        let key = "\(design.id)|\(design.updatedAt?.timeIntervalSince1970 ?? 0)"
        if let cached = snapshotCache[key] { return cached }
        let snapshot = design.drawingData.orderedMaterials
        DispatchQueue.main.async { snapshotCache[key] = snapshot }
        return snapshot
    }

    private func openProject(_ projectId: String) {
        dismiss()
        appState.viewProjectDetailsById(projectId)
    }

    /// Non-deleted task-type display names for a project — the vinyl job
    /// signal source, fetched on demand exactly like the order sheet.
    private func projectTaskTypeDisplays(projectId: String) -> [String] {
        let descriptor = FetchDescriptor<ProjectTask>(
            predicate: #Predicate { $0.projectId == projectId && $0.deletedAt == nil }
        )
        let tasks = (try? modelContext.fetch(descriptor)) ?? []
        return tasks.compactMap { $0.taskType?.display }
    }

    /// productId → vinyl-hint blob for detection rule 3 — mirrors the order
    /// sheet's on-demand build.
    private func vinylHintByProductId() -> [String: String] {
        guard let cid = companyId else { return [:] }
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate { $0.companyId == cid }
        )
        let products = (try? modelContext.fetch(productDescriptor)) ?? []
        let catalogDescriptor = FetchDescriptor<CatalogItem>(
            predicate: #Predicate { $0.companyId == cid && $0.deletedAt == nil }
        )
        let catalogItems = (try? modelContext.fetch(catalogDescriptor)) ?? []
        return DeckVinylHintBuilder.build(products: products, catalogItems: catalogItems)
    }

    /// Assemble bulk-mark items for the plain MARK ORDERED path: full snapshot
    /// where a design resolves materials, marker-only otherwise — with the
    /// design's config-restored color when one exists.
    private func assembleItems(for rowInputs: [VinylBoardRowInput]) -> [VinylBulkMarkItem] {
        let hints = vinylHintByProductId()
        return rowInputs.map { input in
            guard let design = displayDesign(for: input.projectId) else {
                return VinylBulkMarkItem(
                    projectId: input.projectId,
                    design: nil,
                    materials: nil,
                    settings: DeckMaterialsSettings(),
                    vinylSettings: .default,
                    color: nil,
                    po: nil
                )
            }

            let data = design.drawingData
            let configColor = data.config.vinylColor?.trimmingCharacters(in: .whitespacesAndNewlines)
            var vinylSettings = VinylOrderSettings.default
            vinylSettings.color = configColor ?? ""
            vinylSettings.catalogItemId = data.config.vinylCatalogItemId
            vinylSettings.catalogVariantId = data.config.vinylCatalogVariantId
            let materialsSettings = data.materialsSettings ?? DeckMaterialsSettings()

            let resolved = DeckMaterialsResolver.resolve(
                data: data,
                settings: materialsSettings,
                vinylSettings: vinylSettings,
                taskTypeDisplays: projectTaskTypeDisplays(projectId: input.projectId),
                vinylHintByProductId: hints
            )

            return VinylBulkMarkItem(
                projectId: input.projectId,
                design: design,
                materials: resolved.materials,
                settings: materialsSettings,
                vinylSettings: vinylSettings,
                color: (configColor?.isEmpty ?? true) ? nil : configColor,
                po: nil
            )
        }
    }

    private func runBulkMark(items: [VinylBulkMarkItem]) {
        guard let userId = currentUserId, !items.isEmpty else { return }
        isCommitting = true
        resultBanner = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        let service = VinylBulkMarkService(userId: userId) { pid, fields in
            try await dataController.updateProjectFields(projectId: pid, fields: fields)
        }
        let allItems = items
        Task { @MainActor in
            let outcome = await service.markOrdered(items: allItems)
            isCommitting = false
            retryItems = allItems.filter { outcome.failed.contains($0.projectId) }
            if outcome.failed.isEmpty {
                selectionMode = false
                selectedProjectIds.removeAll()
            }
            presentOutcome(outcome, verb: "MARKED", orderSent: false)
        }
    }

    private func runClearOrdered(_ input: VinylBoardRowInput) {
        guard let userId = currentUserId else { return }
        clearTarget = nil
        isCommitting = true
        let design = displayDesign(for: input.projectId)
        let service = DeckMaterialsOrderService(userId: userId) { pid, fields in
            try await dataController.updateProjectFields(projectId: pid, fields: fields)
        }
        Task { @MainActor in
            do {
                try await service.clearOrdered(projectId: input.projectId, design: design)
                snapshotCache.removeAll()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            } catch {
                print("[VinylOrdersBoardView] clearOrdered failed: \(error)")
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isCommitting = false
        }
    }

    private func presentOutcome(_ outcome: VinylBulkMarkOutcome, verb: String, orderSent: Bool) {
        let marked = outcome.succeeded.count
        let failed = outcome.failed.count
        let text: String
        if failed == 0 {
            text = orderSent ? "ORDER SENT · \(marked) \(verb)" : "\(marked) \(verb)"
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } else {
            text = "\(marked) \(verb) · \(failed) FAILED"
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        }
        withAnimation(OPSStyle.Animation.panel) {
            resultBanner = VinylBoardResultBanner(text: text, failedCount: failed)
        }
    }

    // MARK: - Wizard entry

    private func startOrderWizard() {
        guard canRunOrderWizard, let companyId else { return }
        let hints = vinylHintByProductId()

        let jobs = selectedRows.map { input -> VinylBulkOrderJob in
            let project = project(for: input.projectId)
            let title = project?.title ?? input.title
            guard let design = displayDesign(for: input.projectId) else {
                return VinylBulkOrderJob(
                    projectId: input.projectId,
                    title: title,
                    design: nil,
                    resolved: nil,
                    facesByLevel: [],
                    taskTypeDisplays: [],
                    degenerateReason: .noDrawing
                )
            }

            let data = design.drawingData
            let configColor = data.config.vinylColor?.trimmingCharacters(in: .whitespacesAndNewlines)
            var vinylSettings = VinylOrderSettings.default
            vinylSettings.color = configColor ?? ""
            vinylSettings.catalogItemId = data.config.vinylCatalogItemId
            vinylSettings.catalogVariantId = data.config.vinylCatalogVariantId
            let materialsSettings = data.materialsSettings ?? DeckMaterialsSettings()
            let displays = projectTaskTypeDisplays(projectId: input.projectId)

            let resolved = DeckMaterialsResolver.resolve(
                data: data,
                settings: materialsSettings,
                vinylSettings: vinylSettings,
                taskTypeDisplays: displays,
                vinylHintByProductId: hints
            )

            let facesByLevel = data.isMultiLevel
                ? data.levels.map(\.detectedSurfaces)
                : [data.detectedSurfaces]

            let degenerateReason: VinylBulkOrderJob.DegenerateReason?
            if resolved.vinylInputs.isEmpty {
                degenerateReason = .noDrawing
            } else if resolved.scale == nil {
                degenerateReason = .unconfirmedScale
            } else {
                degenerateReason = nil
            }

            return VinylBulkOrderJob(
                projectId: input.projectId,
                title: title,
                design: design,
                resolved: resolved,
                facesByLevel: facesByLevel,
                taskTypeDisplays: displays,
                degenerateReason: degenerateReason
            )
        }

        wizardContext = VinylBulkOrderWizardContext(
            companyId: companyId,
            userId: currentUserId,
            jobs: jobs
        )
    }
}

/// Result banner state for bulk commits.
struct VinylBoardResultBanner: Equatable {
    var text: String
    var failedCount: Int
}

// MARK: - Expanded row detail

/// The order record + project facts behind a tapped row (spec § 4). Snapshot
/// values first, marker color/PO fallback, `—` for empties. Internal (not
/// private) so the snapshot proof harness can render it with fixture data.
struct VinylOrderRowDetail: View {
    let input: VinylBoardRowInput
    let project: Project?
    let marker: ProjectVinylOrderMarker?
    let snapshot: DeckMaterialsSnapshot?
    let onOpenProject: () -> Void
    let onClearOrdered: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            if input.ordered {
                orderRecordRows
            }

            detailRow("CLIENT", project?.effectiveClientName.isEmpty == false ? project!.effectiveClientName : "—")
            detailRow("ADDRESS", project?.address?.isEmpty == false ? project!.address! : "—")

            HStack(spacing: OPSStyle.Layout.spacing2) {
                detailActionButton("OPEN PROJECT", action: onOpenProject)
                if let onClearOrdered {
                    detailActionButton("CLEAR ORDERED", action: onClearOrdered)
                }
            }
            .padding(.top, OPSStyle.Layout.spacing1)
        }
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var orderRecordRows: some View {
        detailRow("ORDERED", input.orderedAt.map { DateHelper.simpleDateString(from: $0).uppercased() } ?? "—")
        detailRow("COLOR", displayColor)
        detailRow("PO", displayPO)

        if let snapshot {
            if snapshot.orderMode == .fullRolls, let rolls = snapshot.orderedRollCount {
                detailRow("ROLLS", "\(rolls) @ \(Int(snapshot.fullRollLengthFeet))'")
            } else {
                detailRow("CUTS", "\(snapshot.vinylOrderedSqFt) SQ FT")
            }
            ForEach(Array(snapshot.cutGroups.enumerated()), id: \.offset) { _, group in
                Text("-\(group.count) @ \(vinylFormatFeetAndInches(group.lengthInches))")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.leading, OPSStyle.Layout.spacing3)
            }
            detailRow("FLASHING + GLUE", flashingSummary(snapshot))
        }
    }

    private var displayColor: String {
        if let snapshotColor = snapshot?.vinylColor, !snapshotColor.isEmpty { return snapshotColor }
        if let markerColor = marker?.vinylColor, !markerColor.isEmpty { return markerColor }
        return "—"
    }

    private var displayPO: String {
        if let snapshotPO = snapshot?.po, !snapshotPO.isEmpty { return snapshotPO }
        if let markerPO = marker?.vinylPO, !markerPO.isEmpty { return markerPO }
        return "—"
    }

    private func flashingSummary(_ snapshot: DeckMaterialsSnapshot) -> String {
        "\(snapshot.dripSticks) DRIP · \(snapshot.ninetySticks) 90 · \(snapshot.clipSticks) CLIP · \(snapshot.glueBuckets) GLUE"
    }

    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(width: OPSStyle.Layout.touchTargetStandard + OPSStyle.Layout.spacing5, alignment: .leading)
            Text(value)
                .font(OPSStyle.Typography.dataValue)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func detailActionButton(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .frame(maxWidth: .infinity)
                .background(OPSStyle.Colors.surfaceHover)
                .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(.plain)
    }
}
