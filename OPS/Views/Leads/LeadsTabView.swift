//
//  LeadsTabView.swift
//  OPS
//
//  Root of the LEADS tab — triage queue surface. Replaces the Phase 1 hero
//  carousel + ball-in-court + stage strip + paged TabView design with a
//  single forecast hero + WonConvert carousel + chip-filtered lead queue +
//  pipeline-by-stage footer.
//
//  Implementation phase: P2 of the 2026-05-19 rebuild.
//  Plan:  docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §6
//  Intent: docs/superpowers/specs/2026-05-19-leads-tab-design-intent.md
//
//  Top-to-bottom layout:
//
//      [meta row]                 // TUE · MAY 19              [+]
//      [title row]                LEADS              OPERATOR :: JACKSON
//      [hero widget]              forecast hero + 3 sub-metric
//      [won·convert carousel]     conditional — only when unconverted wins
//      [section header]           // QUEUE              SORTED — STALE FIRST
//      [filter chip row]          ALL · OVERDUE · DUE TODAY · ...
//      [queue]                    LeadActionCard rows, 8pt gaps
//      [pipeline footer]          // BY STAGE — 6-stage drill panel
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

    var id: String {
        switch self {
        case .add:                return "add"
        case .edit(let opp):      return "edit-\(opp.id)"
        case .lost(let opp):      return "lost-\(opp.id)"
        case .convert(let opp):   return "convert-\(opp.id)"
        case .log(let opp):       return "log-\(opp.id)"
        }
    }
}

// MARK: - Root

struct LeadsTabView: View {
    @StateObject private var viewModel: PipelineViewModel
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore

    @State private var selectedBucket: PipelineViewModel.TriageBucket?
    @State private var detailLead: Opportunity?
    @State private var activeSheet: LeadsSheet?
    @State private var moreForLead: Opportunity?
    @State private var footerStage: PipelineStage?

