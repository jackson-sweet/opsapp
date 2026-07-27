//
//  LeadsTabView.swift
//  OPS
//
//  Root of the LEADS tab — the chase-queue surface.
//  Money & Leads redesign (2026-06-30) — design direction "2a · TRIAGE LEADS".
//
//  Top-to-bottom layout:
//      [AppHeader]                LEADS                         [+] [search]
//      [summary]                  weighted forecast + stage bar + triage tiles
//      [by-stage row]             // PIPELINE BY STAGE (horizontal)
//      [won nudge]                conditional — unconverted wins → convert
//      [sticky chips]             ALL · OVERDUE · DUE TODAY · WAITING ON YOU · …
//      [queue]                    LeadTriageCard rows, grouped by urgency
//

import SwiftUI

// MARK: - Active-sheet enum

/// Identifies which sheet is currently presented over the LEADS surface.
/// Backs `.sheet(item: $activeSheet)` so only one sheet shows at a time.
enum LeadsSheet: Identifiable {
    case add
    case edit(Opportunity)
    case lost(Opportunity)
    case convert(Opportunity)
    case log(Opportunity)
    /// Picker behind the WON · CONVERT nudge when more than one win is
    /// unconverted — pick a win, then hand it to `.convert`.
    case wonChooser

    var id: String {
        switch self {
        case .add:                return "add"
        case .edit(let opp):      return "edit-\(opp.id)"
        case .lost(let opp):      return "lost-\(opp.id)"
        case .convert(let opp):   return "convert-\(opp.id)"
        case .log(let opp):       return "log-\(opp.id)"
        case .wonChooser:         return "won-chooser"
        }
    }
}

// MARK: - Queue item

/// A flattened queue entry — either an urgency-group header or a lead — so the
/// grouped queue renders as one lazy list with cheap diffable ids.
private enum LeadQueueItem: Identifiable {
    case header(PipelineViewModel.TriageBucket, Int)
    case lead(Opportunity, PipelineViewModel.TriageBucket)

    var id: String {
        switch self {
        case .header(let b, _): return "h-\(b.rawValue)"
        case .lead(let l, _):   return "l-\(l.id)"
        }
    }
}

// MARK: - Root

struct LeadsTabView: View {
    @StateObject private var viewModel: PipelineViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var conversionVisibilityStore = LeadConversionVisibilityStore.shared

    @State private var selectedBucket: PipelineViewModel.TriageBucket?
    @State private var detailLead: Opportunity?
    @State private var activeSheet: LeadsSheet?
    @State private var footerStage: PipelineStage?
    @State private var activeSiteVisitLead: Opportunity?
    @State private var discardTarget: Opportunity?
    /// Lead whose comeback date is being adjusted (ComebackChooserSheet).
    @State private var comebackTarget: Opportunity?
    /// Pending ARCHIVE confirmation (OPSConfirm).
    @State private var archiveConfirm: OPSConfirmConfig?

    /// Guards the deep-link drain so a single tap resolves once even if both
    /// the `.task` load and the `pendingLeadDeepLinkId` change fire.
    @State private var isResolvingDeepLink = false

