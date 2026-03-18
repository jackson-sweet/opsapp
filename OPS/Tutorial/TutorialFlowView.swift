import SwiftUI
import UIKit

// MARK: - Frame Preference Key (for floating task positioning)

/// Reports named frames in the tutorialContent coordinate space.
/// Used to capture where deck task placeholder slots are in the project card and calendar,
/// so floating task views can animate to those exact positions.
private struct TaskSlotFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Phase of the 3 deck task floating views throughout the tutorial.
/// These views persist on screen from project card assembly through calendar extraction.
private enum DeckTaskPhase {
    case hidden            // Not yet visible (before assembly)
    case projectCard       // Positioned at project card task row slots
    case detaching         // Borders drawn, separating from project card
    case calendarBar       // Positioned at calendar gantt bar slots
    case reviewCard        // Expanded to full swipe card shapes
}

// MARK: - TutorialFlowView
/// ONE continuous view for the OPS "Lead to Revenue" tutorial.
///
/// Architecture:
/// - Phase-driven state machine (6 phases, no separate step files)
/// - matchedGeometryEffect connects estimate line items → task cards ("peel off")
/// - matchedGeometryEffect connects project card → invoice card (morph)
/// - Single evolving card for lead → estimate (content morphs in place)
/// - Review swipe cards styled after real TaskSwipeCardView
/// - All haptics via TutorialHaptics (arrival/commit/milestone)
/// - Reduced motion: crossfade alternatives for all animations
///
/// Emotional arc: skeptical → curious → impressed → convinced → committed
/// Brand: military tactical minimalist. Sharp ease-out entries. Clean ease-in exits.
/// Springs: dampingFraction >= 0.75 (no visible bounce). Celebration = restraint.
struct TutorialFlowView: View {

    let onComplete: () -> Void

    @StateObject private var state = TutorialStateManager()
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Card Evolution (Phases 1-3)
    // The card appears as a lead notification, morphs into an estimate,
    // then progressively loses line items as they peel off into task cards.

    @State private var showCard = false
    @State private var cardOffset: CGFloat = -280     // Entry from top
    @State private var isEstimateMode = false          // Lead vs estimate content
    @State private var estimateShellOpacity: Double = 1 // Fades during peel-off

    // Phase 1 — Lead
    @State private var clientChars = 0
    @State private var projectChars = 0
    @State private var showLeadSource = false
    @State private var leadGlow: Double = 0
    @State private var leadInteractive = false
    @State private var typewriterTimer: Timer?

    // Phase 2 — Estimate
    @State private var visibleLineItems = 0
    @State private var showDivider = false
    @State private var showTotal = false
    @State private var showSendEstimate = false

    // Phase 3 — Approved
    @State private var showApproval = false
    @State private var peeledCount = 0                 // Drives matchedGeometry peel-off
    @State private var showCrewOnTasks = false
    @State private var showContinue = false

    // Phase 4 — Crew Executes → Project Assembly
    @State private var taskStatuses = [0, 0, 0]        // 0=booked, 1=inProgress, 2=complete
    @State private var projectAssembling = false        // Tasks morph into project card
    @State private var borderDrawProgress: CGFloat = 0  // Border draws around tasks (0→1)
    @State private var cardBgOpacity: Double = 0        // Project card background fades in
    @State private var projectTitleChars = 0            // Typewriter for project name
    @State private var progressBarValue: CGFloat = 0    // Progress bar fills (0→0.66)
    @State private var projectTitleTimer: Timer?

    // Phase 4→5 — Calendar Gantt Transition
    @State private var projectChromeFading = false         // Card chrome dissolving (bg, border, title, progress → 0)
    @State private var taskDetachBorders: [CGFloat] = [0, 0, 0]  // Per-task border draw during detach

    // Floating deck tasks — persistent views that morph through phases
    @State private var deckTaskPhase: DeckTaskPhase = .hidden
    @State private var projectCardSlotFrames: [String: CGRect] = [:]  // Captured from assemblingProjectView
    @State private var calendarSlotFrames: [String: CGRect] = [:]     // Captured from FlowCalendarWeek
    @State private var hideProjectCard = false            // Final removal — matchedGeometry flies tasks to calendar
    @State private var showCalendar = false
    @State private var calendarVisibleTasks: Set<String> = []  // Task IDs visible on calendar
    @State private var calendarCompletedTasks: Set<String> = []
    @State private var calendarFocusDay = -1             // -1=overview, 0=Mon...4=Fri
    @State private var calendarFadeCompleted = false     // Completed tasks fade after zoom out
    @State private var showCalendarHeader = false        // "4 TASKS NOT COMPLETE" text above calendar
    @State private var calendarExtractPhase = 0          // 0=normal, 1=bars expand, 2=titles, 3=wireframe

    // Phase 5 — Review (merged with invoice)
    @State private var showReviewStack = false
    @State private var reviewCurrentIndex = 0
    @State private var swipeResults: [Bool] = []        // true=right(complete), false=left(skip)
    @State private var showingCompletion: Int? = nil     // Index of card showing inline completion
    @State private var completionOpacity: Double = 0
    @State private var showReviewDone = false
    @State private var reviewDoneOpacity: Double = 0
    @State private var reviewDoneScale: CGFloat = 0.85

    // Phase 6 — Accounting Insights + Closing
    @State private var showAccounting = false             // Accounting insights view visible
    @State private var visibleInvoices = 0                // Stagger invoice card entries
    @State private var invoiceBarProgress: CGFloat = 0    // Revenue bar fill (0→1)
    @State private var showExpenses = false               // "COSTS FILED BY CREW" section
    @State private var visibleExpenses = 0                // Stagger expense entries
    @State private var expenseBarProgress: CGFloat = 0    // Expense bar fill (0→1)
    @State private var showProfit = false                 // Profit bar + margin display
    @State private var profitBarProgress: CGFloat = 0     // Profit bar fill (0→1)
    @State private var showClosing = false                // 13-step closing sequence
    @State private var closingStepsVisible = 0            // Steps written in one at a time
    @State private var closingStrikeCount = 0             // Steps struck through (0→11)
    @State private var closingCollapsed = false           // Struck steps compress away
    @State private var showClosingMessage = false         // "YOU SHOW UP..." tagline
    @State private var showCTA = false                    // GET STARTED button

    // Header
    @State private var headerOpacity: Double = 0

    private let clientText = TutorialData.clientName.uppercased()
    private let projectText = TutorialData.projectTitle
    private let charInterval: TimeInterval = 0.035

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                chrome
                    .padding(.top, 8)

