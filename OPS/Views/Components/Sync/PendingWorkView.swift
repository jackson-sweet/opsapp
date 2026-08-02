//
//  PendingWorkView.swift
//  OPS
//
//  SYNC RECOVERY · T6 — the PENDING WORK recovery screen (spec §4). Two pieces:
//
//    • `PendingWorkView` — a PURE renderable. It takes a built `RecoveryInventory`
//      plus a `PendingWorkActions` closure bundle and nothing else (no engine, no
//      queue, no context), so the whole screen is snapshot-testable from hand-built
//      fixtures. It owns the detail-sheet and link-picker presentation only.
//    • `PendingWorkScreen` — the thin wrapper. It builds the inventory from live
//      SwiftData on a 2s cadence and wires every action to the sync engine, the
//      autocreate queue, the photo processor, and the deck/site-visit surfaces.
//
//  Layout is spec §4 wireframe V4: NEEDS ATTENTION → SENDING → DRAFTS → NOT LINKED,
//  each an L1 glass section shown only when non-empty; a single accent RETRY ALL
//  CTA floats when attention has work. Every value traces to `OPSStyle`; every
//  string to `SyncStatusCopy.PendingWork`.
//

import SwiftUI
import SwiftData

// MARK: - Actions

/// The closure bundle the pure view calls. The wrapper supplies real behaviour;
/// snapshot tests supply `.noop`.
struct PendingWorkActions {
    var retryItem: (RecoveryItem) -> Void
    var retryAll: () -> Void
    var discardItem: (RecoveryItem) -> Void
    var exportItem: (RecoveryItem) -> Void
    var linkDesign: (String, PendingWorkLinkTarget) -> Void
    var openDraft: (DraftSnapshot) -> Void
    var openDesign: (OrphanDesignSnapshot) -> Void
    var dismiss: () -> Void

    /// Inert actions for previews / snapshot tests.
    static let noop = PendingWorkActions(
        retryItem: { _ in }, retryAll: {}, discardItem: { _ in }, exportItem: { _ in },
        linkDesign: { _, _ in }, openDraft: { _ in }, openDesign: { _ in }, dismiss: {}
    )
}

// MARK: - Pure view

struct PendingWorkView: View {
    let inventory: RecoveryInventory
    let actions: PendingWorkActions
    var now: Date = Date()
    /// Real link-target search, injected by the wrapper; a safe empty default
    /// keeps the pure view (and its snapshots) engine-free.
    var searchLinkTargets: (String, PendingWorkLinkScope) async -> [PendingWorkLinkTarget] = { _, _ in [] }

    @State private var detailItem: RecoveryItem?
    @State private var linkingDesign: OrphanDesignSnapshot?

