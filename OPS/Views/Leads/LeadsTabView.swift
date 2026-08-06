//
//  LeadsTabView.swift
//  OPS
//
//  Root of the LEADS tab — the chase-queue surface.
//  Console redesign (2026-08-05) — open → act → browse → manipulate.
//
//  Top-to-bottom layout:
//      [AppHeader]                LEADS                         [+] [search]
//      [command band]             need-action hero / quiet line + metrics +
//                                 stage bar → BY STAGE ▸
//      [won nudge]                conditional — unconverted wins → convert
//      [sticky band]              search field + SORT + CREW, then the bucket
//                                 chips and a hairline
//      [queue]                    LeadTriageCard rows — grouped by urgency, or
//                                 flat under NEWEST / VALUE / a live search
//
//  The queue's shape is never decided here: `LeadsQueryEngine.apply` owns
//  population, filtering, ordering and grouping, and this view renders whatever
//  it hands back. One tested truth, no predicates loose in the body.
//

import SwiftUI
import SwiftData

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

    /// Every company user on device — the raw material for the crew roster.
    /// Same `@Query` the dossier uses; the engine does the filtering.
    @Query private var allUsers: [User]

    @State private var selectedBucket: PipelineViewModel.TriageBucket?
    /// Search / sort / crew. Plain `@State`, so a tab remount resets them:
    /// opening LEADS always answers "what needs me" first, never whatever
    /// slice the operator left behind yesterday (spec §5.2). MainTabView
    /// remounts the tab content on selection change (`.id(selectedTab)`).
    @State private var controls: LeadsListControls
    @State private var detailLead: Opportunity?
    @State private var activeSheet: LeadsSheet?
    @State private var footerStage: PipelineStage?
    @State private var activeSiteVisitLead: Opportunity?
    @State private var discardTarget: Opportunity?
    /// Lead whose comeback date is being adjusted (ComebackChooserSheet).
    @State private var comebackTarget: Opportunity?
    /// Pending ARCHIVE confirmation (OPSConfirm).
    @State private var archiveTarget: Opportunity?

    /// Guards the deep-link drain so a single tap resolves once even if both
    /// the `.task` load and the `pendingLeadDeepLinkId` change fire.
    @State private var isResolvingDeepLink = false

    // MARK: Day sheet (assigned scope — spec §2)

    /// The one card open on the day sheet, and the lead a deep link wants
    /// revealed. Both live here so the tab's existing drain can drive them.
    @State private var expandedLeadId: String?
    @State private var daySheetScrollTarget: String?
    /// Built on first `.task` — the production wiring needs a company id, which
    /// only the environment can supply.
    @State private var milestoneCommitter: LeadMilestoneCommitter?
    /// When the last good fetch landed, for `SYS :: OFFLINE — LAST SYNC <T>`.
    @State private var lastSnapshotAt: Date?
    /// Deck opened from an expanded card (LeadDetailView's pattern).
    @State private var deckRequest: DeckOpenRequest?

    /// A deck to open full-screen, with the lead it belongs to for the title.
    private struct DeckOpenRequest: Identifiable {
        let design: DeckDesign
        let leadName: String
        var id: String { design.id }
    }

    /// `initialControls` exists for the snapshot harness, which has to prove
    /// the search and sort states of the real screen (the same reason
    /// `LeadTriageCard` takes `summaryInitiallyExpanded`). Production never
    /// passes it — the console always opens on URGENCY / ALL CREW / no query.
    init(
        viewModel: PipelineViewModel? = nil,
        initialControls: LeadsListControls = LeadsListControls()
    ) {
        _viewModel = StateObject(wrappedValue: viewModel ?? PipelineViewModel())
        _controls = State(initialValue: initialControls)
    }

    /// Which LEADS surface this operator gets (spec §2) — the permission scope
    /// decides, never a role name. `all` is the owner's triage console;
    /// `assigned` is the delegate's day sheet. Pure and static so the branch is
    /// testable without a view.
    static func showsDaySheet(policy: LeadAccessPolicy) -> Bool {
        policy.scope(for: .view) == .assigned
    }

    private var showsDaySheet: Bool { Self.showsDaySheet(policy: leadAccessPolicy) }

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
    /// than strand the operator on an empty, non-tappable chip. The engine owns
    /// that rule so the chip binding and the applied query can never disagree.
    private var effectiveBucket: PipelineViewModel.TriageBucket {
        LeadsQueryEngine.effectiveBucket(selectedBucket ?? .all, in: buckets)
    }

    /// Where BY STAGE lands — the engine owns the rule (max open count, ties by
    /// funnel order); the view only supplies the counts the bar is drawing.
    private var entryStage: PipelineStage {
        LeadsQueryEngine.entryStage(
            counts: PipelineStage.openStages.map { ($0, viewModel.count(in: $0)) }
        )
    }

    // MARK: - Crew (spec §5.3, §6.4)

    /// The nameable crew this console can filter by and print on cards.
    private var roster: [CrewMember] {
        LeadsQueryEngine.roster(
            users: allUsers,
            leads: viewModel.allOpportunities,
            companyId: dataController.currentUser?.companyId
        )
    }

    /// One nameable operator means assignment carries no information — the crew
    /// chip and every card label stay off the screen entirely.
    private var showsAssignment: Bool {
        LeadsQueryEngine.showsAssignment(roster: roster)
    }

    /// Card labels resolved ONCE per render, keyed by lead id: the roster walk
    /// happens here rather than inside each card, so a hundred rows cost one
    /// pass instead of a hundred.
    private var assigneeIndex: [String: String] {
        guard showsAssignment else { return [:] }
        let crew = roster
        var index: [String: String] = [:]
        for lead in viewModel.allOpportunities {
            index[lead.id] = LeadsQueryEngine.assigneeLabel(for: lead.assignedTo, roster: crew)
        }
        return index
    }

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

                    surface
                        .safeAreaInset(edge: .bottom) {
                            Color.clear.frame(height: 120)
                        }
                        .leadDiscardFlow(
                            target: $discardTarget
                        )
                        .leadArchiveFlow(target: $archiveTarget)
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
                    onRequestSheet: { activeSheet = $0 },
                    // One source for assignee labels: the console resolves
                    // them, the browser reads them.
                    assigneeIndex: assigneeIndex,
                    // One site-visit cover for the whole tab — the browser
                    // raises the same one the queue does.
                    onStartSiteVisit: { activeSiteVisitLead = $0 }
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
            .fullScreenCover(item: $deckRequest) { request in
                deckBuilder(request)
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
                prepareDaySheetIfNeeded(companyId: companyId)
                await viewModel.loadData()
                finishDaySheetLoadIfNeeded(companyId: companyId)
            }
            await resolvePendingLeadDeepLinkIfNeeded()
        }
        .modifier(LeadsRefreshListeners(viewModel: viewModel))
        .onChange(of: appState.pendingLeadDeepLinkId) { _, newValue in
            guard newValue != nil else { return }
            Task { await resolvePendingLeadDeepLinkIfNeeded() }
        }
        .onChange(of: showsDaySheet) { _, isDaySheet in
            // Permissions can hydrate after the tab's first `.task` — a store
            // that fails closed on a cold launch would otherwise leave the day
            // sheet without its committer for the rest of the session.
            guard isDaySheet, let companyId = dataController.currentUser?.companyId else { return }
            prepareDaySheetIfNeeded(companyId: companyId)
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
            // Same stranding rule for the day sheet's open card.
            if let open = expandedLeadId, !ids.contains(open) {
                expandedLeadId = nil
            }
        }
    }

    // MARK: - Surface branch (spec §2)

    /// One shell — header, sheets, destinations, listeners — and exactly one
    /// thing swapped inside it: the scroll body. The console path below is
    /// untouched.
    @ViewBuilder
    private var surface: some View {
        if showsDaySheet {
            daySheetScroll
        } else {
            consoleScroll
        }
    }

    // MARK: - Day sheet

    @ViewBuilder
    private var daySheetScroll: some View {
        if let committer = milestoneCommitter {
            LeadDaySheetView(
                viewModel: viewModel,
                committer: committer,
                expandedLeadId: $expandedLeadId,
                scrollTarget: $daySheetScrollTarget,
                operatorId: dataController.currentUser?.id,
                lastSyncLabel: daySheetLastSyncLabel,
                onFullLead: { detailLead = $0 },
                onOpenDeck: { lead, design in
                    deckRequest = DeckOpenRequest(design: design,
                                                  leadName: lead.displayContactName)
                },
                onStage: { lead, stage in setStage(lead, to: stage) },
                onWon: { presentWon($0) },
                onLost: { activeSheet = .lost($0) },
                onArchive: { requestArchive($0) },
                onDiscard: { discardTarget = $0 },
                // The SAME cover the detail screen, the FAB and the add-lead
                // sheet already drive. The day sheet adds a door, not a second
                // capture flow — `SiteVisitCaptureViewModel.loadOrCreateVisit`
                // resumes this lead's open visit or starts one, so a runner who
                // opened a card mid-visit lands back where he left off.
                onStartSiteVisit: { activeSiteVisitLead = $0 },
                onAddLead: canCreate ? { activeSheet = .add } : nil
            )
        } else {
            // One frame: the committer is built by `.task`, which runs before
            // the first fetch answers. Nothing to show yet either way.
            Color.clear
        }
    }

    // MARK: - Console

    private var consoleScroll: some View {
        // Resolved once here, then handed down — see `assigneeIndex`.
        let assignees = assigneeIndex
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                LeadsSummary(viewModel: viewModel, onByStage: { footerStage = entryStage })
                    .padding(.top, OPSStyle.Layout.spacing1)

                if !convertibleUnconvertedWins.isEmpty {
                    LeadsWonNudge(
                        count: convertibleUnconvertedWins.count,
                        totalValue: unconvertedWonValue,
                        onTap: { presentWonConvert() }
                    )
                    .padding(.top, OPSStyle.Layout.spacing3)
                }

                Section {
                    queueBody(assignees: assignees)
                        .padding(.top, OPSStyle.Layout.spacing2_5)
                } header: {
                    queueBand
                }
            }
        }
        .scrollIndicators(.hidden)
        // Typing costs the queue two thirds of the screen; a drag down hands
        // it straight back without a DONE tap.
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            // Manual pull-to-refresh — same silent merge reload as
            // the realtime / foreground triggers, so rows update in
            // place with no skeleton flash. System refresh control,
            // no custom styling. iOS 17.6 supports .refreshable on
            // ScrollView.
            await viewModel.loadData(silent: true)
        }
    }

    // MARK: - Sticky control band

    private var queueBand: some View {
        LeadsQueueBand(
            controls: $controls,
            chips: bucketChips,
            selectedChipId: filterBinding,
            roster: roster,
            showsCrew: showsAssignment
        )
    }

    /// Chips carry RAW bucket counts, deliberately: they describe the queue the
    /// operator owns, not the slice a crew filter is currently showing. A chip
    /// that read `OVERDUE 0` because of a crew filter would look like there is
    /// nothing overdue. Group headers below carry the filtered counts.
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

    /// Renders whatever the engine resolved — grouped when the queue is in its
    /// urgency browse mode, flat under any other sort, an active chip, or a
    /// live search.
    @ViewBuilder
    private func queueBody(assignees: [String: String]) -> some View {
        switch LeadsQueryEngine.apply(
            controls: controls,
            buckets: buckets,
            selectedBucket: selectedBucket ?? .all,
            currentUserId: viewModel.currentUserId
        ) {
        case .grouped(let groups):
            if groups.isEmpty {
                emptyQueue
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(groupedItems(groups)) { item in
                        switch item {
                        case .header(let b, let count):
                            queueSectionHeader(b, count: count)
                        case .lead(let lead, let b):
                            cardFor(lead, bucket: b, assignees: assignees)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        case .flat(let leads):
            if leads.isEmpty {
                if controls.isSearching { noMatchesBlock } else { emptyQueue }
            } else {
                LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                    if controls.isSearching {
                        matchesHeader(count: leads.count)
                    }
                    ForEach(leads) { lead in
                        // `.all` lets each card derive its OWN urgency tone, so
                        // a lead reads as overdue in any order it appears in.
                        cardFor(lead, bucket: .all, assignees: assignees)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            }
        }
    }

    /// One rule for a queue showing nothing: either there is genuinely no work,
    /// or the operator's own filter has excluded it. Never a search state —
    /// that has its own block.
    @ViewBuilder
    private var emptyQueue: some View {
        if buckets.all.isEmpty {
            LeadsCaughtUp(title: "ALL CAUGHT UP", label: "NO FOLLOW-UPS DUE", hint: caughtUpHint)
        } else {
            LeadsCaughtUp(title: "NONE HERE", label: "NO LEADS IN THIS FILTER", hint: "SWITCH FILTER TO SEE MORE")
        }
    }

    private func groupedItems(
        _ groups: [(bucket: PipelineViewModel.TriageBucket, leads: [Opportunity])]
    ) -> [LeadQueueItem] {
        var items: [LeadQueueItem] = []
        for group in groups {
            items.append(.header(group.bucket, group.leads.count))
            items.append(contentsOf: group.leads.map { .lead($0, group.bucket) })
        }
        return items
    }

    // MARK: - Search states (spec §6.3)

    /// `// MATCHES ─── N` — the section-header grammar in a neutral tone,
    /// because a match is not an urgency.
    private func matchesHeader(count: Int) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("MATCHES").foregroundColor(OPSStyle.Colors.text2)
            }
            .font(.custom("JetBrainsMono-Medium", size: 9.5))
            .tracking(1.4)
            .textCase(.uppercase)

            Rectangle().fill(OPSStyle.Colors.line).frame(height: 1)

            Text("\(count)")
                .font(.custom("JetBrainsMono-Medium", size: 9.5))
                .foregroundColor(OPSStyle.Colors.text2)
                .monospacedDigit()
        }
        .padding(.top, OPSStyle.Layout.spacing1)
    }

    /// Nothing matched. Deliberately NOT the olive check ring — that grammar
    /// means "caught up", and a failed search is not an achievement.
    private var noMatchesBlock: some View {
        VStack(spacing: 10) {
            Text("0")
                .font(.custom("Mohave-Light", size: 32))
                .foregroundColor(OPSStyle.Colors.text3)

            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("NO MATCHES").foregroundColor(OPSStyle.Colors.textMute)
            }
            .font(OPSStyle.Typography.miniLabel)
            .tracking(1.6)
            .textCase(.uppercase)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                controls.query = ""
            } label: {
                Text("[ CLEAR SEARCH ]")
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(1.2)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Clear search")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
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

    private func cardFor(
        _ lead: Opportunity,
        bucket: PipelineViewModel.TriageBucket,
        assignees: [String: String]
    ) -> some View {
        LeadTriageCard(
            lead: lead,
            viewModel: viewModel,
            bucket: bucket,
            canEdit: canEdit(lead),
            canConvert: canConvert(lead),
            assigneeLabel: assignees[lead.id],
            // The SAME cover the detail screen, the day sheet, the FAB and the
            // add-lead sheet already drive — `SiteVisitCaptureViewModel
            // .loadOrCreateVisit` resumes this lead's open visit or starts one.
            // The card gates its own chip on `canConvert && !isTerminal`
            // (verbatim LeadDetailView's), and `canConvert` above is already
            // entity-relative, so no second gate belongs here.
            onStartSiteVisit: { activeSiteVisitLead = lead },
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
        // Day sheet: open the lead where it lives rather than pushing a screen
        // over it. A lead the loaded sheet doesn't hold (reassigned, or the
        // fetchOne recovery above) has no row to expand — push detail instead,
        // so a tapped notification is never a dead tap.
        if showsDaySheet, viewModel.allOpportunities.contains(where: { $0.id == lead.id }) {
            daySheetScrollTarget = lead.id
            return
        }
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

    // MARK: - Day sheet plumbing (spec §3.5 / §6)

    /// Build the milestone committer and install the offline snapshot sink.
    /// Console operators reach none of this — the sink stays nil there, and the
    /// view model behaves exactly as it always has.
    @MainActor
    private func prepareDaySheetIfNeeded(companyId: String) {
        guard showsDaySheet, let userId = dataController.currentUser?.id else { return }

        if milestoneCommitter == nil {
            // Capture the controller itself, not this view: the committer
            // outlives any one body evaluation, and reading an
            // `@EnvironmentObject` through a stale view copy is a trap.
            let controller = dataController
            milestoneCommitter = LeadMilestoneCommitter(
                pipeline: viewModel,
                companyId: companyId,
                // The screen supplies connectivity: DataController is the app's
                // one source of network truth.
                isOnline: { controller.isConnected }
            )
        }

        viewModel.snapshotSink = { dtos in
            let savedAt = Date()
            DaySheetCache.shared.save(dtos, userId: userId, companyId: companyId, savedAt: savedAt)
            lastSnapshotAt = savedAt
        }

        // Seed the stamp from disk so an offline cold launch can say when the
        // sheet it is showing was last true.
        if lastSnapshotAt == nil,
           let snapshot = DaySheetCache.shared.load(userId: userId, companyId: companyId) {
            lastSnapshotAt = snapshot.savedAt
        }
    }

    /// After the first fetch: fall back to the cached sheet if it failed, and
    /// warm the row thumbnails if it worked.
    @MainActor
    private func finishDaySheetLoadIfNeeded(companyId: String) {
        guard showsDaySheet, let userId = dataController.currentUser?.id else { return }
        hydrateFromDaySheetCache(userId: userId, companyId: companyId)
        prefetchDaySheetThumbs()
    }

    /// Cold open with no signal: the fetch failed and nothing is loaded, so the
    /// last good sheet becomes the sheet. Kept here rather than in the view
    /// model — the cache belongs to this screen, not to the loader.
    @MainActor
    private func hydrateFromDaySheetCache(userId: String, companyId: String) {
        guard viewModel.loadError != nil, viewModel.allOpportunities.isEmpty else { return }
        guard let snapshot = DaySheetCache.shared.load(userId: userId, companyId: companyId) else { return }
        viewModel.allOpportunities = PipelineViewModel.merge(
            existing: [],
            incoming: snapshot.dtos.map { $0.toModel() }
        )
        lastSnapshotAt = snapshot.savedAt
    }

    /// One shot per lead — the tile shows the newest photo, so that is the only
    /// one worth spending a truck's bandwidth on. Fire-and-forget; the tiles
    /// resolve from cache on their own next appearance.
    @MainActor
    private func prefetchDaySheetThumbs() {
        let newest: [String] = viewModel.allOpportunities.compactMap { lead in
            lead.images.last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        guard !newest.isEmpty else { return }
        Task { _ = await PhotoDownloadManager.shared.downloadAllPhotos(newest) }
    }

    /// Non-nil only when the sheet is showing something other than a fetch that
    /// just succeeded — offline, or the last fetch failed — and there is a
    /// stamp to name.
    private var daySheetLastSyncLabel: String? {
        guard !dataController.isConnected || viewModel.loadError != nil else { return nil }
        guard let lastSnapshotAt else { return nil }
        return DaySheetCache.lastSyncLabel(lastSnapshotAt)
    }

    /// WON is the guarded conversion — iOS refuses a direct `.won` stage write
    /// (`OpportunityRepository.validateDirectStageMutation`) and the server's
    /// conversion RPC refuses an actor without convert scope. Edit-only
    /// delegates never see the button; this guard is the backstop.
    private func presentWon(_ lead: Opportunity) {
        guard canConvert(lead) else { return }
        activeSheet = .convert(lead)
    }

    /// Full-screen deck from an expanded card — the tab owns the model context
    /// and sync engine, exactly as LeadDetailView does.
    @ViewBuilder
    private func deckBuilder(_ request: DeckOpenRequest) -> some View {
        if let modelContext = dataController.modelContext {
            DeckBuilderView(
                deckDesign: request.design,
                modelContext: modelContext,
                syncEngine: dataController.syncEngine,
                projectName: request.leadName
            )
        }
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

    /// SEND FOLLOW-UP — the chase strip owns the deliberate hold/review gate.
    /// The view model advances the lead only from the server's
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
    /// Hands off to the shared archive flow — the same sheet, contract, and
    /// undo the dossier raises. The reload listener on `LeadArchivedSuccess`
    /// takes the row off the board.
    private func requestArchive(_ lead: Opportunity) {
        guard canEdit(lead) else { return }
        archiveTarget = lead
    }
}

// MARK: - Refresh listeners

/// Every freshness trigger for the LEADS tab, lifted out of the root body so
/// the surface branch stays inside the type-checker's budget. Shared by both
/// surfaces — the console and the day sheet reload on exactly the same events,
/// because they read exactly the same view model.
private struct LeadsRefreshListeners: ViewModifier {

    @ObservedObject var viewModel: PipelineViewModel

    func body(content: Content) -> some View {
        content
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
    }
}

// MARK: - Previews

#if DEBUG
// The console reads the crew roster through `@Query` — previews need a
// container for it, even an empty one (a solo roster closes the assignment
// gate, which is itself the correct default state to preview).
#Preview("LeadsTabView / loaded") {
    LeadsTabView(viewModel: .previewLoaded())
        .leadsPreviewEnvironment()
        .environmentObject(SubscriptionManager.shared)
        .modelContainer(for: User.self, inMemory: true)
}

#Preview("LeadsTabView / searching") {
    LeadsTabView(
        viewModel: .previewLoaded(),
        initialControls: LeadsListControls(query: "roof")
    )
    .leadsPreviewEnvironment()
    .environmentObject(SubscriptionManager.shared)
    .modelContainer(for: User.self, inMemory: true)
}

#Preview("LeadsTabView / empty") {
    LeadsTabView(viewModel: .previewLoaded(opportunities: []))
        .leadsPreviewEnvironment()
        .environmentObject(SubscriptionManager.shared)
        .modelContainer(for: User.self, inMemory: true)
}
#endif