                contextHeader
                    .frame(height: 56)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(headerOpacity)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { beginTutorial() }
        .onDisappear {
            typewriterTimer?.invalidate()
            projectTitleTimer?.invalidate()
        }
        .onChange(of: state.isActive) { _, active in
            if !active { onComplete() }
        }
    }

    // MARK: - Chrome (Progress Dots + Skip)

    private var chrome: some View {
        HStack {
            HStack(spacing: 8) {
                ForEach(0..<TutorialPhase.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i))
                        .frame(width: 6, height: 6)
                }
            }
            .animation(OPSStyle.Animation.fast, value: state.currentPhase)

            Spacer()

            if state.currentPhase != .invoiceAndPay {
                Button {
                    state.skip()
                } label: {
                    Text("SKIP")
                        .font(.caption)
                        .tracking(1)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                }
            }
        }
        .padding(.horizontal, 20)
    }

    private func dotColor(for index: Int) -> Color {
        let current = state.currentPhase.rawValue
        if index == current { return OPSStyle.Colors.primaryAccent }
        if index < current { return Color.white.opacity(0.4) }
        return Color.white.opacity(0.12)
    }

    // MARK: - Context Header

    private var contextHeader: some View {
        VStack(alignment: .center, spacing: 4) {
            Text(stepHeadline)
                .font(.heading)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(1)

            Text(stepSubline)
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
        .multilineTextAlignment(.center)
        .animation(.easeOut(duration: 0.2), value: state.currentPhase)
    }

    private var stepHeadline: String {
        switch state.currentPhase {
        case .leadArrives:      return "A NEW LEAD JUST LANDED"
        case .sendEstimate:     return "BUILD THE ESTIMATE"
        case .estimateApproved: return "CLIENT SAID YES"
        case .crewExecutes:     return "CREW IS WORKING"
        case .weeklyReview:     return "END OF THE WEEK"
        case .invoiceAndPay:    return "THE NUMBERS"
        }
    }

    private var stepSubline: String {
        switch state.currentPhase {
        case .leadArrives:      return "Caught automatically from your inbox."
        case .sendEstimate:     return "Line items. Crew costs. Materials. One tap to send."
        case .estimateApproved: return "Labor items become tasks. Crew gets assigned. No re-entry."
        case .crewExecutes:     return "They update status from the field. You see it live."
        case .weeklyReview:     return "Crew forgot to close these out. Swipe right to mark complete."
        case .invoiceAndPay:    return "Four projects. One week. Here's where you stand."
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            // ── PHASES 1-3: Evolving card + approval + peeling task cards ──

            if showCard {
                evolvingCard
                    .padding(.horizontal, 24)
                    .offset(y: cardOffset)
                    .opacity(estimateShellOpacity)
            }

            if showApproval {
                approvalBanner
                    .padding(.horizontal, 24)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .padding(.top, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // Task cards appearing via matchedGeometryEffect from estimate line items
            if peeledCount > 0 && !projectAssembling {
                VStack(spacing: 8) {
                    ForEach(0..<peeledCount, id: \.self) { i in
                        taskCardRow(TutorialData.taskCards[i], index: i, showCrew: showCrewOnTasks)
                            .matchedGeometryEffect(id: "laborTask_\(i)", in: ns)
                    }
                }
                .padding(.horizontal, 24)
            }

            // ── PHASE 4: Task assembly ──
            // Tasks morph into compact lines, border draws, title types in

            if state.currentPhase == .crewExecutes && !hideProjectCard {
                assemblingProjectView
                    .padding(.horizontal, 24)
                    .clipped() // Clips to visible content bounds during exit (title/progress already at opacity 0)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── PHASE 4→5: Calendar Gantt view ──

            if showCalendar {
                VStack(spacing: 12) {
                    if showCalendarHeader {
                        VStack(spacing: 8) {
                            Text("4 TASKS NOT COMPLETE")
                                .font(.heading)
                                .foregroundStyle(OPSStyle.Colors.warningStatus)
                                .tracking(2)
                            Text("MARKED FOR REVIEW")
                                .font(.caption)
                                .foregroundStyle(OPSStyle.Colors.secondaryText)
                                .tracking(1.5)
                        }
                        .transition(.opacity)
                    }

                    FlowCalendarWeek(
                        visibleTasks: calendarVisibleTasks,
                        completedTasks: calendarCompletedTasks,
                        focusDay: calendarFocusDay,
                        fadeCompleted: calendarFadeCompleted,
                        extractPhase: calendarExtractPhase
                    )
                }
                .padding(.horizontal, 12)
            }

            // ── FLOATING DECK TASKS ──
            // These 3 views persist from project card through calendar to review.
            // They are the visual continuity — the user's eye tracks them through every transition.
            if deckTaskPhase != .hidden {
                floatingDeckTasks
            }

            // ── PHASE 5: Review ──

            if showReviewStack {
                reviewStackView
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }

            // Swipe result overlay (right=complete, left=skipped)
            // Dimmed background + result card, blocks interaction with stack
            if let idx = showingCompletion, idx < swipeResults.count {
                ZStack {
                    // Dim background
                    Color.black.opacity(0.6 * completionOpacity)
                        .ignoresSafeArea()

                    // Result card
                    inlineSwipeResultCard(for: idx, wasRight: swipeResults[idx])
                        .padding(.horizontal, 24)
                }
                .opacity(completionOpacity)
            }

            if showReviewDone && !showAccounting {
                allCaughtUpView
                    .transition(.opacity)
            }

            // ── PHASE 6: Accounting Insights ──

            if showAccounting {
                accountingInsightsView
                    .padding(.horizontal, 20)
                    .transition(.opacity)
            }

            // ── PHASE 6: Closing Sequence ──

            if showClosing {
                closingSequenceView
                    .transition(.opacity)
            }

            // ── CONTINUE button (phases 3-4) ──

            if showContinue {
                Button {
                    handleContinue()
                } label: {
                    Text("CONTINUE")
                        .font(.button)
                        .tracking(1)
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
        .coordinateSpace(name: "tutorialContent")
        .onPreferenceChange(TaskSlotFrameKey.self) { frames in
            // Route frames to the correct state dict based on current phase
            if showCalendar && deckTaskPhase == .calendarBar {
                calendarSlotFrames = frames
            } else if deckTaskPhase == .projectCard || deckTaskPhase == .detaching {
                projectCardSlotFrames = frames
            }
        }
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 1-2: The Evolving Card (Lead → Estimate)
    // MARK: ─────────────────────────────────────────────────────────────────

    private var evolvingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isEstimateMode {
                // ── Lead content ──
                leadContent
            } else {
                // ── Estimate content ──
                estimateContent
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(
                    isEstimateMode
                        ? OPSStyle.Colors.cardBorder
                        : OPSStyle.Colors.primaryAccent.opacity(leadGlow * 0.3),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .shadow(
            color: isEstimateMode ? .clear : OPSStyle.Colors.primaryAccent.opacity(leadGlow * 0.06),
            radius: 16, x: 0, y: 4
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if leadInteractive && !isEstimateMode { handleLeadTap() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isEstimateMode
            ? "Estimate for \(TutorialData.projectTitle), \(TutorialData.formatCurrency(TutorialData.estimateTotal))"
            : "New lead: \(TutorialData.clientName), \(TutorialData.projectTitle). Tap to accept.")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: Lead Content

    @ViewBuilder
    private var leadContent: some View {
        // Reserve full height so card doesn't jump
        ZStack(alignment: .topLeading) {
            // Invisible spacer at final content size
            VStack(alignment: .leading, spacing: 12) {
                leadBadge
                Text(clientText).font(.headingLarge).tracking(0.8)
                Text(projectText).font(.body)
                leadSourceRow.padding(.top, 4)
            }
            .opacity(0)

            // Visible content — types in
            VStack(alignment: .leading, spacing: 12) {
                leadBadge
                    .opacity(showCard ? 1 : 0)

                Text(clientChars > 0 ? String(clientText.prefix(clientChars)) : " ")
                    .font(.headingLarge)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.8)
                    .opacity(clientChars > 0 ? 1 : 0)

                Text(projectChars > 0 ? String(projectText.prefix(projectChars)) : " ")
                    .font(.body)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
                    .opacity(projectChars > 0 ? 1 : 0)

                leadSourceRow
                    .padding(.top, 4)
                    .opacity(showLeadSource ? 1 : 0)
            }
        }
    }

    private var leadBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(OPSStyle.Colors.warningStatus)
                .frame(width: 6, height: 6)
            Text("NEW LEAD")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.warningStatus)
                .tracking(1.5)
        }
    }

    private var leadSourceRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "envelope.fill")
                .font(.system(size: 11))
            Text("GMAIL")
                .font(.microLabel)
                .tracking(1.2)
        }
        .foregroundStyle(OPSStyle.Colors.primaryAccent)
    }

    // MARK: Estimate Content

    @ViewBuilder
    private var estimateContent: some View {
        // Header
        VStack(alignment: .leading, spacing: 4) {
            Text("ESTIMATE")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                .tracking(1.5)

            Text(TutorialData.projectTitle.uppercased())
                .font(.headingLarge)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(0.8)

            Text(TutorialData.clientName)
                .font(.caption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
        .padding(.bottom, 16)

        // Line items
        VStack(spacing: 0) {
            // Labor items — matchedGeometry IDs connect to task cards
            ForEach(0..<TutorialData.laborItems.count, id: \.self) { i in
                if i < visibleLineItems && i >= peeledCount {
                    lineItemRow(TutorialData.laborItems[i])
                        .matchedGeometryEffect(id: "laborTask_\(i)", in: ns)
                        .transition(.opacity.combined(with: .move(edge: .leading)))

                    if i < TutorialData.laborItems.count - 1 && i < visibleLineItems - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.separator)
                            .frame(height: 0.5)
                            .padding(.leading, 15)
                    }
                }
            }

            // Material item (no matchedGeometry — billing only, not a task)
            if visibleLineItems > TutorialData.laborItems.count {
                lineItemRow(TutorialData.lineItems.last!)
                    .opacity(peeledCount > 0 ? 0 : 1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }

        // Divider
        if showDivider && peeledCount == 0 {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1)
                .padding(.vertical, 12)
        }

        // Total
        if showTotal && peeledCount == 0 {
            HStack {
                Text("TOTAL")
                    .font(.status)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
                    .tracking(1.5)
                Spacer()
                Text(TutorialData.formatCurrency(TutorialData.estimateTotal))
                    .font(.displayLarge)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
            }
        }

        // Send button
        if showSendEstimate && peeledCount == 0 {
            Button(action: handleSendEstimate) {
                Text("SEND ESTIMATE")
                    .font(.button)
                    .tracking(1)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .fill(OPSStyle.Colors.primaryAccent)
                    )
            }
            .padding(.top, 16)
        }
    }

    // MARK: Line Item Row

    private func lineItemRow(_ item: TutorialData.LineItem) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(item.type.color)
                .frame(width: 3, height: 28)

            Text(item.type.rawValue)
                .font(.microLabel)
                .foregroundStyle(item.type.color)
                .tracking(0.8)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(item.type.color.opacity(0.12))
                )

            Text(item.name)
                .font(.body)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Spacer()

            Text(TutorialData.formatCurrency(item.amount))
                .font(.bodyBold)
                .foregroundStyle(OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, 8)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 3: Approval Banner + Task Cards
    // MARK: ─────────────────────────────────────────────────────────────────

    private var approvalBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(OPSStyle.Colors.successStatus)

            VStack(alignment: .leading, spacing: 2) {
                Text("ESTIMATE APPROVED")
                    .font(.status)
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .tracking(1.5)
                Text("\(TutorialData.clientName) accepted")
                    .font(.body)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.successStatus.opacity(0.2), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: Task Card Row (Phase 3 — freshly peeled, BOOKED status)

    private func taskCardRow(_ task: TutorialData.TaskCard, index: Int, showCrew: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(task.color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.name.uppercased())
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.5)

                Text("BOOKED")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.inactiveStatus)
                    .tracking(1)
            }

            Spacer()

            if showCrew {
                crewBadge(for: task)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(height: 48)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private func crewBadge(for task: TutorialData.TaskCard) -> some View {
        let color = TutorialData.crewMembers.first(where: { $0.name == task.crew })?.color ?? OPSStyle.Colors.primaryAccent
        return HStack(spacing: 6) {
            Circle()
                .fill(color.opacity(0.2))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: "person.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(color)
                )
            Text(task.crew)
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 4: Task Execution → Project Assembly
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Unified view: task cards during execution morph into project card.
    /// When `projectAssembling` = false: full task cards with status cycling.
    /// When `projectAssembling` = true: compact task lines + drawn border + typewriter title + progress bar.
    /// When `projectChromeFading` = true: card chrome dissolves, task rows get individual borders.
    private var assemblingProjectView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Project title — types in during assembly, fades during chrome dissolve
            if projectAssembling {
                let title = TutorialData.projectTitle.uppercased()
                VStack(alignment: .leading, spacing: 4) {
                    Text(projectTitleChars > 0 ? String(title.prefix(projectTitleChars)) : " ")
                        .font(.headingLarge)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .tracking(0.8)

                    if projectTitleChars >= title.count {
                        Text(TutorialData.clientName)
                            .font(.caption)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.bottom, 12)
                .opacity(projectChromeFading ? 0 : 1) // Chrome fades
            }

            // Task rows — morph between full cards and compact lines
            // Spacing increases during detach so tasks separate into individual cards
            VStack(spacing: projectAssembling ? (projectChromeFading ? 10 : 2) : 8) {
                let calIDs = ["cal_sandprep", "cal_stain", "cal_rail"]
                ForEach(0..<TutorialData.taskCards.count, id: \.self) { i in
                    if deckTaskPhase == .hidden {
                        // Before floating layer takes over — render normally
                        morphingTaskRow(TutorialData.taskCards[i], index: i)
                    } else {
                        // Floating layer has taken over — render invisible placeholder
                        // that reports its frame for the floating views to position at
                        Color.clear
                            .frame(height: projectAssembling ? (projectChromeFading ? 34 : 26) : 48)
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: TaskSlotFrameKey.self,
                                        value: [calIDs[i]: geo.frame(in: .named("tutorialContent"))]
                                    )
                                }
                            )
                    }
                }
            }

            // Progress bar — appears during assembly, fades during chrome dissolve
            if projectAssembling && progressBarValue > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.08))
                            Capsule()
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: geo.size.width * progressBarValue)
                        }
                    }
                    .frame(height: 3)
                    .padding(.top, 14)

                    Text("2 OF 3 TASKS")
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                        .tracking(1)
                }
                .opacity(projectChromeFading ? 0 : 1) // Chrome fades
            }
        }
        .padding(projectAssembling ? 20 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
                .opacity(projectChromeFading ? 0 : cardBgOpacity) // Chrome fades
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                .opacity(projectChromeFading ? 0 : 1) // Chrome fades
        )
    }

    /// Task row that morphs between full card (with status) and compact line (with checkmark).
    private func morphingTaskRow(_ task: TutorialData.TaskCard, index: Int) -> some View {
        let s = taskStatuses[index]
        let statusLabel = s == 0 ? "BOOKED" : s == 1 ? "IN PROGRESS" : "COMPLETE"
        let statusColor: Color = s == 0 ? OPSStyle.Colors.inactiveStatus
            : s == 1 ? OPSStyle.Colors.warningStatus
            : OPSStyle.Colors.successStatus

        return HStack(spacing: projectAssembling ? 8 : 12) {
            if !projectAssembling {
                // Full mode: color stripe
                RoundedRectangle(cornerRadius: 1)
                    .fill(task.color)
                    .frame(width: 3)
            }

            if projectAssembling {
                // Compact mode: checkmark or open circle
                if s == 2 {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                        .frame(width: 14)
                } else {
                    Circle()
                        .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                        .frame(width: 12, height: 12)
                        .frame(width: 14)
                }
            }

            VStack(alignment: .leading, spacing: projectAssembling ? 0 : 3) {
                Text(task.name.uppercased())
                    .font(projectAssembling ? .smallCaption : .bodyBold)
                    .foregroundStyle(
                        projectAssembling && s == 2
                            ? OPSStyle.Colors.secondaryText
                            : OPSStyle.Colors.primaryText
                    )
                    .tracking(0.5)

                if !projectAssembling {
                    Text(statusLabel)
                        .font(.microLabel)
                        .foregroundStyle(statusColor)
                        .tracking(1)
                }
            }

            Spacer()

            if !projectAssembling && s == 2 {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(height: projectAssembling ? (projectChromeFading ? 34 : 26) : 48)
        .padding(.horizontal, projectAssembling ? (projectChromeFading ? 10 : 0) : 16)
        .padding(.vertical, projectAssembling ? (projectChromeFading ? 4 : 2) : 10)
        .background(
            Group {
                if !projectAssembling {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                } else if projectChromeFading {
                    // Detaching: individual card background appears as border draws
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .opacity(Double(taskDetachBorders[index]))
                }
            }
        )
        .overlay(
            Group {
                if !projectAssembling {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                } else if projectChromeFading {
                    // Detaching: individual border draws around each task
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .trim(from: 0, to: taskDetachBorders[index])
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                }
            }
        )
        .opacity(!projectAssembling && s == 2 ? 0.5 : 1.0)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: FLOATING DECK TASKS (Continuity Chain)
    // MARK: ─────────────────────────────────────────────────────────────────

    /// The 3 deck tasks rendered as persistent floating views.
    /// Their position/size morphs based on deckTaskPhase:
    /// .projectCard → compact rows at project card slot positions
    /// .detaching → same position, borders drawing, spacing increasing
    /// .calendarBar → gantt bar size at calendar slot positions
    /// .reviewCard → expanded to full swipe card shapes
    private var floatingDeckTasks: some View {
        let calIDs = ["cal_sandprep", "cal_stain", "cal_rail"]
        let tasks = TutorialData.taskCards
        let calSchedule = TutorialData.calendarSchedule.filter { $0.isDeckTask }

        return ForEach(0..<3, id: \.self) { i in
            let calID = calIDs[i]
            let task = tasks[i]
            let calTask = calSchedule[i]
            let isComplete = calTask.completesOnDay != nil

            // Determine frame based on phase
            let frame: CGRect = {
                switch deckTaskPhase {
                case .hidden:
                    return .zero
                case .projectCard, .detaching:
                    return projectCardSlotFrames[calID] ?? .zero
                case .calendarBar, .reviewCard:
                    return calendarSlotFrames[calID] ?? .zero
                }
            }()

            // Content based on phase
            ZStack {
                // Compact task row content (visible in projectCard/detaching phases)
                compactTaskContent(task: task, index: i, calTask: calTask)
                    .opacity(deckTaskPhase == .projectCard || deckTaskPhase == .detaching ? 1 : 0)

                // Gantt bar content (visible in calendarBar phase)
                ganttBarContent(calTask: calTask)
                    .opacity(deckTaskPhase == .calendarBar ? 1 : 0)

                // Review card content (visible in reviewCard phase — only for incomplete tasks)
                if let reviewIdx = calTask.reviewCardIndex {
                    extractedReviewContent(calTask: calTask, reviewIndex: reviewIdx)
                        .opacity(deckTaskPhase == .reviewCard ? 1 : 0)
                }
            }
            .frame(width: max(frame.width, 1), height: max(frame.height, 1))
            .background(
                RoundedRectangle(cornerRadius: deckTaskPhase == .reviewCard
                    ? OPSStyle.Layout.cardCornerRadius
                    : OPSStyle.Layout.smallCornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: deckTaskPhase == .reviewCard
                    ? OPSStyle.Layout.cardCornerRadius
                    : OPSStyle.Layout.smallCornerRadius)
                    .trim(from: 0, to: deckTaskPhase == .detaching ? taskDetachBorders[i] : 1)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .clipShape(RoundedRectangle(cornerRadius: deckTaskPhase == .reviewCard
                ? OPSStyle.Layout.cardCornerRadius
                : OPSStyle.Layout.smallCornerRadius))
            .position(x: frame.midX, y: frame.midY)
            // Completed deck tasks fade when calendar marks them as faded
            .opacity(calendarFadeCompleted && isComplete && deckTaskPhase == .calendarBar ? 0.1 : 1)
            .zIndex(10 + Double(3 - i)) // Above project card and calendar
        }
    }

    /// Compact task row content — matches the assembling project card appearance.
    /// Shows checkmark/circle, task name, and status.
    private func compactTaskContent(task: TutorialData.TaskCard, index: Int, calTask: TutorialData.CalendarScheduleTask) -> some View {
        let s = taskStatuses[index]

        return HStack(spacing: 8) {
            if s == 2 {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .frame(width: 14)
            } else {
                Circle()
                    .stroke(s == 1 ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.inactiveStatus, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .frame(width: 14)
            }

            Text(task.name.uppercased())
                .font(.smallCaption)
                .foregroundStyle(s == 2 ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.primaryText)
                .tracking(0.5)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
    }

    /// Gantt bar content — matches FlowCalendarWeek bar appearance.
    /// Color stripe, task name, project name.
    private func ganttBarContent(calTask: TutorialData.CalendarScheduleTask) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(calTask.color)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(calTask.name.uppercased())
                    .font(.custom("Mohave-Medium", size: 11))
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.3)
                    .lineLimit(1)

                Text(calTask.projectName)
                    .font(.custom("Kosugi-Regular", size: 8))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
    }

    /// Review card content — pixel-identical to FlowReviewCard layout.
    /// Shown when deck tasks expand from calendar bars to card shapes.
    private func extractedReviewContent(calTask: TutorialData.CalendarScheduleTask, reviewIndex: Int) -> some View {
        let card = TutorialData.reviewCards[reviewIndex]
        let showText = calendarExtractPhase >= 2
        let showWireframe = calendarExtractPhase >= 3

        return ZStack(alignment: .bottomLeading) {
            OPSStyle.Colors.cardBackgroundDark

            FlowWireframe(variant: reviewIndex)
                .opacity(showWireframe ? 0.22 : 0)

            VStack {
                Rectangle().fill(card.color).frame(height: 3)
                Spacer()
            }

            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                    startPoint: .top, endPoint: .bottom
                ).frame(height: 100)
                Spacer()
            }
            .opacity(showText ? 1 : 0)

            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center, endPoint: .bottom
            )
            .opacity(showText ? 1 : 0)

            VStack(alignment: .leading, spacing: 6) {
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .frame(width: 5, height: 5)
                    Text(card.daysAgo == 1 ? "1 DAY AGO" : "\(card.daysAgo) DAYS AGO")
                        .font(.microLabel)
                        .foregroundStyle(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .tracking(1)
                }
                Text(card.task.uppercased())
                    .font(.title)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 11))
                    Text(card.project.uppercased()).font(.caption)
                }.foregroundStyle(.white.opacity(0.7))
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill").font(.system(size: 11))
                    Text(card.client.uppercased()).font(.smallCaption)
                }.foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
            .padding(.bottom, 40)
            .opacity(showText ? 1 : 0)
        }
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 5: Review (merged with invoice)
    // MARK: ─────────────────────────────────────────────────────────────────

    private var reviewStackView: some View {
        let cards = TutorialData.reviewCards
        let remaining = Array(cards.dropFirst(reviewCurrentIndex))
        let visible: [(idx: Int, card: TutorialData.ReviewCard)] = Array(
            remaining.prefix(3).enumerated().map { (idx: $0.offset, card: $0.element) }
        ).reversed()

        return VStack(spacing: 0) {
            if reviewCurrentIndex < cards.count {
                Text("\(reviewCurrentIndex + 1) OF \(cards.count)")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .tracking(2)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .transition(.opacity)
            }

            ZStack {
                ForEach(visible, id: \.card.id) { item in
                    FlowReviewCard(
                        card: item.card,
                        cardIndex: reviewCurrentIndex + item.idx,
                        onSwiped: { direction in handleReviewSwipe(direction: direction) }
                    )
                    .scaleEffect(1.0 - (CGFloat(item.idx) * 0.03))
                    .offset(y: CGFloat(item.idx) * 8)
                    .allowsHitTesting(item.idx == 0 && showingCompletion == nil)
                    .zIndex(Double(3 - item.idx))
                }
            }

            Spacer().frame(height: 20)

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 11, weight: .medium))
                    Text("SKIP")
                        .font(.smallCaption)
                        .tracking(1.2)
                }
                .foregroundStyle(OPSStyle.Colors.tertiaryText)

                Spacer()

                HStack(spacing: 6) {
                    Text("COMPLETE")
                        .font(.smallCaption)
                        .tracking(1.2)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundStyle(OPSStyle.Colors.successStatus.opacity(0.7))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }

    /// Inline project completion card — shown after each right-swipe.
    /// Shows all tasks for that project checked off + INVOICE SENT.
    /// Unified swipe result card — works for both right (complete) and left (skip).
    /// Right: all tasks checked, INVOICE SENT. Left: task still open, X TASK(S) REMAINING.
    private func inlineSwipeResultCard(for cardIndex: Int, wasRight: Bool) -> some View {
        let card = TutorialData.reviewCards[cardIndex]
        let borderColor = wasRight ? OPSStyle.Colors.successStatus : OPSStyle.Colors.warningStatus

        return VStack(alignment: .leading, spacing: 0) {
            // Project header
            HStack(spacing: 10) {
                Image(systemName: wasRight ? "checkmark.circle.fill" : "clock.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(borderColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(card.project.uppercased())
                        .font(.bodyBold)
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .tracking(0.5)
                    Text(card.client)
                        .font(.smallCaption)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.bottom, 12)

            // Task checklist
            ForEach(Array(card.projectTasks.enumerated()), id: \.offset) { _, task in
                let isTheSwipedTask = !task.alreadyComplete
                let isComplete = task.alreadyComplete || (isTheSwipedTask && wasRight)

                HStack(spacing: 8) {
                    if isComplete {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(OPSStyle.Colors.successStatus)
                            .frame(width: 14)
                    } else {
                        Circle()
                            .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                            .frame(width: 12, height: 12)
                            .frame(width: 14)
                    }

                    Text(task.name.uppercased())
                        .font(.smallCaption)
                        .foregroundStyle(isComplete ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .tracking(0.5)

                    Spacer()

                    if isTheSwipedTask {
                        Text(wasRight ? "JUST NOW" : "SKIPPED")
                            .font(.microLabel)
                            .foregroundStyle(wasRight ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.warningStatus)
                            .tracking(1)
                    }
                }
                .padding(.vertical, 2)
            }

            // Footer: Invoice sent (right) or tasks remaining (left)
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 0.5)
                .padding(.vertical, 10)

            if wasRight {
                HStack(spacing: 8) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12))
                    Text("INVOICE SENT — \(TutorialData.formatCurrency(card.invoiceTotal))")
                        .font(.microLabel)
                        .tracking(1)
                }
                .foregroundStyle(OPSStyle.Colors.primaryAccent)
            } else {
                let remaining = card.projectTasks.filter { !$0.alreadyComplete }.count
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 12))
                    Text("\(remaining) TASK\(remaining == 1 ? "" : "S") REMAINING")
                        .font(.microLabel)
                        .tracking(1)
                }
                .foregroundStyle(OPSStyle.Colors.warningStatus)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(borderColor.opacity(0.2), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var allCaughtUpView: some View {
        VStack(spacing: 16) {
            Circle()
                .stroke(OPSStyle.Colors.successStatus.opacity(0.2), lineWidth: 1.5)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                )
                .scaleEffect(reviewDoneScale)

            Text("ALL CAUGHT UP")
                .font(.heading)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(2)
        }
        .opacity(reviewDoneOpacity)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 6: Accounting Insights + Closing
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Accounting insights — revenue, costs, profit. Visuals over numbers.
    /// Dynamic based on which projects the user swiped right/left.
    private var accountingInsightsView: some View {
        let allCards = TutorialData.reviewCards
        let allCosts = TutorialData.projectCosts

        // Revenue: right-swiped = full invoice, left-swiped = 50% deposit
        let invoiceEntries: [(card: TutorialData.ReviewCard, amount: Int, isPaid: Bool)] = swipeResults.indices.map { i in
            let card = allCards[i]
            let paid = swipeResults[i]
            return (card: card, amount: paid ? card.invoiceTotal : card.invoiceTotal / 2, isPaid: paid)
        }
        let totalRevenue = invoiceEntries.reduce(0) { $0 + $1.amount }

        // Costs: ALL projects incur costs regardless of swipe direction
        let totalCosts = allCosts.reduce(0) { $0 + $1.totalCost }

        // Profit
        let profit = totalRevenue - totalCosts

        return ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {

                // ── REVENUE SECTION ──
                Text("INVOICED & PAID")
                    .font(.status)
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .tracking(1.5)
                    .padding(.bottom, 12)

                // Invoice cards — staggered from right
                ForEach(0..<min(visibleInvoices, invoiceEntries.count), id: \.self) { i in
                    let entry = invoiceEntries[i]
                    invoiceCard(
                        project: entry.card.project,
                        client: entry.card.client,
                        amount: entry.amount,
                        color: entry.card.color,
                        isPaid: entry.isPaid
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }

                // Revenue bar — horizontal capsule filling proportionally
                revenueBar(current: invoiceBarProgress, total: totalRevenue, maxAmount: totalRevenue)
                    .padding(.top, 12)
                    .padding(.bottom, 24)

                // ── COSTS SECTION ──
                if showExpenses {
                    Text("COSTS FILED BY CREW")
                        .font(.status)
                        .foregroundStyle(OPSStyle.Colors.warningStatus)
                        .tracking(1.5)
                        .padding(.bottom, 12)
                        .transition(.opacity)

                    // Expense cards — staggered from left (opposite direction from revenue)
                    let expenses = TutorialData.expenseItems
                    ForEach(0..<min(visibleExpenses, expenses.count), id: \.self) { i in
                        expenseCard(item: expenses[i])
                            .transition(.move(edge: .leading).combined(with: .opacity))
                    }

                    // Expense bar — same scale as revenue for visual comparison
                    expenseBar(current: expenseBarProgress, total: totalCosts, maxAmount: totalRevenue)
                        .padding(.top, 12)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }

                // ── PROFIT SECTION ──
                if showProfit {
                    profitSection(revenue: totalRevenue, costs: totalCosts, profit: profit)
                        .transition(.opacity)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Individual invoice card — project color stripe, name, client, amount, paid/deposit stamp.
    private func invoiceCard(project: String, client: String, amount: Int, color: Color, isPaid: Bool) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 1)
                .fill(color)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.uppercased())
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.3)
                Text(client)
                    .font(.smallCaption)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(TutorialData.formatCurrency(amount))
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                Text(isPaid ? "PAID" : "DEPOSIT")
                    .font(.microLabel)
                    .foregroundStyle(isPaid ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                    .tracking(1)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBorderSubtle, lineWidth: 0.5)
        )
        .padding(.bottom, 6)
    }

    /// Expense receipt card — category icon, description, amount. Amber accents. Smaller than invoice cards.
    private func expenseCard(item: TutorialData.ExpenseItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon)
                .font(.system(size: 12))
                .foregroundStyle(OPSStyle.Colors.warningStatus)
                .frame(width: 20)

            Text(item.description.uppercased())
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
                .tracking(0.3)
                .lineLimit(1)

            Spacer()

            Text(TutorialData.formatCurrency(item.amount))
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.primaryText)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.15), lineWidth: 0.5)
        )
        .padding(.bottom, 4)
    }

    /// Horizontal capsule progress bar. `current` is 0→1 fill progress.
    /// `total` is the displayed dollar amount. `maxAmount` is the scale reference.
    private func revenueBar(current: CGFloat, total: Int, maxAmount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: geo.size.width * current)
                }
            }
            .frame(height: 6)

            if current > 0 {
                Text(TutorialData.formatCurrency(total))
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
            }
        }
    }

    private func expenseBar(current: CGFloat, total: Int, maxAmount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let scale = maxAmount > 0 ? CGFloat(total) / CGFloat(maxAmount) : 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.06))
                    Capsule()
                        .fill(OPSStyle.Colors.warningStatus)
                        .frame(width: geo.size.width * scale * current)
                }
            }
            .frame(height: 6)

            if current > 0 {
                Text(TutorialData.formatCurrency(total))
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.warningStatus)
            }
        }
    }

    /// Profit visualization — revenue bar, minus expenses bar, equals profit bar.
    /// The visual ratio communicates margin instantly without reading numbers.
    /// Handles negative profit (all projects left-swiped → deposits < costs).
    private func profitSection(revenue: Int, costs: Int, profit: Int) -> some View {
        let isNegative = profit < 0
        let marginPercent = revenue > 0 ? Int(Double(profit) / Double(revenue) * 100) : 0

        return VStack(alignment: .leading, spacing: 12) {
            Text("WHAT YOU KEEP")
                .font(.status)
                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                .tracking(1.5)

            // Stacked bars showing ratio visually
            VStack(alignment: .leading, spacing: 8) {
                // Revenue reference bar (full width, success green, dimmed)
                HStack(spacing: 8) {
                    Text("IN")
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                        .tracking(1)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { geo in
                        Capsule()
                            .fill(OPSStyle.Colors.successStatus.opacity(0.3))
                            .frame(width: geo.size.width)
                    }
                    .frame(height: 4)
                }

                // Costs bar (proportional to revenue, amber)
                HStack(spacing: 8) {
                    Text("OUT")
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                        .tracking(1)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { geo in
                        let costRatio = revenue > 0 ? CGFloat(costs) / CGFloat(revenue) : 0
                        Capsule()
                            .fill(OPSStyle.Colors.warningStatus.opacity(0.5))
                            .frame(width: geo.size.width * costRatio)
                    }
                    .frame(height: 4)
                }

                // Profit bar (the difference, primary accent, full brightness)
                HStack(spacing: 8) {
                    Text("KEEP")
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)
                        .tracking(1)
                        .frame(width: 30, alignment: .trailing)
                    GeometryReader { geo in
                        let profitRatio = revenue > 0 ? CGFloat(profit) / CGFloat(revenue) : 0
                        Capsule()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: geo.size.width * max(profitRatio * profitBarProgress, 0))
                    }
                    .frame(height: 6) // Slightly taller — this is the hero
                }
            }

            // Net profit amount (or shortfall warning)
            if profitBarProgress > 0 {
                HStack {
                    Text(isNegative
                        ? "-\(TutorialData.formatCurrency(abs(profit)))"
                        : TutorialData.formatCurrency(profit))
                        .font(.headingLarge)
                        .foregroundStyle(isNegative ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryText)
                    Spacer()
                    Text(isNegative
                        ? "APPROVE MORE JOBS"
                        : "\(marginPercent)% MARGIN")
                        .font(.status)
                        .foregroundStyle(isNegative ? OPSStyle.Colors.warningStatus : OPSStyle.Colors.primaryAccent)
                        .tracking(1.5)
                }
                .padding(.top, 4)
            }
        }
    }


    /// 13 steps of running a job. Written in one at a time.
    /// 11 get struck through (OPS handles them). 2 survive (SITE VISIT, THE WORK).
    /// Struck lines compress away, survivors center. Tagline appears. CTA.
    private var closingSequenceView: some View {
        let steps = TutorialData.closingSteps

        // Pre-compute the ordered indices of OPS-handled steps for strikethrough mapping
        let opsIndices = steps.enumerated().filter { $0.element.opsHandles }.map { $0.offset }

        return VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .center, spacing: closingCollapsed ? 0 : 6) {
                ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                    let isVisible = idx < closingStepsVisible
                    // Map closingStrikeCount to actual step indices:
                    // closingStrikeCount=1 means opsIndices[0] is struck, =2 means [0] and [1], etc.
                    let isStruck = step.opsHandles
                        && (opsIndices.firstIndex(of: idx).map { $0 < closingStrikeCount } ?? false)
                    let shouldHide = closingCollapsed && isStruck

                    if !shouldHide {
                        ZStack {
                            Text(step.text)
                                .font(step.opsHandles ? .heading : .headingBold)
                                .foregroundStyle(
                                    isStruck ? OPSStyle.Colors.tertiaryText :
                                    !step.opsHandles ? OPSStyle.Colors.primaryText :
                                    OPSStyle.Colors.secondaryText
                                )
                                .tracking(2)
                                .strikethrough(isStruck, color: OPSStyle.Colors.tertiaryText)

                            // Emphasis glow on surviving steps after collapse
                            if closingCollapsed && !step.opsHandles {
                                Text(step.text)
                                    .font(.headingBold)
                                    .foregroundStyle(OPSStyle.Colors.primaryAccent)
                                    .tracking(2)
                            }
                        }
                        .opacity(isVisible ? 1 : 0)
                        .transition(.opacity)
                    }
                }
            }

            // Tagline — appears after collapse
            if showClosingMessage {
                VStack(spacing: 8) {
                    Text("11 STEPS. HANDLED.")
                        .font(.heading)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                        .tracking(2)

                    Text("YOU SHOW UP. YOU BUILD. WE RUN THE REST.")
                        .font(.caption)
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)
                        .tracking(1.5)
                }
                .padding(.top, 32)
                .transition(.opacity)
            }

            Spacer()

            // CTA
            if showCTA {
                VStack(spacing: 16) {
                    Button {
                        state.ctaTapped(action: "getStarted")
                        onComplete()
                    } label: {
                        Text("GET STARTED")
                            .font(.button)
                            .tracking(1)
                            .foregroundStyle(Color.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                    .fill(OPSStyle.Colors.primaryAccent)
                            )
                    }

                    Button {
                        state.ctaTapped(action: "skip")
                        onComplete()
                    } label: {
                        Text("SKIP")
                            .font(.caption)
                            .foregroundStyle(OPSStyle.Colors.tertiaryText)
                            .tracking(1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
    }

    // MARK: ═══════════════════════════════════════════════════════════════════
    // MARK: ANIMATION SEQUENCES
    // MARK: ═══════════════════════════════════════════════════════════════════

    // MARK: Begin Tutorial

    private func beginTutorial() {
        state.start()

        guard !reduceMotion else {
            showCard = true
            cardOffset = 0
            clientChars = clientText.count
            projectChars = projectText.count
            showLeadSource = true
            leadGlow = 1
            leadInteractive = true
            headerOpacity = 1
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            showCard = true
            withAnimation(.easeOut(duration: 0.35)) { cardOffset = 0 }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                TutorialHaptics.arrival()
                startTypewriter()
            }
        }

        showHeader()
    }

    private func showHeader() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
        }
    }

    // MARK: Typewriter

    private func startTypewriter() {
        var totalChars = 0
        let allChars = clientText.count + projectText.count

        typewriterTimer = Timer.scheduledTimer(withTimeInterval: charInterval, repeats: true) { timer in
            totalChars += 1
            if totalChars <= clientText.count {
                clientChars = totalChars
            } else {
                let pi = totalChars - clientText.count
                if pi == 1 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { projectChars = 1 }
                    return
                }
                if pi <= projectText.count { projectChars = pi }
            }
            if totalChars >= allChars {
                timer.invalidate()
                finishTypewriter()
            }
        }
    }

    private func finishTypewriter() {
        withAnimation(.easeOut(duration: 0.25)) { showLeadSource = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            withAnimation(.easeOut(duration: 0.5)) { leadGlow = 1 }
            leadInteractive = true
        }
    }

    // MARK: Lead Tap → Estimate Morph

    private func handleLeadTap() {
        guard leadInteractive else { return }
        leadInteractive = false
        TutorialHaptics.commit()
        state.advancePhase()

        withAnimation(.easeOut(duration: 0.25)) {
            isEstimateMode = true
            leadGlow = 0
        }

        withAnimation(.easeOut(duration: 0.2)) { headerOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
        }

        let baseDelay = 0.4
        for i in 0..<TutorialData.lineItems.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + baseDelay + (Double(i) * 0.12)) {
                withAnimation(.easeOut(duration: 0.2)) { visibleLineItems = i + 1 }
                TutorialHaptics.arrival()
            }
        }

        let afterItems = baseDelay + (Double(TutorialData.lineItems.count) * 0.12) + 0.15
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems) {
            withAnimation(.easeOut(duration: 0.2)) { showDivider = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems + 0.15) {
            withAnimation(.easeOut(duration: 0.2)) { showTotal = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + afterItems + 0.4) {
            withAnimation(.easeOut(duration: 0.2)) { showSendEstimate = true }
        }
    }

    // MARK: Send Estimate → Approved

    private func handleSendEstimate() {
        TutorialHaptics.commit()
        state.advancePhase()

        withAnimation(.easeOut(duration: 0.15)) { showSendEstimate = false }

        withAnimation(.easeOut(duration: 0.2)) { headerOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            withAnimation(.easeOut(duration: 0.3)) { showApproval = true }
            TutorialHaptics.milestone()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            withAnimation(.easeOut(duration: 0.3)) {
                showDivider = false
                showTotal = false
                estimateShellOpacity = 0.0
            }

            for i in 0..<TutorialData.laborItems.count {
                DispatchQueue.main.asyncAfter(deadline: .now() + (Double(i) * 0.15)) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        peeledCount = i + 1
                    }
                    TutorialHaptics.arrival()
                }
            }
        }

        let crewDelay = 1.8 + (Double(TutorialData.laborItems.count) * 0.15) + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + crewDelay) {
            withAnimation(.easeOut(duration: 0.3)) { showCrewOnTasks = true }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + crewDelay + 0.1) { showCard = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + crewDelay + 0.5) {
            withAnimation(.easeOut(duration: 0.3)) { showContinue = true }
        }
    }

    // MARK: Continue Handler

    private func handleContinue() {
        TutorialHaptics.commit()
        withAnimation(.easeOut(duration: 0.15)) { showContinue = false }

        switch state.currentPhase {
        case .estimateApproved: transitionToCrewExecution()
        case .crewExecutes:     transitionToReview()
        default: break
        }
    }

    // MARK: → Crew Execution (2 of 3 tasks complete, project assembles)

    private func transitionToCrewExecution() {
        state.advancePhase()

        withAnimation(.easeOut(duration: 0.2)) {
            showApproval = false
            peeledCount = 0
            showCrewOnTasks = false
        }

        withAnimation(.easeOut(duration: 0.2)) { headerOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
        }

        guard !reduceMotion else {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
            taskStatuses = [2, 2, 1]
            projectAssembling = true
            borderDrawProgress = 1
            cardBgOpacity = 1
            projectTitleChars = TutorialData.projectTitle.count
            progressBarValue = 0.66
            showContinue = true
            return
        }

        // Only 2 of 3 tasks complete. Railing Touch-Up stays IN PROGRESS.
        // This creates the setup for the review step.
        for i in 0..<2 {
            let base = 0.3 + (Double(i) * 1.6)
            DispatchQueue.main.asyncAfter(deadline: .now() + base) {
                withAnimation(.easeOut(duration: 0.2)) { taskStatuses[i] = 1 }
                TutorialHaptics.arrival()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + base + 1.0) {
                withAnimation(.easeOut(duration: 0.2)) { taskStatuses[i] = 2 }
                TutorialHaptics.arrival()
            }
        }

        // Task 2 (Railing Touch-Up) goes to IN PROGRESS and stays
        let task2Base = 0.3 + 2 * 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + task2Base) {
            withAnimation(.easeOut(duration: 0.2)) { taskStatuses[2] = 1 }
            TutorialHaptics.arrival()
        }

        // ── ASSEMBLY: Task cards morph into project card ──
        let assemblyStart = task2Base + 1.2

        // Step 1: Cards shrink, individual backgrounds fade, spacing compresses
        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart) {
            // dampingFraction 0.8 = smooth morph, no bounce
            withAnimation(.easeOut(duration: 0.4)) {
                projectAssembling = true
            }
        }

        // Step 2: Card background fades in (wrapping the compact items)
        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) { cardBgOpacity = 1 }
        }

        // Step 3: Border draws around the group (0 → 1 over 0.6s)
        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.4) {
            withAnimation(.easeOut(duration: 0.6)) { borderDrawProgress = 1 }
            TutorialHaptics.commit()
        }

        // Step 4: Project title types in
        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.8) {
            startProjectTitleTypewriter()
        }

        // Step 5: Progress bar fills to 2/3
        let titleDone = assemblyStart + 0.8 + (Double(TutorialData.projectTitle.count) * 0.035) + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + titleDone) {
            withAnimation(.easeOut(duration: 0.5)) { progressBarValue = 0.66 }
        }

        // Step 6: CONTINUE
        DispatchQueue.main.asyncAfter(deadline: .now() + titleDone + 0.8) {
            withAnimation(.easeOut(duration: 0.3)) { showContinue = true }
        }
    }

    private func startProjectTitleTypewriter() {
        let title = TutorialData.projectTitle.uppercased()
        var charCount = 0

        projectTitleTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            charCount += 1
            projectTitleChars = charCount
            if charCount >= title.count {
                timer.invalidate()
            }
        }
    }

    // MARK: → Review

    private func transitionToReview() {
        // NOTE: state.advancePhase() is DEFERRED until tasks fly to calendar (Stage 4).
        // Calling it here would change currentPhase from .crewExecutes → .weeklyReview,
        // which immediately hides the assemblingProjectView (and all task rows) before
        // any chrome dissolve or border draw animation can run.

        let schedule = TutorialData.calendarSchedule

        guard !reduceMotion else {
            // Reduced motion: skip calendar, crossfade to review
            state.advancePhase()
            hideProjectCard = true
            showReviewStack = true
            return
        }

        let deckTasks = schedule.filter { $0.isDeckTask }
        let otherTasks = schedule.filter { !$0.isDeckTask }
        var t: Double = 0.3

        // ═══════════════════════════════════════════════════════════
        // STAGE 1: Project card chrome dissolves
        // Card bg, border, title, progress bar fade out.
        // Task rows remain visible, spacing increases.
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) {
                projectChromeFading = true
                borderDrawProgress = 0
                cardBgOpacity = 0
                progressBarValue = 0
                projectTitleChars = 0
            }
        }
        t += 0.5

        // ═══════════════════════════════════════════════════════════
        // STAGE 2: Individual borders draw around each task
        // One by one — each task becomes a standalone bordered card
        // ═══════════════════════════════════════════════════════════

        for i in 0..<3 {
            let drawTime = t + Double(i) * 0.3
            DispatchQueue.main.asyncAfter(deadline: .now() + drawTime) {
                withAnimation(.easeOut(duration: 0.3)) {
                    taskDetachBorders[i] = 1
                }
                TutorialHaptics.arrival()
            }
        }
        t += 3 * 0.3 + 0.3

        // ═══════════════════════════════════════════════════════════
        // STAGE 3: Calendar grid appears (empty, week overview)
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.35)) { showCalendar = true }
        }
        t += 0.2 // Brief overlap — calendar grid draws behind task rows

        // ═══════════════════════════════════════════════════════════
        // STAGE 4: Project card slides up, deck tasks slide down into calendar
        // Task rows exit upward via .move(edge: .top) on assemblingProjectView.
        // Deck bars enter from above via .move(edge: .top) transition, staggered.
        // Phase advances, header transitions to "END OF THE WEEK".
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            state.advancePhase()

            // Header transition
            withAnimation(.easeOut(duration: 0.2)) { headerOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
            }

            // Project card task rows slide up and out
            withAnimation(.easeOut(duration: 0.3)) {
                hideProjectCard = true
            }
        }

        // Deck task bars slide down from top of calendar, one at a time
        for (idx, task) in deckTasks.enumerated() {
            let flyTime = t + 0.15 + Double(idx) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + flyTime) {
                withAnimation(.easeOut(duration: 0.35)) {
                    _ = calendarVisibleTasks.insert(task.id)
                }
                TutorialHaptics.arrival()
            }
        }
        t += 0.15 + Double(deckTasks.count) * 0.2 + 0.2

        // ═══════════════════════════════════════════════════════════
        // STAGE 5: Other tasks appear one at a time
        // ═══════════════════════════════════════════════════════════

        for (idx, task) in otherTasks.enumerated() {
            let addTime = t + Double(idx) * 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + addTime) {
                withAnimation(.easeOut(duration: 0.2)) {
                    _ = calendarVisibleTasks.insert(task.id)
                }
            }
        }
        t += Double(otherTasks.count) * 0.12 + 0.4

        // ═══════════════════════════════════════════════════════════
        // STAGE 6: Day-by-day focus — column expands to full width,
        // others collapse. Mark completions with haptics.
        // ═══════════════════════════════════════════════════════════

        for day in 0..<5 {
            let dayStart = t

            DispatchQueue.main.asyncAfter(deadline: .now() + dayStart) {
                withAnimation(.easeOut(duration: 0.3)) {
                    calendarFocusDay = day
                }
                TutorialHaptics.arrival()
            }
            t += 0.4

            let dayCompletions = schedule.filter { $0.completesOnDay == day }
            for task in dayCompletions {
                let completeTime = t
                DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        _ = calendarCompletedTasks.insert(task.id)
                    }
                    TutorialHaptics.arrival()
                }
                t += 0.3
            }

            t += 0.25
        }

        // ═══════════════════════════════════════════════════════════
        // STAGE 7: Zoom back out to week overview
        // ═══════════════════════════════════════════════════════════

        let zoomOutTime = t
        DispatchQueue.main.asyncAfter(deadline: .now() + zoomOutTime) {
            withAnimation(.easeOut(duration: 0.35)) {
                calendarFocusDay = -1
            }
        }
        t += 0.5

        // ═══════════════════════════════════════════════════════════
        // STAGE 8: Completed tasks fade, incomplete stay bright
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeIn(duration: 0.4)) {
                calendarFadeCompleted = true
            }
        }
        t += 0.8

        // ═══════════════════════════════════════════════════════════
        // STAGE 9: Header — "4 TASKS NOT COMPLETE — MARKED FOR REVIEW"
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCalendarHeader = true
            }
        }
        t += 1.5

        // ═══════════════════════════════════════════════════════════
        // STAGE 10: Incomplete bars expand and stack into card shapes
        // Grid, labels, completed bars fade. Bars physically grow.
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.5)) {
                calendarExtractPhase = 1
            }
            TutorialHaptics.arrival()
        }
        t += 0.7

        // ═══════════════════════════════════════════════════════════
        // STAGE 11: Titles appear on expanded cards
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                calendarExtractPhase = 2
            }
        }
        t += 0.4

        // ═══════════════════════════════════════════════════════════
        // STAGE 12: Wireframe illustrations draw in
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                calendarExtractPhase = 3
            }
        }
        t += 0.6

        // ═══════════════════════════════════════════════════════════
        // STAGE 13: Swap to actual review swipe cards (invisible handoff)
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) {
                showCalendar = false
                showCalendarHeader = false
                showReviewStack = true
            }
        }
    }

    // MARK: Review Swipe (with inline project completion on right-swipe)

    private func handleReviewSwipe(direction: String) {
        let wasRight = direction == "right"
        let justSwipedIndex = reviewCurrentIndex

        swipeResults.append(wasRight)
        state.recordSwipe(cardIndex: reviewCurrentIndex, direction: direction)

        withAnimation(.easeOut(duration: 0.15)) {
            reviewCurrentIndex += 1
        }

        // Both right AND left swipes show a result card.
        // Right = project complete + invoice sent. Left = task still open.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            showingCompletion = justSwipedIndex
            withAnimation(.easeOut(duration: 0.3)) { completionOpacity = 1 }
            if wasRight { TutorialHaptics.milestone() }
            // No haptic on left-swipe result — skip is deliberate non-action
        }

        // Hold result card, then dismiss with delay before next card
        let holdTime: Double = wasRight ? 2.0 : 1.4 // right holds longer (more to read)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 + holdTime) {
            withAnimation(.easeOut(duration: 0.25)) { completionOpacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                showingCompletion = nil
                // Extra delay after last card before advancing
                let isLast = reviewCurrentIndex >= TutorialData.reviewCards.count
                DispatchQueue.main.asyncAfter(deadline: .now() + (isLast ? 0.6 : 0)) {
                    checkIfReviewDone()
                }
            }
        }
    }

    private func checkIfReviewDone() {
        if reviewCurrentIndex >= TutorialData.reviewCards.count {
            showAllCaughtUp()
        }
    }

    private func showAllCaughtUp() {
        withAnimation(.easeOut(duration: 0.2)) { showReviewStack = false }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            TutorialHaptics.milestone()

            withAnimation(.easeOut(duration: 0.4)) {
                showReviewDone = true
                reviewDoneOpacity = 1
                reviewDoneScale = 1.0
            }
        }

        // Auto-advance to payment step
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
            transitionToAccounting()
        }
    }

    // MARK: → Accounting Insights

    private func transitionToAccounting() {
        state.advancePhase() // → .invoiceAndPay

        withAnimation(.easeOut(duration: 0.2)) {
            showReviewDone = false
            reviewDoneOpacity = 0
        }

        // Header transition
        withAnimation(.easeOut(duration: 0.2)) { headerOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) { headerOpacity = 1 }
        }

        guard !reduceMotion else {
            // Reduced motion: show final state immediately, then go to closing
            showAccounting = true
            visibleInvoices = swipeResults.count
            invoiceBarProgress = 1
            showExpenses = true
            visibleExpenses = TutorialData.expenseItems.count
            expenseBarProgress = 1
            showProfit = true
            profitBarProgress = 1
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showAccounting = false
                showClosing = true
                closingStepsVisible = TutorialData.closingSteps.count
                closingStrikeCount = TutorialData.closingSteps.filter(\.opsHandles).count
                closingCollapsed = true
                showClosingMessage = true
                showCTA = true
            }
            return
        }

        let allExpenses = TutorialData.expenseItems
        var t: Double = 0.4

        // ═══════════════════════════════════════════════════════════
        // SCENE 1: Revenue — invoice cards slide in from right
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) { showAccounting = true }
        }
        t += 0.4

        // Stagger invoice cards (one per review card — 4 total)
        for i in 0..<swipeResults.count {
            let cardTime = t + Double(i) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + cardTime) {
                withAnimation(.easeOut(duration: 0.25)) { visibleInvoices = i + 1 }
                TutorialHaptics.arrival()
            }
        }
        t += Double(swipeResults.count) * 0.2 + 0.2

        // Revenue bar fills
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.6)) { invoiceBarProgress = 1 }
        }
        t += 0.8

        // ═══════════════════════════════════════════════════════════
        // SCENE 2: Costs — expense cards slide in from left
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) { showExpenses = true }
        }
        t += 0.3

        // Stagger expense cards
        for i in 0..<allExpenses.count {
            let expTime = t + Double(i) * 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + expTime) {
                withAnimation(.easeOut(duration: 0.2)) { visibleExpenses = i + 1 }
            }
        }
        t += Double(allExpenses.count) * 0.15 + 0.2

        // Expense bar fills
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.5)) { expenseBarProgress = 1 }
        }
        t += 0.7

        // ═══════════════════════════════════════════════════════════
        // SCENE 3: Profit — the money shot
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) { showProfit = true }
        }
        t += 0.3

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.6)) { profitBarProgress = 1 }
            TutorialHaptics.milestone()
        }
        t += 1.5

        // ═══════════════════════════════════════════════════════════
        // SCENE 4: Transition to closing sequence
        // ═══════════════════════════════════════════════════════════

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeIn(duration: 0.3)) { showAccounting = false }
        }
        t += 0.5

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) { showClosing = true }
            startClosingSequence()
        }
    }

    // MARK: Closing Sequence

    private func startClosingSequence() {
        let steps = TutorialData.closingSteps
        var t: Double = 0.3

        // ── Phase A: Write in all 13 steps one at a time ──
        for i in 0..<steps.count {
            let writeTime = t + Double(i) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + writeTime) {
                withAnimation(.easeOut(duration: 0.15)) { closingStepsVisible = i + 1 }
                TutorialHaptics.arrival()
            }
        }
        t += Double(steps.count) * 0.2 + 0.8 // Hold — all 13 visible

        // ── Phase B: Strike through OPS-handled steps one at a time ──
        let opsStepCount = steps.filter(\.opsHandles).count
        for i in 0..<opsStepCount {
            let strikeTime = t + Double(i) * 0.12
            DispatchQueue.main.asyncAfter(deadline: .now() + strikeTime) {
                withAnimation(.easeOut(duration: 0.15)) { closingStrikeCount = i + 1 }
            }
        }
        t += Double(opsStepCount) * 0.12 + 0.8 // Hold — all struck

        // ── Phase C: Collapse struck lines, survivors center ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) { closingCollapsed = true }
            TutorialHaptics.milestone()
        }
        t += 0.6

        // ── Phase D: Tagline appears ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) { showClosingMessage = true }
        }
        t += 0.8

        // ── Phase E: CTA ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) { showCTA = true }
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Calendar Week View
// MARK: ═══════════════════════════════════════════════════════════════════════