    private var showRetryAll: Bool { inventory.attentionCount > 0 }

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            if inventory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                        section(
                            title: SyncStatusCopy.PendingWork.sectionAttention,
                            count: inventory.attention.count,
                            countColor: OPSStyle.Colors.tan,
                            items: inventory.attention
                        )
                        section(
                            title: SyncStatusCopy.PendingWork.sectionSending,
                            count: inventory.sending.count,
                            countColor: OPSStyle.Colors.text3,
                            items: inventory.sending
                        )
                        section(
                            title: SyncStatusCopy.PendingWork.sectionDrafts,
                            count: inventory.drafts.count,
                            countColor: OPSStyle.Colors.text3,
                            items: inventory.drafts
                        )
                        section(
                            title: SyncStatusCopy.PendingWork.sectionUnlinked,
                            count: inventory.unlinked.count,
                            countColor: OPSStyle.Colors.text3,
                            items: inventory.unlinked
                        )
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3)
                    .padding(.bottom, showRetryAll ? 108 : OPSStyle.Layout.spacing5)
                }

                if showRetryAll {
                    retryAllCTA
                }
            }
        }
        .sheet(item: $detailItem) { item in
            PendingWorkDetailSheet(
                item: item,
                now: now,
                onRetry: { actions.retryItem(item) },
                onExport: { actions.exportItem(item) },
                onDiscard: { actions.discardItem(item) }
            )
        }
        .sheet(item: $linkingDesign) { design in
            PendingWorkLinkPicker(
                searchProvider: searchLinkTargets,
                onSelect: { target in actions.linkDesign(design.id, target) }
            )
        }
    }

    // MARK: - Section

    @ViewBuilder
    private func section(
        title: String,
        count: Int,
        countColor: Color,
        items: [RecoveryItem]
    ) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Text(title)
                        .font(OPSStyle.Typography.metadata)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.text3)
                    Text("· \(count)")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(countColor)
                }

                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider().background(OPSStyle.Colors.lineSoft)
                        }
                        entryView(for: item)
                    }
                }
                .glassSurface()
            }
        }
    }

    @ViewBuilder
    private func entryView(for item: RecoveryItem) -> some View {
        switch item {
        case .bundle(let bundle):
            PendingWorkBundleCard(
                bundle: bundle,
                now: now,
                onTap: { detailItem = item },
                onRetry: { actions.retryItem(item) }
            )
        case .op, .autocreate, .photos:
            PendingWorkEntryRow(
                item: item,
                now: now,
                onTap: { detailItem = item },
                onRetry: { actions.retryItem(item) }
            )
        case .draft(let draft):
            PendingWorkDraftRow(draft: draft, now: now, onOpen: { actions.openDraft(draft) })
        case .orphanDesign(let design):
            PendingWorkOrphanRow(
                design: design,
                now: now,
                onOpen: { actions.openDesign(design) },
                onLink: { linkingDesign = design }
            )
        }
    }

    // MARK: - Floating RETRY ALL (the screen's single accent element · §8)

    private var retryAllCTA: some View {
        Button {
            actions.retryAll()
        } label: {
            Text(SyncStatusCopy.PendingWork.retryAllButton(count: inventory.attentionCount))
                .font(OPSStyle.Typography.buttonLabel)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.invertedText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.bottomCTAHeight)
                .background(OPSStyle.Colors.opsAccent)
                .cornerRadius(OPSStyle.Layout.buttonRadius)
        }
        .buttonStyle(.plain)
        .shadow(color: OPSStyle.Colors.shadowColor, radius: 12, x: 0, y: 6)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Empty (all clear · §10)

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(SyncStatusCopy.PendingWork.emptyHero)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(SyncStatusCopy.PendingWork.emptyLabel)
                .font(OPSStyle.Typography.metadata)
                .tracking(1.0)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(OPSStyle.Layout.spacing3_5)
    }
}

// MARK: - Share sheet bridge

/// UIKit share sheet for the mixed export payload (text + images + files).
struct PendingWorkShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Screen wrapper

struct PendingWorkScreen: View {
    /// How the leading nav control reads — a close ✕ (modal cover) or a back
    /// chevron labelled for its origin (pushed/drilled from Settings).
    enum Leading: Equatable {
        case close
        case back(String)
    }

    var leading: Leading = .close

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @State private var inventory = RecoveryInventory(attention: [], sending: [], drafts: [], unlinked: [])
    @State private var now = Date()
    @State private var exportPayload: PendingWorkExportPayload?
    @State private var resumingDraft = false
    @State private var openingDesign: DeckDesign?

    private let refreshTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private var queue: ClientLeadAutocreateQueue { ClientLeadAutocreateQueue.shared }

    var body: some View {
        VStack(spacing: 0) {
            header
            PendingWorkView(
                inventory: inventory,
                actions: actions,
                now: now,
                searchLinkTargets: { await searchLinkTargets($0, $1) }
            )
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
        .onAppear {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            refresh()
        }
        .onReceive(refreshTimer) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .opsLeadsDidChange)) { _ in
            refresh()
        }
        .sheet(item: $exportPayload) { payload in
            PendingWorkShareSheet(activityItems: payload.activityItems)
        }
        .fullScreenCover(isPresented: $resumingDraft) {
            SiteVisitCaptureView(
                opportunity: nil,
                onCreateProject: { _ in resumingDraft = false }
            )
            .environmentObject(dataController)
        }
        .fullScreenCover(item: $openingDesign) { design in
            DeckBuilderView(
                deckDesign: design,
                modelContext: modelContext,
                syncEngine: dataController.syncEngine
            )
            .environmentObject(dataController)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        switch leading {
        case .close:
            OPSScreenHeader(SyncStatusCopy.PendingWork.screenTitle) {
                OPSHeaderCloseButton { dismiss() }
            }
        case .back(let label):
            OPSScreenHeader(SyncStatusCopy.PendingWork.screenTitle) {
                OPSHeaderBackButton(label: label) { dismiss() }
            }
        }
    }

    // MARK: - Inventory

    private func refresh() {
        let current = Date()
        now = current
        inventory = RecoveryInventory.load(from: modelContext, queue: queue, now: current)
    }

    // MARK: - Actions bundle