    init(viewModel: PipelineViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PipelineViewModel())
    }

    private var buckets: PipelineViewModel.TriageBuckets { viewModel.triageBuckets }
    private var leadAccessPolicy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private var canCreate: Bool { leadAccessPolicy.canCreate }
    private var canConvertAny: Bool { leadAccessPolicy.canConvertAny }
    private func canEdit(_ lead: Opportunity) -> Bool {
        leadAccessPolicy.can(.edit, assignedTo: lead.assignedTo)
    }
    private func canConvert(_ lead: Opportunity) -> Bool {
        leadAccessPolicy.can(.convert, assignedTo: lead.assignedTo)
    }
    private var convertibleUnconvertedWins: [Opportunity] {
        buckets.unconvertedWon.filter(canConvert)
    }

    /// The default view is ALL, grouped by urgency. A specific chip flattens to
    /// that bucket; if it empties (last item cleared) we drop back to ALL rather
    /// than strand the operator on an empty, non-tappable chip.
    private var effectiveBucket: PipelineViewModel.TriageBucket {
        if let selected = selectedBucket, selected != .all, !buckets.leads(for: selected).isEmpty {
            return selected
        }
        return .all
    }

    private static let groupOrder: [PipelineViewModel.TriageBucket] = [
        .overdue, .dueToday, .waitingOnYou, .waitingOnThem, .fresh
    ]

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    AppHeader(
                        headerType: .leads,
                        onAddLead: canCreate ? { activeSheet = .add } : nil
                    )
                    .padding(.bottom, OPSStyle.Layout.spacing2)
                    .background(OPSStyle.Colors.background.ignoresSafeArea(edges: .top))

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                            LeadsSummary(viewModel: viewModel)
                                .padding(.top, OPSStyle.Layout.spacing1)

                            LeadsByStageRow(viewModel: viewModel, onStageTap: { footerStage = $0 })
                                .padding(.top, 22)

                            if !convertibleUnconvertedWins.isEmpty {
                                LeadsWonNudge(
                                    count: convertibleUnconvertedWins.count,
                                    totalValue: unconvertedWonValue,
                                    onTap: { presentWonConvert() }
                                )
                                .padding(.top, OPSStyle.Layout.spacing3)
                            }

                            Section {
                                queueBody
                                    .padding(.top, OPSStyle.Layout.spacing2_5)
                            } header: {
                                queueBand
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .refreshable {
                        // Manual pull-to-refresh — same silent merge reload as
                        // the realtime / foreground triggers, so rows update in
                        // place with no skeleton flash. System refresh control,
                        // no custom styling. iOS 17.6 supports .refreshable on
                        // ScrollView.
                        await viewModel.loadData(silent: true)
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 120)
                    }
                    .leadDiscardFlow(
                        target: $discardTarget
                    )
                    .opsConfirm($archiveConfirm)
                }
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $detailLead) { lead in
                LeadDetailView(
                    opportunity: lead,
                    onMarkLost: { activeSheet = .lost(lead) },
                    onEdit:     { activeSheet = .edit(lead) },
                    onMarkWon:  { activeSheet = .convert(lead) },
                    onConvertLead: { convertedLead in
                        activeSheet = .convert(convertedLead)
                    }
                )
                .environmentObject(dataController)
                .environmentObject(permissionStore)
            }
            .navigationDestination(item: $footerStage) { stage in
                PipelineStageListView(
                    stage: stage,
                    viewModel: viewModel,
                    onLeadTap: { detailLead = $0 },
                    onRequestSheet: { activeSheet = $0 }
                )
                .environmentObject(dataController)
                .environmentObject(permissionStore)
            }
            .sheet(item: $activeSheet) { sheet in
                sheetView(for: sheet)
            }
            .sheet(item: $comebackTarget) { lead in
                ComebackChooserSheet(lead: lead, viewModel: viewModel)
            }
            .fullScreenCover(item: $activeSiteVisitLead) { lead in
                SiteVisitCaptureView(
                    opportunity: lead,
                    onCreateProject: { convertedLead in
                        activeSiteVisitLead = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            activeSheet = .convert(convertedLead)
                        }
                    }
                )
                .environmentObject(dataController)
            }
        }
        .trackScreen("Leads")
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId, currentUserId: dataController.currentUser?.id)
                await viewModel.loadData()
            }
            await resolvePendingLeadDeepLinkIfNeeded()
        }
        .onChange(of: appState.pendingLeadDeepLinkId) { _, newValue in
            guard newValue != nil else { return }
            Task { await resolvePendingLeadDeepLinkIfNeeded() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadCreatedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadUpdatedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadActivityLoggedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadMarkedLostSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadMarkedWonSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadConvertedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadLinkedProjectSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadArchivedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadDeletedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .opsLeadsDidChange)) { _ in
            // Remote change (RealtimeProcessor: opportunities / activities /
            // follow_ups). Funnel through the debounced, coalesced reload — an
            // event storm collapses to one silent merge fetch; leads are
            // deliberately outside the SwiftData sync engine.
            viewModel.scheduleRefresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            // Catch-up on resume: realtime tears down ~30s after backgrounding
            // (OPSApp scenePhase), so any change during background is lost —
            // this re-fetch is the recovery path. Short debounce; the coalescer
            // + hasLoadedOnce guard make it a no-op on cold launch where .task
            // owns the first load.
            viewModel.scheduleRefresh(debounce: .milliseconds(300))
        }
        .onChange(of: viewModel.allOpportunities.map(\.id)) { _, ids in
            // A reload can drop a lead deleted / merged / archived elsewhere.
            // If that lead is open in detail, pop it rather than strand a dead
            // screen. Observe the id list (Equatable) rather than [Opportunity]
            // — the @Model class has no Equatable conformance, and this covers
            // every reload path (realtime, foreground, pull-to-refresh, the
            // nine Lead*Success listeners), not just the realtime one.
            // activeSheet is left alone — a mid-edit sheet stays (per non-goals).
            if let open = detailLead, !ids.contains(open.id) {
                detailLead = nil
            }
        }
    }

    // MARK: - Sticky chip band

    private var queueBand: some View {
        VStack(spacing: 0) {
            TacticalChipRow(chips: bucketChips, selectedId: filterBinding)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
            Rectangle()
                .fill(OPSStyle.Colors.line)
                .frame(height: 1)
        }
        .background(OPSStyle.Colors.background)
    }

    private var bucketChips: [TacticalChip] {
        let order: [PipelineViewModel.TriageBucket] = [
            .all, .overdue, .dueToday, .waitingOnYou, .fresh, .waitingOnThem
        ]
        return order.map { b in
            let count = (b == .all) ? buckets.all.count : buckets.leads(for: b).count
            return TacticalChip(id: b.rawValue, label: chipLabel(b), count: count, tone: bucketTone(b))
        }
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { effectiveBucket.rawValue },
            set: { newValue in
                if let b = PipelineViewModel.TriageBucket(rawValue: newValue) {
                    selectedBucket = b
                }
            }
        )
    }

    private func chipLabel(_ b: PipelineViewModel.TriageBucket) -> String {
        switch b {
        case .all:           return "ALL"
        case .overdue:       return "OVERDUE"
        case .dueToday:      return "DUE TODAY"
        case .waitingOnYou:  return "YOUR MOVE"
        case .fresh:         return "FRESH"
        case .waitingOnThem: return "WAITING"
        }
    }

    private func bucketTone(_ b: PipelineViewModel.TriageBucket) -> Color? {
        switch b {
        case .all:           return nil
        case .overdue:       return OPSStyle.Colors.rose
        case .dueToday:      return OPSStyle.Colors.tan
        case .waitingOnYou:  return OPSStyle.Colors.opsAccent
        case .fresh:         return OPSStyle.Colors.olive
        case .waitingOnThem: return OPSStyle.Colors.textMute
        }
    }

    // MARK: - Queue body

    @ViewBuilder
    private var queueBody: some View {
        if effectiveBucket == .all {
            if buckets.all.isEmpty {
                LeadsCaughtUp(title: "ALL CAUGHT UP", label: "NO FOLLOW-UPS DUE", hint: caughtUpHint)
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(groupedItems) { item in
                        switch item {
                        case .header(let b, let count):
                            queueSectionHeader(b, count: count)
                        case .lead(let lead, let b):
                            cardFor(lead, bucket: b)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        } else {
            let leads = buckets.leads(for: effectiveBucket)
            if leads.isEmpty {
                LeadsCaughtUp(title: "NONE HERE", label: "NO LEADS IN THIS FILTER", hint: "SWITCH FILTER TO SEE MORE")
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(leads) { lead in
                        cardFor(lead, bucket: effectiveBucket)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    private var groupedItems: [LeadQueueItem] {
        var items: [LeadQueueItem] = []
        for b in Self.groupOrder {
            let leads = buckets.leads(for: b)
            guard !leads.isEmpty else { continue }
            items.append(.header(b, leads.count))
            items.append(contentsOf: leads.map { .lead($0, b) })
        }
        return items
    }

    private func queueSectionHeader(_ b: PipelineViewModel.TriageBucket, count: Int) -> some View {
        let color = bucketTone(b) ?? OPSStyle.Colors.text2
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(groupHeaderLabel(b))
                .font(.custom("JetBrainsMono-Medium", size: 9.5))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundColor(color)
            Rectangle().fill(OPSStyle.Colors.line).frame(height: 1)
            Text("\(count)")
                .font(.custom("JetBrainsMono-Medium", size: 9.5))
                .foregroundColor(color)
                .monospacedDigit()
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    private func groupHeaderLabel(_ b: PipelineViewModel.TriageBucket) -> String {
        switch b {
        case .overdue:       return "OVERDUE · CHASE NOW"
        case .dueToday:      return "DUE TODAY"
        case .waitingOnYou:  return "YOUR MOVE"
        case .waitingOnThem: return "WAITING"
        case .fresh:         return "FRESH"
        case .all:           return "ALL"
        }
    }

    private func cardFor(_ lead: Opportunity, bucket: PipelineViewModel.TriageBucket) -> some View {
        LeadTriageCard(
            lead: lead,
            viewModel: viewModel,
            bucket: bucket,
            canEdit: canEdit(lead),
            canConvert: canConvert(lead),
            onTap:     { detailLead = lead },
            onLog:     { activeSheet = .log(lead) },
            onHandled: { markHandled(lead) },
            onSendFollowUp: { sendFollowUp(lead) },
            onAdjust:  { comebackTarget = lead },
            onStage:   { stage in setStage(lead, to: stage) },
            onWon:     { activeSheet = .convert(lead) },
            onLost:    { activeSheet = .lost(lead) },
            onArchive: { requestArchive(lead) },
            onDiscard: { discardTarget = lead }
        )
        .contextMenu {
            LeadCardContextMenu(
                lead: lead,
                canManage: canEdit(lead),
                onEdit: { activeSheet = .edit(lead) },
                onArchive: { requestArchive(lead) },
                onDiscard: { discardTarget = lead }
            )
        }
    }

    // MARK: - Sheet routing

    @ViewBuilder
    private func sheetView(for sheet: LeadsSheet) -> some View {
        switch sheet {
        case .add:
            AddLeadSheet(
                onSaved: { _ in },
                onStartSiteVisit: canConvertAny
                    ? { lead in activeSiteVisitLead = lead }
                    : nil
            )
        case .edit(let opp):
            EditLeadSheet(opportunity: opp)
        case .lost(let opp):
            LostReasonSheet(opportunity: opp)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .convert(let opp):
            ConvertToProjectSheet(opportunity: opp)
        case .log(let opp):
            UnifiedLogActivitySheet(viewModel: UnifiedLogActivityViewModel(entry: .leadDetail(opp)))
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        case .wonChooser:
            LeadsWonChooserSheet(
                leads: convertibleUnconvertedWins,
                onPick: { lead in
                    // Swap chooser → convert. Drop the chooser first, then
                    // present convert on the next runloop so a single sheet
                    // channel never tries to show both (mirrors the site-visit
                    // → convert hand-off).
                    activeSheet = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        activeSheet = .convert(lead)
                    }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Deep link

    @MainActor
    private func resolvePendingLeadDeepLinkIfNeeded() async {
        guard let leadId = appState.pendingLeadDeepLinkId, !leadId.isEmpty else { return }
        guard !isResolvingDeepLink else { return }
        isResolvingDeepLink = true
        appState.pendingLeadDeepLinkId = nil
        defer { isResolvingDeepLink = false }

        if let lead = viewModel.allOpportunities.first(where: { $0.id == leadId }) {
            presentDeepLinkedLead(lead)
            return
        }

        guard let companyId = dataController.currentUser?.companyId else {
            appState.presentAccessDenied(message: "This lead is no longer available.")
            return
        }
        let repo = OpportunityRepository(companyId: companyId)
        do {
            let dto = try await repo.fetchOne(leadId)
            let lead = dto.toModel()
            guard !lead.isDeleted else {
                appState.presentAccessDenied(message: "This lead is no longer available.")
                return
            }
            presentDeepLinkedLead(lead)
        } catch {
            print("[Pipeline] Deep-linked lead \(leadId) not resolvable: \(error)")
            appState.presentAccessDenied(message: "This lead is no longer available.")
        }
    }

    @MainActor
    private func presentDeepLinkedLead(_ lead: Opportunity) {
        if let current = detailLead, current.id != lead.id {
            detailLead = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                detailLead = lead
            }
        } else {
            detailLead = lead
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    // MARK: - Helpers

    private var unconvertedWonValue: Double {
        convertibleUnconvertedWins.reduce(0) {
            $0 + ($1.actualValue ?? $1.estimatedValue ?? 0)
        }
    }

    private var caughtUpHint: String {
        "\(viewModel.openLeadCount) OPEN · PIPELINE \(BooksFormat.compact(viewModel.openPipelineValue))"
    }

    /// One unconverted win → straight to convert. Several → a chooser first so
    /// the operator sees every open win and picks which to turn into a job.
    private func presentWonConvert() {
        let wins = convertibleUnconvertedWins
        if wins.count > 1 {
            activeSheet = .wonChooser
        } else if let first = wins.first {
            activeSheet = .convert(first)
        }
    }

    // MARK: - Chase actions (Leads redesign spec §2.2 / §6)

    /// HANDLED ✓ — flip the ball, then voice the comeback in the toast with a
    /// tappable ADJUST escape hatch. The toast is the only ceremony.
    private func markHandled(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        Task {
            do {
                let comeback = try await viewModel.markHandled(opportunityId: lead.id)
                ToastCenter.shared.present(Toast(
                    label: "// HANDLED · BACK \(LeadChaseStrip.comebackLabel(comeback))",
                    tone: .success,
                    autoDismissAfter: 6,
                    action: ToastAction(label: "ADJUST", accessibilityLabel: "Adjust comeback date") {
                        comebackTarget = lead
                    }
                ))
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }

    /// SEND FOLLOW-UP — one tap sends the stock reply through the connected
    /// mailbox. The view model advances the lead only from the server's
    /// provider-confirmed canonical response.
    private func sendFollowUp(_ lead: Opportunity) {
        guard canEdit(lead), viewModel.canSendFollowUp(for: lead) else { return }
        Task {
            let outcome = await viewModel.sendFollowUp(opportunityId: lead.id)
            ToastCenter.shared.present(
                Feedback.Lead.followUpResult(outcome) {
                    comebackTarget = lead
                }
            )
        }
    }

    /// Direct stage pick from the status menu (open stages only — WON always
    /// routes through the convert sheet).
    private func setStage(_ lead: Opportunity, to stage: PipelineStage) {
        guard canEdit(lead), stage != lead.stage else { return }
        Task {
            do {
                try await viewModel.moveToStage(
                    opportunityId: lead.id,
                    to: stage,
                    userId: dataController.currentUser?.id
                )
                ToastCenter.shared.present(Feedback.Lead.stageSet)
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }

    /// ARCHIVE — guarded by the standardized confirm (spec §6).
    private func requestArchive(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        archiveConfirm = OPSConfirmConfig(
            title: "ARCHIVE LEAD?",
            message: "It leaves the queue. Restore any time from the by-stage list.",
            verb: "ARCHIVE"
        ) {
            Task {
                do {
                    try await viewModel.archive(opportunityId: lead.id)
                    ToastCenter.shared.present(Feedback.Lead.archived)
                } catch {
                    ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
                }
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadsTabView / loaded") {
    LeadsTabView(viewModel: .previewLoaded())
        .leadsPreviewEnvironment()
        .environmentObject(SubscriptionManager.shared)
}

#Preview("LeadsTabView / empty") {
    LeadsTabView(viewModel: .previewLoaded(opportunities: []))
        .leadsPreviewEnvironment()
        .environmentObject(SubscriptionManager.shared)
}
#endif