/// Gantt-style week calendar with animated column widths and bar extraction.
///
/// Architecture:
/// - Week mode (focusDay == -1): 5 equal columns, compact task bars
/// - Day mode (focusDay == 0-4): focused column expands, others collapse
/// - extractPhase 0: normal calendar
/// - extractPhase 1: incomplete bars physically expand and stack into card shapes;
///                    grid, labels, completed bars fade out
/// - extractPhase 2: titles appear on expanded cards
/// - extractPhase 3: wireframe illustrations draw in
/// - All animations use easeOut (no springs — brand: military tactical minimalist)
private struct FlowCalendarWeek: View {
    let visibleTasks: Set<String>
    let completedTasks: Set<String>
    let focusDay: Int                  // -1 = week overview, 0-4 = focused day
    let fadeCompleted: Bool
    let extractPhase: Int              // 0=normal, 1=expand, 2=titles, 3=wireframe

    private let schedule = TutorialData.calendarSchedule
    private let dayLabels = TutorialData.dayLabels
    private let totalRows = 6
    private let barHeight: CGFloat = 28
    private let barSpacing: CGFloat = 5
    private let headerHeight: CGFloat = 36
    private let barInset: CGFloat = 2

    private var isExtracting: Bool { extractPhase > 0 }

    private func colWidth(_ day: Int, in total: CGFloat) -> CGFloat {
        if focusDay < 0 { return total / 5.0 }
        return day == focusDay ? total : 0
    }