    private var actions: PendingWorkActions {
        PendingWorkActions(
            retryItem: { retry(item: $0) },
            retryAll: { retryAll() },
            discardItem: { discard(item: $0) },
            exportItem: { export(item: $0) },
            linkDesign: { link(designId: $0, to: $1) },
            openDraft: { openDraft($0) },
            openDesign: { openDesign($0) },
            dismiss: { dismiss() }
        )
    }

    // MARK: - Retry

    private func retry(item: RecoveryItem) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        apply(retryTo: item)
        Task { await dataController.syncEngine.triggerSync() }
        refresh()
    }

    private func apply(retryTo item: RecoveryItem) {
        switch item {
        case .op(let snapshot, _, _):
            retryOperation(id: snapshot.id)
        case .autocreate(let snapshot, _, _):
            queue.retryParked(clientId: snapshot.clientId)
        case .photos(let grouped, _):
            retryPhotos(ids: grouped.map(\.id))
        case .bundle(let bundle):
            for member in bundle.members {
                if let opId = member.syncOpId {
                    retryOperation(id: opId)
                } else if let clientId = member.autocreateClientId {
                    queue.retryParked(clientId: clientId)
                } else if !member.photoIds.isEmpty {
                    retryPhotos(ids: member.photoIds)
                }
            }
        case .draft, .orphanDesign:
            break
        }
    }

    private func retryAll() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let hadAttention = inventory.attentionCount > 0

        // Reset every recoverable op (failed AND parked) to a fresh pending
        // budget, then re-enqueue crash-stranded in-flight ops.
        resetRecoverableOperations()
        dataController.syncEngine.reenqueueRecoverableOperations()

        // Unpark every parked lead-delivery request and revive every failed photo.
        queue.unparkAll()
        retryAllFailedPhotos()

        Task { await dataController.syncEngine.triggerSync() }
        refresh()

        // Success only when the sweep actually cleared the attention section.
        if hadAttention && inventory.attentionCount == 0 {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    private func retryOperation(id: UUID) {
        let target = id
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> {
                $0.id == target && ($0.status == "failed" || $0.status == "parked")
            }
        )
        guard let op = (try? modelContext.fetch(descriptor))?.first else { return }
        dataController.syncEngine.retryOperations([op])
    }

    private func resetRecoverableOperations() {
        let descriptor = FetchDescriptor<SyncOperation>(
            predicate: #Predicate<SyncOperation> { $0.status == "failed" || $0.status == "parked" }
        )
        guard let ops = try? modelContext.fetch(descriptor), !ops.isEmpty else { return }
        dataController.syncEngine.retryOperations(ops)
    }

    private func retryPhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<LocalPhoto>(
            predicate: #Predicate<LocalPhoto> { $0.status == "failed" }
        )
        guard let photos = try? modelContext.fetch(descriptor) else { return }
        var touched = false
        for photo in photos where idSet.contains(photo.id) {
            photo.status = "local"
            photo.uploadRetryCount = 0
            photo.needsSync = true
            touched = true
        }
        guard touched else { return }
        try? modelContext.save()
        Task { await dataController.syncEngine.processPhotoUploads() }
    }

    private func retryAllFailedPhotos() {
        let descriptor = FetchDescriptor<LocalPhoto>(
            predicate: #Predicate<LocalPhoto> { $0.status == "failed" }
        )
        guard let photos = try? modelContext.fetch(descriptor), !photos.isEmpty else { return }
        for photo in photos {
            photo.status = "local"
            photo.uploadRetryCount = 0
            photo.needsSync = true
        }
        try? modelContext.save()
        Task { await dataController.syncEngine.processPhotoUploads() }
    }

    // MARK: - Discard (spec §4 semantics)

    private func discard(item: RecoveryItem) {
        switch item {
        case .op(let snapshot, _, _):
            // Create → the local entity was never sent: delete it, then drop the
            // op. Update/link → cancel the op only; server state wins on inbound.
            if snapshot.operationType == "create" {
                deleteLocalEntity(entityType: snapshot.entityType, entityId: snapshot.entityId)
            }
            cancelOperation(id: snapshot.id)
        case .autocreate(let snapshot, _, _):
            queue.removeRequest(clientId: snapshot.clientId)
        case .photos(let grouped, _):
            deletePhotos(ids: grouped.map(\.id))
        case .bundle(let bundle):
            discardBundle(bundle)
        case .draft, .orphanDesign:
            break
        }
        try? modelContext.save()
        refresh()
    }

    private func discardBundle(_ bundle: SiteVisitBundle) {
        for member in bundle.members {
            if let opId = member.syncOpId {
                if let op = fetchOperation(id: opId) {
                    if op.operationType == "create" {
                        deleteLocalEntity(entityType: op.entityType, entityId: op.entityId)
                    }
                    dataController.syncEngine.cancelOperation(op)
                }
            } else if let clientId = member.autocreateClientId {
                queue.removeRequest(clientId: clientId)
            } else if !member.photoIds.isEmpty {
                deletePhotos(ids: member.photoIds)
            }
        }
        // Remove a never-sent packet locally, or queue tenant-scoped tombstones
        // when any part of the packet has already reached the server.
        deleteVisitPacket(siteVisitId: bundle.draft.siteVisitId)
    }

    private func cancelOperation(id: UUID) {
        guard let op = fetchOperation(id: id) else { return }
        dataController.syncEngine.cancelOperation(op)
    }

    private func fetchOperation(id: UUID) -> SyncOperation? {
        let target = id
        let descriptor = FetchDescriptor<SyncOperation>(predicate: #Predicate<SyncOperation> { $0.id == target })
        return (try? modelContext.fetch(descriptor))?.first
    }

    /// Hard-deletes a never-sent local entity for the field-created types that
    /// surface here. Unmapped types fall back to op-cancel only (the sync record
    /// is dropped; the local row lingers harmlessly) — no blind delete.
    private func deleteLocalEntity(entityType: String, entityId: String) {
        let target = entityId.lowercased()
        switch entityType {
        case "client":
            deleteFirst(FetchDescriptor<Client>(predicate: #Predicate<Client> { $0.id == target }))
        case "deckDesign":
            deleteFirst(FetchDescriptor<DeckDesign>(predicate: #Predicate<DeckDesign> { $0.id == target }))
        case "projectTask":
            deleteFirst(FetchDescriptor<ProjectTask>(predicate: #Predicate<ProjectTask> { $0.id == target }))
        case "project":
            deleteFirst(FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.id == target }))
        case "opportunity":
            deleteFirst(FetchDescriptor<Opportunity>(predicate: #Predicate<Opportunity> { $0.id == target }))
        default:
            break
        }
    }

    private func deleteVisitPacket(siteVisitId: String) {
        let visitDescriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.id == siteVisitId }
        )
        guard let visit = (try? modelContext.fetch(visitDescriptor))?.first else { return }
        let artifactDescriptor = FetchDescriptor<SiteVisitCaptureArtifact>(
            predicate: #Predicate<SiteVisitCaptureArtifact> { $0.siteVisitId == siteVisitId }
        )
        let answerDescriptor = FetchDescriptor<SiteVisitChecklistAnswer>(
            predicate: #Predicate<SiteVisitChecklistAnswer> { $0.siteVisitId == siteVisitId }
        )
        let draftDescriptor = FetchDescriptor<SiteVisitIdentityDraft>(
            predicate: #Predicate<SiteVisitIdentityDraft> { $0.siteVisitId == siteVisitId }
        )
        let artifacts = (try? modelContext.fetch(artifactDescriptor)) ?? []
        let answers = (try? modelContext.fetch(answerDescriptor)) ?? []
        let drafts = (try? modelContext.fetch(draftDescriptor)) ?? []
        let coordinator = SiteVisitPersistenceCoordinator(
            modelContext: modelContext,
            companyId: visit.companyId
        )
        let wasNeverSynced = visit.lastSyncedAt == nil
            && artifacts.allSatisfy { $0.lastSyncedAt == nil }
            && answers.allSatisfy { $0.lastSyncedAt == nil }
            && drafts.allSatisfy { $0.lastSyncedAt == nil }

        do {
            if wasNeverSynced {
                try coordinator.hardDeleteNeverSyncedVisit(
                    visit,
                    artifacts: artifacts,
                    answers: answers,
                    drafts: drafts
                )
            } else {
                try coordinator.commit {
                    let deletedAt = Date()
                    visit.status = .cancelled
                    visit.deletedAt = deletedAt
                    visit.updatedAt = deletedAt
                    visit.needsSync = true
                    for artifact in artifacts {
                        artifact.deletedAt = deletedAt
                        artifact.updatedAt = deletedAt
                        artifact.needsSync = true
                    }
                    for answer in answers {
                        answer.deletedAt = deletedAt
                        answer.updatedAt = deletedAt
                        answer.needsSync = true
                    }
                    for draft in drafts {
                        draft.deletedAt = deletedAt
                        draft.touch()
                    }
                }
            }
        } catch {
            print("[PENDING_WORK] Site-visit discard save failed: \(error)")
        }
    }

    private func deletePhotos(ids: [String]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        let descriptor = FetchDescriptor<LocalPhoto>()
        guard let photos = try? modelContext.fetch(descriptor) else { return }
        for photo in photos where idSet.contains(photo.id) {
            if FileManager.default.fileExists(atPath: photo.localPath) {
                try? FileManager.default.removeItem(atPath: photo.localPath)
            }
            modelContext.delete(photo)
        }
    }

    private func deleteFirst<T: PersistentModel>(_ descriptor: FetchDescriptor<T>) {
        if let model = (try? modelContext.fetch(descriptor))?.first {
            modelContext.delete(model)
        }
    }

    // MARK: - Export

    private func export(item: RecoveryItem) {
        let payload = PendingWorkExport.build(item: item, modelContext: modelContext, now: now)
        // The detail sheet has already begun dismissing; present the share sheet
        // once it settles so two sheets never fight for the same presenter.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            exportPayload = payload
        }
    }

    // MARK: - Link

    private func link(designId: String, to target: PendingWorkLinkTarget) {
        switch target.scope {
        case .leads:
            dataController.syncEngine.recordOperation(
                entityType: .deckDesign,
                entityId: designId,
                operationType: "linkOpportunity",
                changedFields: ["opportunity_id": target.id.lowercased()],
                priority: 1
            )
            setDesignLink(designId: designId, opportunityId: target.id, projectId: nil)
        case .projects:
            dataController.syncEngine.recordOperation(
                entityType: .deckDesign,
                entityId: designId,
                operationType: "update",
                changedFields: ["project_id": target.id.lowercased()],
                priority: 1
            )
            setDesignLink(designId: designId, opportunityId: nil, projectId: target.id)
        }
        refresh()
    }

    /// Optimistic local link so the row leaves NOT LINKED immediately; the
    /// recorded op carries the authoritative server write.
    private func setDesignLink(designId: String, opportunityId: String?, projectId: String?) {
        let target = designId
        let descriptor = FetchDescriptor<DeckDesign>(predicate: #Predicate<DeckDesign> { $0.id == target })
        guard let design = (try? modelContext.fetch(descriptor))?.first else { return }
        if let opportunityId { design.opportunityId = opportunityId }
        if let projectId { design.projectId = projectId }
        try? modelContext.save()
    }

    // MARK: - Open draft / design

    private func openDraft(_ draft: DraftSnapshot) {
        // No id-targeted resume hook exists for the FAB capture flow, and its
        // owner (FloatingActionMenu) is out of scope. Reopening the unlinked
        // capture surfaces the newest content-bearing visit for the operator to
        // finish — the common single-draft case lands on this draft.
        resumingDraft = true
    }

    private func openDesign(_ design: OrphanDesignSnapshot) {
        let target = design.id
        let descriptor = FetchDescriptor<DeckDesign>(predicate: #Predicate<DeckDesign> { $0.id == target })
        openingDesign = (try? modelContext.fetch(descriptor))?.first
    }

    // MARK: - Link-target search (real queries)

    private func searchLinkTargets(
        _ query: String,
        _ scope: PendingWorkLinkScope
    ) async -> [PendingWorkLinkTarget] {
        guard let companyId = dataController.currentUser?.companyId, !companyId.isEmpty else { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespaces).lowercased()

        switch scope {
        case .leads:
            let all = (try? modelContext.fetch(FetchDescriptor<Opportunity>())) ?? []
            return all
                .filter { $0.companyId == companyId && !$0.stage.isTerminal && $0.deletedAt == nil }
                .filter { trimmed.isEmpty || $0.contactName.lowercased().contains(trimmed) }
                .sorted { ($0.lastActivityAt ?? $0.createdAt) > ($1.lastActivityAt ?? $1.createdAt) }
                .prefix(40)
                .map { PendingWorkLinkTarget(id: $0.id, name: $0.contactName, subtitle: $0.stage.displayName, scope: .leads) }
        case .projects:
            let all = (try? modelContext.fetch(FetchDescriptor<Project>())) ?? []
            return all
                .filter { $0.companyId == companyId && $0.deletedAt == nil && !$0.status.isCompleted }
                .filter { trimmed.isEmpty || $0.title.lowercased().contains(trimmed) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .prefix(40)
                .map { PendingWorkLinkTarget(id: $0.id, name: $0.title, subtitle: $0.status.displayName, scope: .projects) }
        }
    }
}