    init(viewModel: PipelineViewModel? = nil) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PipelineViewModel())
    }

    private var buckets: PipelineViewModel.TriageBuckets { viewModel.triageBuckets }
    private var canManage: Bool { permissionStore.can("pipeline.manage") }
    private var bucket: PipelineViewModel.TriageBucket {
        selectedBucket ?? viewModel.defaultBucket
    }
    private var stageCounts: [PipelineStage: Int] {
        Dictionary(uniqueKeysWithValues: PipelineStage.allCases.map {
            ($0, viewModel.count(in: $0))
        })
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                OPSStyle.Colors.background.ignoresSafeArea()
                Atmosphere(tone: atmosphereTone)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        metaRow
                        titleRow

                        HeroWidget(
                            forecastValue: viewModel.weightedForecastValue,
                            forecastDeltaPct: viewModel.forecastDeltaPct,
                            overdueCount: buckets.overdue.count,
                            dueTodayCount: buckets.dueToday.count,
                            openLeadCount: viewModel.openLeadCount,
                            waitingCount: viewModel.waitingCount,
                            avgVelocityDays: viewModel.avgVelocityDays()
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                        if !buckets.unconvertedWon.isEmpty {
                            WonConvertCarousel(
                                leads: buckets.unconvertedWon,
                                onConvert: { activeSheet = .convert($0) },
                                onLater:   { detailLead = $0 }
                            )
                            .padding(.top, 18)
                        }

                        queueHeader
                            .padding(.top, 22)
                            .padding(.horizontal, 20)

                        FilterChipRow(
                            selectedId: filterBinding,
                            chips: bucketChips
                        )
                        .padding(.top, 8)

                        queueList
                            .padding(.top, 4)
                            .padding(.horizontal, 20)

                        PipelineFooter(
                            counts: stageCounts,
                            onStageTap: { footerStage = $0 },
                            onBoardTap: { openBoard() }
                        )
                        .padding(.horizontal, 20)
                        .padding(.top, 28)
                        .padding(.bottom, 100)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationBarHidden(true)
            .navigationDestination(item: $detailLead) { lead in
                LeadDetailView(
                    opportunity: lead,
                    onMarkLost: { activeSheet = .lost(lead) },
                    onEdit:     { activeSheet = .edit(lead) },
                    onMarkWon:  { activeSheet = .convert(lead) }
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
            .confirmationDialog(
                "Actions",
                isPresented: moreSheetPresented,
                presenting: moreForLead
            ) { lead in
                if canManage {
                    Button("MARK WON →") { activeSheet = .convert(lead) }
                    Button("MARK LOST", role: .destructive) { activeSheet = .lost(lead) }
                    Button("EDIT") { activeSheet = .edit(lead) }
                    Button("ARCHIVE") {
                        Task { try? await viewModel.archive(opportunityId: lead.id) }
                    }
                }
                Button("CANCEL", role: .cancel) {}
            }
        }
        .trackScreen("Leads")
        .task {
            if let companyId = dataController.currentUser?.companyId {
                viewModel.setup(companyId: companyId, currentUserId: dataController.currentUser?.id)
                await viewModel.loadData()
            }
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
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadArchivedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("LeadDeletedSuccess"))) { _ in
            Task { await viewModel.loadData() }
        }
    }

    // MARK: - Top rows

    private var metaRow: some View {
        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(dateText)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(0.8)
            .textCase(.uppercase)

            Spacer()

            // No filter icon (plan §2.1 Q4 = delete entirely). Search is
            // provided by the persistent overlay button in MainTabView
            // (Bug 706a4d32), so we don't render one here either.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                activeSheet = .add
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text2)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("New lead")
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
    }

    private var titleRow: some View {
        HStack(alignment: .lastTextBaseline) {
            Text("LEADS")
                .font(OPSStyle.Typography.display)
                .foregroundColor(OPSStyle.Colors.text)
                .textCase(.uppercase)
            Spacer()
            if let user = dataController.currentUser {
                Text("OPERATOR :: \(user.firstName.uppercased())")
                    .font(.custom("JetBrainsMono-Regular", size: 9.5))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .kerning(0.8)
                    .textCase(.uppercase)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - Queue

    private var queueHeader: some View {
        HStack {
            PanelSectionHeader(label: "QUEUE")
            Spacer()
            Text("SORTED — STALE FIRST")
                .font(OPSStyle.Typography.metadata)
                .kerning(1.4)
                .foregroundColor(OPSStyle.Colors.textMute)
                .textCase(.uppercase)
        }
    }

    private var bucketChips: [FilterChipModel] {
        let order: [PipelineViewModel.TriageBucket] = [
            .all, .overdue, .dueToday, .waitingOnYou, .fresh, .waitingOnThem
        ]
        return order.map { b in
            let count: Int = (b == .all) ? buckets.all.count : buckets.leads(for: b).count
            return FilterChipModel(
                id: b.rawValue,
                label: b.label,
                count: count,
                dotColor: dotColor(for: b)
            )
        }
    }

    private var filterBinding: Binding<String> {
        Binding(
            get: { bucket.rawValue },
            set: { newValue in
                if let b = PipelineViewModel.TriageBucket(rawValue: newValue) {
                    selectedBucket = b
                }
            }
        )
    }

    private func dotColor(for b: PipelineViewModel.TriageBucket) -> Color {
        switch b {
        case .all:           return OPSStyle.Colors.text
        case .overdue:       return OPSStyle.Colors.rose
        case .dueToday:      return OPSStyle.Colors.tan
        case .waitingOnYou:  return OPSStyle.Colors.opsAccent
        case .fresh:         return OPSStyle.Colors.text2
        case .waitingOnThem: return OPSStyle.Colors.textMute
        }
    }

    @ViewBuilder
    private var queueList: some View {
        let leads = buckets.leads(for: bucket)
        if leads.isEmpty {
            BucketEmpty(bucket: bucket)
                .padding(.vertical, 28)
                .frame(maxWidth: .infinity)
        } else {
            LazyVStack(spacing: 8) {
                ForEach(leads) { lead in
                    LeadActionCard(
                        opportunity: lead,
                        verb: viewModel.verbFor(lead, bucket: bucket),
                        tone: viewModel.toneFor(bucket, lead: lead),
                        showsLog: canManage,
                        showsMore: canManage,
                        showsAdvance: canManage,
                        onTap:     { detailLead = lead },
                        onLog:     { activeSheet = .log(lead) },
                        onMore:    { moreForLead = lead },
                        onAdvance: { advance(lead) }
                    )
                }
            }
        }
    }

    // MARK: - Sheet routing

    @ViewBuilder
    private func sheetView(for sheet: LeadsSheet) -> some View {
        switch sheet {
        case .add:
            AddLeadSheet(onSaved: { _ in })
        case .edit(let opp):
            EditLeadSheet(opportunity: opp)
        case .lost(let opp):
            LostReasonSheet(opportunity: opp)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .convert(let opp):
            ConvertToProjectSheet(opportunity: opp)
        case .log(let opp):
            LeadLogActivitySheet(opportunity: opp)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helpers

    private var atmosphereTone: Atmosphere.Tone {
        // Adapts subtly to current urgency profile. Defaults to steel when
        // the queue is calm.
        if buckets.overdue.count > 0 { return .rose }
        if buckets.dueToday.count > 0 { return .tan }
        if !buckets.unconvertedWon.isEmpty { return .olive }
        return .steel
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "EEE · MMM d"
        return f.string(from: Date()).uppercased()
    }

    private var moreSheetPresented: Binding<Bool> {
        Binding(
            get: { moreForLead != nil },
            set: { if !$0 { moreForLead = nil } }
        )
    }

    private func advance(_ lead: Opportunity) {
        guard canManage, !lead.stage.isTerminal, let next = lead.stage.next else { return }
        Task {
            try? await viewModel.moveToStage(
                opportunityId: lead.id,
                to: next,
                userId: dataController.currentUser?.id
            )
        }
    }

    /// "OPEN STAGE BOARD →" — routes to the first open stage that has leads,
    /// falling back to NEW LEAD (per PipelineFooter's onBoardTap contract).
    private func openBoard() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let openOrder: [PipelineStage] = [
            .newLead, .qualifying, .quoting, .quoted, .followUp, .negotiation
        ]
        footerStage = openOrder.first { (stageCounts[$0] ?? 0) > 0 } ?? .newLead
    }
}

// MARK: - Bucket empty state

private struct BucketEmpty: View {
    let bucket: PipelineViewModel.TriageBucket

    var body: some View {
        VStack(spacing: 10) {
            Text("00")
                .font(.custom("Mohave-Light", size: 32))
                .foregroundColor(OPSStyle.Colors.text3)
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(message)
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
            .font(OPSStyle.Typography.metadata)
            .kerning(1.8)
            .textCase(.uppercase)
        }
    }

    private var message: String {
        switch bucket {
        case .all:           return "— NO OPEN LEADS"
        case .overdue:       return "— NO OVERDUE FOLLOW-UPS"
        case .dueToday:      return "— NOTHING DUE TODAY"
        case .waitingOnYou:  return "— NO REPLIES OUTSTANDING"
        case .fresh:         return "— NO NEW LEADS"
        case .waitingOnThem: return "— NOT WAITING ON ANYONE"
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("LeadsTabView / loaded") {
    LeadsTabView(viewModel: .previewLoaded())
        .leadsPreviewEnvironment()
}

#Preview("LeadsTabView / empty") {
    LeadsTabView(viewModel: .previewLoaded(opportunities: []))
        .leadsPreviewEnvironment()
}
#endif