    private func colX(_ day: Int, in total: CGFloat) -> CGFloat {
        (0..<day).reduce(CGFloat(0)) { $0 + colWidth($1, in: total) }
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let extractedCardW = w - 32
            let extractedCardH = extractedCardW / 0.7
            let normalCalH = headerHeight + CGFloat(totalRows) * (barHeight + barSpacing) + 8

            ZStack(alignment: .topLeading) {
                // ── Day column separators ──
                ForEach(1..<5, id: \.self) { i in
                    let cw = colWidth(i, in: w)
                    Rectangle()
                        .fill(OPSStyle.Colors.separator.opacity(0.3))
                        .frame(width: 0.5, height: normalCalH - headerHeight)
                        .offset(x: colX(i, in: w), y: headerHeight)
                        .opacity(isExtracting ? 0 : (cw > 1 ? 1 : 0))
                }

                // ── Day labels ──
                ForEach(0..<5, id: \.self) { day in
                    let cw = colWidth(day, in: w)
                    let weekWidth = w / 5.0

                    VStack(spacing: 1) {
                        Text(dayLabels[day])
                            .font(.custom("Mohave-Medium", size: 11))
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(
                                day == 4 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText
                            )
                            .tracking(1)

                        if day == 4 {
                            Text("TODAY")
                                .font(.custom("Kosugi-Regular", size: 8))
                                .minimumScaleFactor(0.5)
                                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                                .tracking(0.5)
                        }

                        Rectangle()
                            .fill(day == 4 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.separator)
                            .frame(width: max(cw - 8, 0), height: day == 4 ? 1.5 : 0.5)
                    }
                    .frame(width: focusDay >= 0 && day == focusDay ? w : weekWidth)
                    .offset(x: focusDay >= 0 && day == focusDay ? 0 : colX(day, in: w))
                    .opacity(isExtracting ? 0 : (focusDay < 0 || day == focusDay ? 1 : 0))
                }

                // ── Task bars ──
                ForEach(schedule) { task in
                    if visibleTasks.contains(task.id) {
                        let isComplete = completedTasks.contains(task.id)
                        let isIncomplete = task.completesOnDay == nil

                        // Normal calendar position
                        let startX = colX(task.startDay, in: w) + barInset
                        let endX = colX(task.endDay, in: w) + colWidth(task.endDay, in: w) - barInset
                        let normalWidth = max(endX - startX, 0)
                        let normalY = headerHeight + 4 + CGFloat(task.row) * (barHeight + barSpacing)

                        // Extracted card position (stacked deck)
                        let extractIdx = CGFloat(task.reviewCardIndex ?? 0)
                        let shouldExtract = isExtracting && isIncomplete

                        let bw = shouldExtract ? extractedCardW : normalWidth
                        let bh = shouldExtract ? extractedCardH : barHeight
                        let bx = shouldExtract ? 16 : startX
                        let by = shouldExtract ? (extractIdx * 8 + 16) : normalY

                        ZStack {
                            // Gantt bar content (visible when NOT extracting)
                            ganttBar(task: task, isComplete: isComplete, isIncomplete: isIncomplete)
                                .opacity(shouldExtract ? 0 : 1)

                            // Extracted card content (visible when extracting)
                            if isIncomplete {
                                extractedCard(task: task)
                                    .opacity(shouldExtract ? 1 : 0)
                            }
                        }
                        .frame(width: bw, height: bh)
                        .clipShape(RoundedRectangle(cornerRadius: shouldExtract
                            ? OPSStyle.Layout.cardCornerRadius
                            : OPSStyle.Layout.smallCornerRadius))
                        .overlay(
                            RoundedRectangle(cornerRadius: shouldExtract
                                ? OPSStyle.Layout.cardCornerRadius
                                : OPSStyle.Layout.smallCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                .opacity(shouldExtract ? 1 : 0.5)
                        )
                        .offset(x: bx, y: by)
                        .scaleEffect(shouldExtract ? (1.0 - extractIdx * 0.03) : 1.0,
                                     anchor: .top)
                        .zIndex(shouldExtract ? Double(10 + 4 - (task.reviewCardIndex ?? 0)) : 0)
                        .opacity(
                            shouldExtract ? 1.0 :
                            isExtracting ? 0 :           // Hide completed during extraction
                            bw < 2 ? 0 :
                            fadeCompleted && isComplete ? 0.1 :
                            isComplete ? 0.5 : 1.0
                        )
                        // Deck tasks slide down from top (entering from project card above);
                        // other tasks fade in normally
                        .transition(task.isDeckTask
                            ? .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity)
                            : .opacity)
                    }
                }
            }
        }
        .frame(height: isExtracting ? 500 : (headerHeight + CGFloat(totalRows) * (barHeight + barSpacing) + 8))
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
                .opacity(isExtracting ? 0 : 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                .opacity(isExtracting ? 0 : 1)
        )
    }

    // MARK: - Gantt Bar (normal calendar bar)

    private func ganttBar(task: TutorialData.CalendarScheduleTask, isComplete: Bool, isIncomplete: Bool) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1)
                .fill(task.color)
                .frame(width: 2)

            VStack(alignment: .leading, spacing: 0) {
                Text(task.name.uppercased())
                    .font(.custom("Mohave-Medium", size: 11))
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(isComplete ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .tracking(0.3)
                    .lineLimit(1)

                Text(task.projectName)
                    .font(.custom("Kosugi-Regular", size: 8))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(OPSStyle.Colors.successStatus)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(
                    isIncomplete && fadeCompleted
                        ? task.color.opacity(0.12)
                        : OPSStyle.Colors.cardBackgroundDark
                )
        )
    }

    // MARK: - Extracted Card (review card preview during extraction)

    /// Pixel-identical to FlowReviewCard layout. Content phases:
    /// extractPhase 1 = colored background only (bar expanding)
    /// extractPhase 2 = titles + gradients appear
    /// extractPhase 3 = wireframe illustration draws in
    private func extractedCard(task: TutorialData.CalendarScheduleTask) -> some View {
        let cardIdx = task.reviewCardIndex ?? 0
        let card = TutorialData.reviewCards[cardIdx]
        let showText = extractPhase >= 2
        let showWireframe = extractPhase >= 3

        return ZStack(alignment: .bottomLeading) {
            // Background
            OPSStyle.Colors.cardBackgroundDark

            // Wireframe (phase 3)
            FlowWireframe(variant: cardIdx)
                .opacity(showWireframe ? 0.22 : 0)

            // Color stripe at top
            VStack {
                Rectangle()
                    .fill(card.color)
                    .frame(height: 3)
                Spacer()
            }

            // Top gradient (phase 2+)
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                Spacer()
            }
            .opacity(showText ? 1 : 0)

            // Bottom gradient (phase 2+)
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .opacity(showText ? 1 : 0)

            // Info overlay (phase 2+ — identical to FlowReviewCard)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .frame(width: 5, height: 5)
                    Text(card.daysAgo == 1 ? "1 DAY AGO" : "\(card.daysAgo) DAYS AGO")
                        .font(.microLabel)
                        .foregroundStyle(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .tracking(1)
                }

                Text(card.task.uppercased())
                    .font(.title)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                    Text(card.project.uppercased())
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.7))

                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 11))
                    Text(card.client.uppercased())
                        .font(.smallCaption)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
            .padding(.bottom, 40)
            .opacity(showText ? 1 : 0)
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Review Swipe Card
// MARK: ═══════════════════════════════════════════════════════════════════════

/// Full-bleed review card styled after the real TaskSwipeCardView.
/// Wireframe illustration background, color stripe, bottom info overlay.
private struct FlowReviewCard: View {

    let card: TutorialData.ReviewCard
    let cardIndex: Int
    let onSwiped: (String) -> Void

    @State private var dragOffset: CGSize = .zero
    @State private var committed = false

    private let threshold: CGFloat = 120

    private var swipeProgress: Double {
        min(abs(dragOffset.width) / threshold, 1.0)
    }

    private var isSwipingRight: Bool {
        dragOffset.width > 0
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            // Full-bleed wireframe (bright enough to see — 22% opacity)
            ZStack {
                OPSStyle.Colors.cardBackgroundDark

                FlowWireframe(variant: cardIndex)
                    .opacity(0.22)
            }

            // Color stripe at top
            VStack {
                Rectangle()
                    .fill(card.color)
                    .frame(height: 3)
                Spacer()
            }

            // Top gradient for readability
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                Spacer()
            }

            // Bottom gradient for text readability
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )

            // Info overlay (matches real TaskSwipeCardView layout)
            VStack(alignment: .leading, spacing: 6) {
                Spacer()

                // Days-ago badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .frame(width: 5, height: 5)
                    Text(card.daysAgo == 1 ? "1 DAY AGO" : "\(card.daysAgo) DAYS AGO")
                        .font(.microLabel)
                        .foregroundStyle(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .tracking(1)
                }

                // Task name
                Text(card.task.uppercased())
                    .font(.title)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .lineLimit(2)

                // Project
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 11))
                    Text(card.project.uppercased())
                        .font(.caption)
                }
                .foregroundStyle(.white.opacity(0.7))

                // Client
                HStack(spacing: 6) {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 11))
                    Text(card.client.uppercased())
                        .font(.smallCaption)
                }
                .foregroundStyle(.white.opacity(0.5))
            }
            .padding(20)
            .padding(.bottom, 40)

            // Stamp overlays
            if isSwipingRight && swipeProgress > 0.1 {
                stampView(text: "COMPLETE", color: OPSStyle.Colors.successStatus, rotation: -12)
                    .opacity(swipeProgress)
            }
            if !isSwipingRight && swipeProgress > 0.1 {
                stampView(text: "SKIP", color: OPSStyle.Colors.inactiveStatus, rotation: 12)
                    .opacity(swipeProgress)
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.7, contentMode: .fit)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .offset(dragOffset)
        .rotationEffect(.degrees(dragOffset.width / 25))
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !committed else { return }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    guard !committed else { return }
                    if abs(value.translation.width) >= threshold {
                        commitSwipe()
                    } else {
                        // dampingFraction 0.8 = controlled settle, no bounce
                        withAnimation(.easeOut(duration: 0.2)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(card.task), \(card.project), \(card.client), \(card.daysAgo) days ago")
        .accessibilityHint("Swipe right to complete, swipe left to skip")
    }

    private func stampView(text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.headingBold)
            .foregroundStyle(color)
            .tracking(3)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(color, lineWidth: 2)
            )
            .rotationEffect(.degrees(rotation))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func commitSwipe() {
        committed = true
        let direction = isSwipingRight ? "right" : "left"
        let flyX: CGFloat = isSwipingRight ? 500 : -500

        if isSwipingRight {
            TutorialHaptics.commit()
        }
        // No haptic on left-swipe (skip) — haptics are earned by meaningful actions

        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = CGSize(width: flyX, height: dragOffset.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwiped(direction)
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Wireframe Illustrations
// MARK: ═══════════════════════════════════════════════════════════════════════

/// Four distinct wireframe line drawings for review cards.
/// Monochrome white lines. Blueprint aesthetic. Brighter than production (22% opacity applied by parent).
private struct FlowWireframe: View {
    let variant: Int

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let color = Color.white

            switch variant % 4 {
            case 0: drawDuplex(context: context, w: w, h: h, color: color)
            case 1: drawDeckRailing(context: context, w: w, h: h, color: color)
            case 2: drawApartmentUnit(context: context, w: w, h: h, color: color)
            case 3: drawHouseReno(context: context, w: w, h: h, color: color)
            default: break
            }
        }
    }

    // Variant 0: Duplex — two connected units with shared wall
    private func drawDuplex(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        // Left unit
        path.move(to: CGPoint(x: w * 0.1, y: ground))
        path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.5, y: ground))
        // Right unit
        path.move(to: CGPoint(x: w * 0.5, y: ground))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.9, y: ground))
        // Doors + Windows
        path.addRect(CGRect(x: w * 0.25, y: h * 0.6, width: w * 0.08, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.67, y: h * 0.6, width: w * 0.08, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.15, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.38, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.55, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.8, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

    // Variant 1: Deck with railing
    private func drawDeckRailing(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        let deckTop = h * 0.55
        let deckLeft = w * 0.15
        let deckRight = w * 0.85
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        // Deck platform
        path.move(to: CGPoint(x: deckLeft, y: deckTop))
        path.addLine(to: CGPoint(x: deckRight, y: deckTop))
        path.addLine(to: CGPoint(x: deckRight, y: deckTop + 4))
        path.addLine(to: CGPoint(x: deckLeft, y: deckTop + 4))
        path.closeSubpath()
        // Support posts
        for i in 0..<5 {
            let x = deckLeft + (deckRight - deckLeft) * CGFloat(i) / 4.0
            path.move(to: CGPoint(x: x, y: deckTop))
            path.addLine(to: CGPoint(x: x, y: ground))
        }
        // Railing posts
        let railTop = h * 0.35
        for i in 0...6 {
            let x = deckLeft + (deckRight - deckLeft) * CGFloat(i) / 6.0
            path.move(to: CGPoint(x: x, y: deckTop))
            path.addLine(to: CGPoint(x: x, y: railTop))
        }
        // Rails
        path.move(to: CGPoint(x: deckLeft, y: railTop))
        path.addLine(to: CGPoint(x: deckRight, y: railTop))
        let midRail = (railTop + deckTop) / 2
        path.move(to: CGPoint(x: deckLeft, y: midRail))
        path.addLine(to: CGPoint(x: deckRight, y: midRail))
        // Steps
        let stepW = w * 0.08
        for i in 0..<3 {
            let sy = deckTop + CGFloat(i) * (ground - deckTop) / 3
            path.move(to: CGPoint(x: deckRight, y: sy))
            path.addLine(to: CGPoint(x: deckRight + stepW, y: sy))
            path.addLine(to: CGPoint(x: deckRight + stepW, y: sy + (ground - deckTop) / 3))
        }
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

    // Variant 2: Apartment unit — interior with partition
    private func drawApartmentUnit(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let margin = w * 0.12
        let top = h * 0.15
        let bottom = h * 0.88
        let left = margin
        let right = w - margin
        path.addRect(CGRect(x: left, y: top, width: right - left, height: bottom - top))
        let partition = left + (right - left) * 0.6
        path.move(to: CGPoint(x: partition, y: top))
        path.addLine(to: CGPoint(x: partition, y: bottom))
        // Door opening
        let doorTop = h * 0.45
        path.move(to: CGPoint(x: partition - 1, y: doorTop))
        path.addLine(to: CGPoint(x: partition - 1, y: bottom))
        // Door swing arc
        var arc = Path()
        arc.addArc(center: CGPoint(x: partition, y: bottom),
                   radius: bottom - doorTop,
                   startAngle: .degrees(180),
                   endAngle: .degrees(270),
                   clockwise: false)
        context.stroke(arc, with: .color(color), lineWidth: 0.4)
        // Window on left wall
        let winY = h * 0.3
        let winH = h * 0.15
        let winMid = winY + winH / 2
        path.move(to: CGPoint(x: left - 3, y: winY))
        path.addLine(to: CGPoint(x: left + 3, y: winY))
        path.move(to: CGPoint(x: left - 3, y: winY + winH))
        path.addLine(to: CGPoint(x: left + 3, y: winY + winH))
        path.move(to: CGPoint(x: left - 3, y: winMid))
        path.addLine(to: CGPoint(x: left + 3, y: winMid))
        // Counter in right room
        let counterY = h * 0.65
        path.move(to: CGPoint(x: partition + w * 0.05, y: counterY))
        path.addLine(to: CGPoint(x: right - w * 0.05, y: counterY))
        path.addLine(to: CGPoint(x: right - w * 0.05, y: counterY + h * 0.04))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

    // Variant 3: House with scaffolding
    private func drawHouseReno(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        let left = w * 0.2
        let right = w * 0.75
        let wallTop = h * 0.32
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        // Walls
        path.move(to: CGPoint(x: left, y: ground))
        path.addLine(to: CGPoint(x: left, y: wallTop))
        path.addLine(to: CGPoint(x: right, y: wallTop))
        path.addLine(to: CGPoint(x: right, y: ground))
        // Roof
        path.move(to: CGPoint(x: left - w * 0.04, y: wallTop))
        path.addLine(to: CGPoint(x: (left + right) / 2, y: h * 0.15))
        path.addLine(to: CGPoint(x: right + w * 0.04, y: wallTop))
        // Door + Window
        path.addRect(CGRect(x: w * 0.4, y: h * 0.6, width: w * 0.1, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.55, y: h * 0.45, width: w * 0.1, height: w * 0.08))
        // Scaffolding
        let scafLeft = right + w * 0.03
        let scafRight = right + w * 0.18
        path.move(to: CGPoint(x: scafLeft, y: ground))
        path.addLine(to: CGPoint(x: scafLeft, y: h * 0.2))
        path.move(to: CGPoint(x: scafRight, y: ground))
        path.addLine(to: CGPoint(x: scafRight, y: h * 0.2))
        for level in stride(from: ground, through: h * 0.25, by: -(ground - h * 0.2) / 4) {
            path.move(to: CGPoint(x: scafLeft, y: level))
            path.addLine(to: CGPoint(x: scafRight, y: level))
        }
        // Cross bracing
        path.move(to: CGPoint(x: scafLeft, y: ground))
        path.addLine(to: CGPoint(x: scafRight, y: ground - (ground - h * 0.2) / 4))
        path.move(to: CGPoint(x: scafRight, y: ground))
        path.addLine(to: CGPoint(x: scafLeft, y: ground - (ground - h * 0.2) / 4))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }
}
