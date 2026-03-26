import SwiftUI
import UIKit

// MARK: - TutorialFlowViewV2
/// ONE continuous view for the OPS "Lead to Revenue" V2 tutorial.
///
/// Architecture:
/// - Phase-driven state machine (9 phases, no separate step files)
/// - matchedGeometryEffect connects estimate line items → task cards ("peel off")
/// - Single evolving card for lead → estimate (content morphs in place)
/// - Review swipe cards with visible completed stack (bottom-right)
/// - Project closeout: stack expands → project cards → invoices → paid
/// - Per-project financial bars (revenue/expense/profit)
/// - Closing: 13 steps type in, 11 strike through, survivors glow, tagline, CTA
/// - All haptics via TutorialHaptics (arrival/commit/milestone/strikethrough)
/// - Reduced motion: crossfade alternatives for all animations
///
/// Core principle: Every piece of information transforms into the next.
/// Nothing appears from nowhere. One continuous metamorphosis from lead to profit.
///
/// Brand: military tactical minimalist. Sharp ease-out entries (0.2s). Clean ease-in exits (0.15s).
/// Springs: dampingFraction >= 0.75 (no visible bounce). Celebration = restraint.
struct TutorialFlowViewV2: View {

    let onComplete: () -> Void

    @StateObject private var state = TutorialStateManagerV2()
    @Namespace private var ns
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // MARK: - Card Evolution (Phases 0-2)

    @State private var showCard = false
    @State private var cardOffset: CGFloat = -280
    @State private var isEstimateMode = false
    @State private var estimateShellOpacity: Double = 1

    // Phase 0 — Lead
    @State private var clientChars = 0
    @State private var projectChars = 0
    @State private var showLeadSource = false
    @State private var leadGlow: Double = 0
    @State private var leadInteractive = false
    @State private var typewriterTimer: Timer?

    // Phase 1 — Estimate
    @State private var visibleLineItems = 0
    @State private var showDivider = false
    @State private var showTotal = false
    @State private var showSendEstimate = false

    // Phase 2 — Approved
    @State private var showApproval = false
    @State private var peeledCount = 0
    @State private var showCrewOnTasks = false
    @State private var showContinue = false

    // Phase 3 — Crew Executes → Project Assembly
    @State private var taskStatuses = [0, 0, 0]
    @State private var projectAssembling = false
    @State private var borderDrawProgress: CGFloat = 0
    @State private var cardBgOpacity: Double = 0
    @State private var projectTitleChars = 0
    @State private var progressBarValue: CGFloat = 0
    @State private var projectTitleTimer: Timer?

    // Phase 3→4 — Calendar Gantt Transition
    @State private var projectChromeFading = false
    @State private var taskDetachBorders: [CGFloat] = [0, 0, 0]
    @State private var hideProjectCard = false
    @State private var showCalendar = false
    @State private var calendarVisibleTasks: Set<String> = []
    @State private var calendarCompletedTasks: Set<String> = []
    @State private var calendarFocusDay = -1
    @State private var calendarFadeCompleted = false
    @State private var showCalendarHeader = false
    @State private var calendarExtractPhase = 0

    // Phase 5 — Review with stacking
    @State private var showReviewStack = false
    @State private var reviewCurrentIndex = 0
    @State private var swipeResults: [Bool] = []
    @State private var showingCompletion: Int? = nil
    @State private var completionOpacity: Double = 0
    @State private var completionSlideX: CGFloat = 0          // Directional entry from swipe direction
    @State private var showReviewDone = false
    @State private var reviewDoneOpacity: Double = 0
    @State private var reviewDoneScale: CGFloat = 0.5
    @State private var reviewDoneCentered = false            // false = at stack position, true = centered
    @State private var stackGlowOpacity: Double = 0          // Success glow on stack during ALL CAUGHT UP
    @State private var completedCardIndices: [Int] = []
    @State private var leftSwipeAction: String? = nil         // "push" or "reschedule" — user's choice on left-swipe
    @State private var showSwipeOnboarding = false              // One-time swipe tutorial overlay
    @State private var swipeOnboardingPhase = 0                 // 0=idle, 1=swipe right demo, 2=hold right, 3=return, 4=swipe left demo, 5=hold left, 6=return, 7=done

    // Phase 6-7 — Closeout + Financials (one morphing card per project)
    @State private var closeoutCurrentProject = 0
    @State private var showCloseoutCard = false
    @State private var closeoutCardScale: CGFloat = 0.35     // Mini stack → full
    @State private var closeoutCardOffset: CGSize = .zero     // Stack position → center
    @State private var closeoutStep = 0                       // 0=project, 1=invoice, 2=sent, 3=paid, 5=tasksReturn+swipe
    @State private var showCloseoutTasks = false
    @State private var showInvoiceLines = false
    @State private var showSentIndicator = false
    @State private var showPaidBanner = false
    @State private var revenueBarProgress: CGFloat = 0
    @State private var expenseBarProgress: CGFloat = 0
    @State private var showProfitLine = false
    @State private var closeoutCardOpacity: Double = 1
    @State private var showCompletedStack = false             // Persists stack visibility beyond review
    @State private var showCloseoutContinue = false           // Tap to advance between projects
    @State private var closeoutWaitingForTap = false          // Blocks auto-advance until user taps
    @State private var closeoutProjectOrder: [Int] = []       // Snapshot of completed indices at closeout start
    @State private var stackCenter: CGPoint = .zero           // Captured position of completed stack in content area
    @State private var contentCenter: CGPoint = .zero         // Center of content area for offset calculation
    @State private var closeoutSwipeDrag: CGSize = .zero      // Drag offset for swipe-to-close gesture
    @State private var closeoutSwipeCommitted = false          // Prevents double-tap on swipe
    @State private var closeoutSwipeHapticFired = false        // Prevents haptic spam during drag (matches job board hasTriggeredHaptic)
    @State private var showSwipeHint = false                   // "SWIPE TO CLOSE" label
    @State private var closeoutNameChars = 0                   // Typewriter for project name on step 5
    @State private var closeoutNameTimer: Timer?               // Typewriter timer
    @State private var closeoutShowClient = false              // Client name fade-in after typewriter
    @State private var closeoutShowFinancials = false          // Financial bars visibility (separate from step gate)
    @State private var closeoutTasksReturned = 0               // Number of tasks faded back in during step 6
    // Stack mode — remaining projects as compact swipeable PAID cards after first full animation
    @State private var closeoutStackMode = false
    @State private var closeoutStackVisible: Int = 0
    @State private var closeoutStackClosed: Set<Int> = []
    @State private var closeoutStackCards: [Int] = []         // Card indices for the stack (set once, stable)
    @State private var closeoutStackHintShowing = false       // Swipe hint on first card + dim the rest

    // Phase 8 — Closing
    @State private var showClosing = false
    @State private var closingStepsVisible = 0
    @State private var closingStrikeCount = 0
    @State private var closingStrikeProgress: [CGFloat] = Array(repeating: 0, count: 13) // Per-step line draw 0→1
    @State private var closingCollapsed = false
    @State private var closingSurvivorsHighlighted = false
    @State private var closingTaglineProgress = 0
    @State private var showCTA = false
    @State private var showClosingLists = false                // YOU: / OPS: two-column reveal
    @State private var closingListsCollapsing = false          // Lists collapsing up into divider
    @State private var closingOpsListFaded = false             // OPS list faded out (first)
    @State private var closingYouListFaded = false             // YOU list faded out (second)
    @State private var closingTaglineChars: [Int] = [0, 0, 0]  // Typewriter char count per tagline line
    @State private var closingTaglineTimers: [Timer?] = [nil, nil, nil]

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
                    .id("\(state.currentPhase.rawValue)_\(showCalendarHeader)") // Forces view replacement on phase change AND calendar header toggle
                    .frame(height: 56)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .opacity(headerOpacity)
                    .transition(.opacity)
                    .animation(.easeOut(duration: 0.3), value: state.currentPhase)
                    .animation(.easeOut(duration: 0.3), value: showCalendarHeader)

                contentArea
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.top, 16) // Breathing room between header and content
            }

            // Left-swipe popup overlay — FULL BLEED, covers entire screen including header
            if let idx = showingCompletion, idx < swipeResults.count {
                Color.black.opacity(0.6 * completionOpacity)
                    .ignoresSafeArea()

                inlineSwipeResultCard(for: idx, wasRight: swipeResults[idx])
                    .padding(.horizontal, 24)
                    .offset(x: completionSlideX)
                    .opacity(completionOpacity)
            }

            // Swipe onboarding overlay — one-time demo on first review card
            if showSwipeOnboarding {
                let ghostOffset: CGFloat = {
                    switch swipeOnboardingPhase {
                    case 1, 2: return 80      // right
                    case 4, 5: return -80     // left
                    default: return 0         // center
                    }
                }()

                Color.black.opacity(0.7)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Spacer()

                    // Ghost card — matches actual review card proportions and content
                    ZStack {
                        // Card background
                        OPSStyle.Colors.cardBackgroundDark

                        // Color stripe at top
                        VStack {
                            Rectangle()
                                .fill(OPSStyle.Colors.inactiveStatus)
                                .frame(height: 3)
                            Spacer()
                        }

                        // Top gradient
                        VStack {
                            LinearGradient(
                                gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                            .frame(height: 100)
                            Spacer()
                        }

                        // Bottom gradient
                        LinearGradient(
                            gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                            startPoint: .center,
                            endPoint: .bottom
                        )

                        // Placeholder content (dimmed)
                        VStack(alignment: .leading, spacing: 6) {
                            Spacer()

                            HStack(spacing: 5) {
                                Circle()
                                    .fill(OPSStyle.Colors.warningStatus)
                                    .frame(width: 5, height: 5)
                                Text("3 DAYS AGO")
                                    .font(.microLabel)
                                    .foregroundStyle(OPSStyle.Colors.warningStatus.opacity(0.5))
                                    .tracking(1)
                            }

                            Text("GUTTER CLEANING")
                                .font(.title)
                                .foregroundStyle(Color.white.opacity(0.3))
                                .lineLimit(1)

                            HStack(spacing: 6) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 11))
                                Text("PARKSIDE DUPLEX")
                                    .font(.caption)
                            }
                            .foregroundStyle(Color.white.opacity(0.2))

                            HStack(spacing: 6) {
                                Image(systemName: "person.circle.fill")
                                    .font(.system(size: 11))
                                Text("METRO PROPERTY MGMT")
                                    .font(.smallCaption)
                            }
                            .foregroundStyle(Color.white.opacity(0.15))
                        }
                        .padding(24)
                        .padding(.bottom, 40)
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // COMPLETE stamp — matches real FlowReviewCardV2 stampView
                        if swipeOnboardingPhase == 1 || swipeOnboardingPhase == 2 {
                            Text("COMPLETE")
                                .font(.headingBold)
                                .foregroundStyle(OPSStyle.Colors.successStatus)
                                .tracking(3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.successStatus, lineWidth: 2)
                                )
                                .rotationEffect(.degrees(-12))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity)
                        }

                        // SKIP stamp — matches real FlowReviewCardV2 stampView
                        if swipeOnboardingPhase == 4 || swipeOnboardingPhase == 5 {
                            Text("SKIP")
                                .font(.headingBold)
                                .foregroundStyle(OPSStyle.Colors.inactiveStatus)
                                .tracking(3)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.inactiveStatus, lineWidth: 2)
                                )
                                .rotationEffect(.degrees(12))
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .aspectRatio(0.7, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .offset(x: ghostOffset)
                    .rotationEffect(.degrees(ghostOffset / 25))
                    .padding(.horizontal, 24)

                    // Instruction text
                    Text(swipeOnboardingPhase >= 4
                        ? "SWIPE LEFT TO SKIP"
                        : "SWIPE RIGHT TO COMPLETE")
                        .font(.caption)
                        .foregroundStyle(Color.white.opacity(0.7))
                        .tracking(1.5)

                    Spacer()
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(true)
        .onAppear { beginTutorial() }
        .onDisappear {
            typewriterTimer?.invalidate()
            projectTitleTimer?.invalidate()
            closeoutNameTimer?.invalidate()
            closingTaglineTimers.forEach { $0?.invalidate() }
        }
        .onChange(of: state.isActive) { _, active in
            if !active { onComplete() }
        }
    }

    // MARK: - Chrome (Progress Dots + Skip)

    private var chrome: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(0..<TutorialPhaseV2.totalSteps, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i))
                        .frame(width: 5, height: 5)
                }
            }
            .animation(OPSStyle.Animation.fast, value: state.currentPhase)

            Spacer()

            if state.currentPhase != .closing && !showCTA {
                Button {
                    state.skip()
                } label: {
                    Text("SKIP")
                        .font(.caption)
                        .tracking(1)
                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, 24)
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
                .foregroundStyle(stepHeadlineColor)
                .tracking(stepHeadlineTracking)

            Text(stepSubline)
                .font(.smallCaption)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
        }
        .multilineTextAlignment(.center)
        .animation(.easeOut(duration: 0.3), value: showCalendarHeader)
    }

    private var stepHeadline: String {
        switch state.currentPhase {
        case .leadArrives:      return "A NEW LEAD JUST LANDED"
        case .sendEstimate:     return "BUILD THE ESTIMATE"
        case .estimateApproved: return "CLIENT SAID YES"
        case .crewExecutes:     return "CREW IS WORKING"
        case .calendarWeek:     return showCalendarHeader ? "4 TASKS NOT COMPLETE" : "END OF THE WEEK"
        case .weeklyReview:     return "WEEKLY REVIEW"
        case .projectCloseout:  return "CLOSE IT OUT"
        case .financials:       return "WHAT YOU KEEP"
        case .closing:          return ""
        }
    }

    private var stepHeadlineColor: Color {
        if state.currentPhase == .calendarWeek && showCalendarHeader {
            return OPSStyle.Colors.warningStatus
        }
        return OPSStyle.Colors.primaryText
    }

    private var stepHeadlineTracking: CGFloat {
        if state.currentPhase == .calendarWeek && showCalendarHeader {
            return 2
        }
        return 1
    }

    private var stepSubline: String {
        switch state.currentPhase {
        case .leadArrives:      return "Caught automatically from your inbox."
        case .sendEstimate:     return "Line items. Crew costs. Materials. One tap to send."
        case .estimateApproved: return "Labor items become tasks. Crew gets assigned."
        case .crewExecutes:     return "They update status from the field. You see it live."
        case .calendarWeek:     return showCalendarHeader ? "MARKED FOR REVIEW" : "Your whole week. Every task. Every crew member."
        case .weeklyReview:     return "Right to complete. Left to skip."
        case .projectCloseout:  return "Invoice. Payment. One tap."
        case .financials:       return "Revenue minus costs. The real number."
        case .closing:          return ""
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            // Capture content area center for offset calculations
            GeometryReader { geo in
                Color.clear.onAppear {
                    contentCenter = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                }
            }
            .frame(width: 0, height: 0) // Zero-size — invisible measurement
            // ── PHASES 0-2: Evolving card + approval + peeling task cards ──

            if showCard {
                VStack(spacing: 12) {
                    evolvingCard
                        .padding(.horizontal, 24)

                    // Tap hint — appears when lead card is interactive, hides on tap
                    if leadInteractive && !isEstimateMode {
                        TapToBeginHint()
                            .transition(.opacity)
                    }
                }
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

            if peeledCount > 0 && state.currentPhase == .estimateApproved {
                VStack(spacing: 8) {
                    ForEach(0..<peeledCount, id: \.self) { i in
                        taskCardRow(TutorialData.taskCards[i], index: i, showCrew: showCrewOnTasks)
                            .matchedGeometryEffect(id: "laborTask_\(i)", in: ns, isSource: true)
                    }
                }
                .padding(.horizontal, 24)
            }

            // ── PHASE 3: Task assembly ──

            if state.currentPhase == .crewExecutes && !hideProjectCard {
                assemblingProjectView
                    .padding(.horizontal, 24)
                    .clipped()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            // ── PHASE 4: Calendar Gantt view ──

            if showCalendar {
                VStack(spacing: 12) {
                    FlowCalendarWeekV2(
                        visibleTasks: calendarVisibleTasks,
                        completedTasks: calendarCompletedTasks,
                        focusDay: calendarFocusDay,
                        fadeCompleted: calendarFadeCompleted,
                        extractPhase: calendarExtractPhase,
                        calendarNS: ns
                    )
                }
                .padding(.horizontal, 12)
                .frame(maxHeight: .infinity, alignment: .center)
            }

            // ── PHASE 5: Review with stacking ──

            if showReviewStack {
                reviewStackView
                    .padding(.horizontal, 16)
                    .transition(.opacity)
            }

            // NOTE: Left-swipe popup overlay moved to top-level ZStack for full-bleed dark background

            // Completed stack (bottom-right corner) — persists through review + closeout, hides when empty
            if completedCardIndices.count > 0 && showCompletedStack {
                completedStackView
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .padding(.trailing, 16)
                    .padding(.bottom, 72)
                    .background(
                        // Capture stack center in content area coordinate space
                        GeometryReader { geo in
                            Color.clear
                                .onChange(of: completedCardIndices.count) { _, _ in
                                    let frame = geo.frame(in: .named("contentArea"))
                                    stackCenter = CGPoint(
                                        x: frame.maxX - 28, // Approximate center of top card
                                        y: frame.maxY - 36
                                    )
                                }
                                .onAppear {
                                    let frame = geo.frame(in: .named("contentArea"))
                                    stackCenter = CGPoint(
                                        x: frame.maxX - 28,
                                        y: frame.maxY - 36
                                    )
                                }
                        }
                    )
            }

            if showReviewDone && !showCloseoutCard {
                allCaughtUpView
                    .transition(.opacity)
            }

            // ── PHASES 6-7: Closeout — INLINE (no function calls, SwiftUI tracks state directly) ──

            if showCloseoutCard, closeoutCurrentProject < closeoutProjectOrder.count {
                let closedColor = OPSStyle.Colors.statusColor(for: .closed)

                VStack(spacing: 12) {
                // Swipe hint — above the card, left-to-right shimmer
                if showSwipeHint && closeoutStep >= 5 {
                    CloseoutSwipeHint()
                        .opacity(closeoutSwipeCommitted ? 0 : 1)
                        .animation(.easeOut(duration: 0.2), value: closeoutSwipeCommitted)
                }

                // ZStack: card content is the sizing child. Revealed/flash cards use
                // .overlay/.background on the ZStack itself to guarantee frame match.
                ZStack {
                    // FRONT: Card content — the only child that determines frame size
                    closeoutCardContent
                        .offset(x: closeoutStep >= 5 ? closeoutSwipeDrag.width : 0)
                        .opacity(closeoutSwipeCommitted ? 0 : 1)
                }
                // BEHIND: Revealed CLOSED — .background matches ZStack frame exactly
                .background(
                    Group {
                        if closeoutStep >= 5 && (closeoutSwipeDrag.width > 0 || closeoutSwipeCommitted) {
                            HStack {
                                Text("CLOSED")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(closedColor)
                                    .padding(.leading, 20)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(closedColor.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(closedColor, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .opacity(closeoutSwipeCommitted ? 1 : min(closeoutSwipeDrag.width / 140, 1.0))
                        }
                    }
                )
                // TOP: Confirmation flash — .overlay matches ZStack frame exactly
                .overlay(
                    Group {
                        if closeoutSwipeCommitted {
                            HStack {
                                Text("CLOSED")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(closedColor)
                                    .padding(.leading, 20)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .fill(closedColor.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                    .stroke(closedColor, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                    }
                )
                .gesture(
                    closeoutStep >= 5
                    ? DragGesture()
                        .onChanged { value in
                            guard !closeoutSwipeCommitted else { return }
                            closeoutSwipeDrag = CGSize(
                                width: max(0, value.translation.width),
                                height: 0
                            )
                            if closeoutSwipeDrag.width >= 140 && !closeoutSwipeHapticFired {
                                let impact = UIImpactFeedbackGenerator(style: .medium)
                                impact.impactOccurred()
                                closeoutSwipeHapticFired = true
                            }
                        }
                        .onEnded { value in
                            guard !closeoutSwipeCommitted else { return }
                            if value.translation.width >= 140 {
                                commitCloseoutSwipe()
                            } else {
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    closeoutSwipeDrag = .zero
                                }
                                closeoutSwipeHapticFired = false
                            }
                        }
                    : nil
                )
                .padding(.horizontal, 24)
                } // end VStack
                .scaleEffect(closeoutCardScale, anchor: .bottomTrailing)
                .offset(closeoutCardOffset)
                .opacity(closeoutCardOpacity)
            }

            // ── PHASES 6-7: Stack mode — remaining PAID projects as swipeable vertical stack ──
            if closeoutStackMode {
                VStack(spacing: 8) {
                    ForEach(closeoutStackCards, id: \.self) { cardIdx in
                        if !closeoutStackClosed.contains(cardIdx) {
                            let isFirst = cardIdx == closeoutStackCards.first(where: { !closeoutStackClosed.contains($0) })
                            let project = TutorialDataV2.closeoutProject(for: cardIdx)

                            VStack(spacing: 6) {
                                // Swipe hint above the first card
                                if closeoutStackHintShowing && isFirst == true {
                                    CloseoutSwipeHint()
                                        .transition(.opacity)
                                }

                                CloseoutStackCard(
                                    projectName: project.projectName,
                                    clientName: project.clientName,
                                    color: project.color,
                                    onClosed: { handleStackCardClosed(cardIdx) }
                                )
                            }
                            .opacity(closeoutStackHintShowing && isFirst != true ? 0.3 : 1)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .offset(y: 16)),
                                removal: .scale(scale: 0.95, anchor: .top).combined(with: .opacity)
                            ))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                .animation(.easeOut(duration: 0.3), value: closeoutStackVisible)
                .animation(.easeInOut(duration: 0.35), value: closeoutStackClosed)
                .animation(.easeOut(duration: 0.25), value: closeoutStackHintShowing)
                .transition(.opacity)
            }

            // ── PHASE 8: Closing Sequence ──

            if showClosing {
                closingSequenceView
                    .transition(.opacity)
            }

            // ── CONTINUE button (phases 2-3) ──

            if showContinue {
                continueButton { handleContinue() }
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                    .transition(.opacity)
            }
        }
        .coordinateSpace(name: "contentArea")
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 0-1: The Evolving Card (Lead → Estimate)
    // MARK: ─────────────────────────────────────────────────────────────────

    private var evolvingCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !isEstimateMode {
                leadContent
            } else {
                estimateContent
            }
        }
        .padding(24)
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

        VStack(spacing: 0) {
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

            if visibleLineItems > TutorialData.laborItems.count {
                lineItemRow(TutorialData.lineItems.last!)
                    .opacity(peeledCount > 0 ? 0 : 1)
                    .transition(.opacity.combined(with: .move(edge: .leading)))
            }
        }

        if showDivider && peeledCount == 0 {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1)
                .padding(.vertical, 12)
        }

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
    // MARK: PHASE 2: Approval Banner + Task Cards
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
        .padding(.vertical, 8)
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
    // MARK: PHASE 3: Task Execution → Project Assembly
    // MARK: ─────────────────────────────────────────────────────────────────

    private var assemblingProjectView: some View {
        VStack(alignment: .leading, spacing: 0) {
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
                .opacity(projectChromeFading ? 0 : 1)
            }

            VStack(spacing: projectAssembling ? (projectChromeFading ? 10 : 2) : 8) {
                ForEach(0..<TutorialData.taskCards.count, id: \.self) { i in
                    morphingTaskRow(TutorialData.taskCards[i], index: i)
                        .matchedGeometryEffect(id: "laborTask_\(i)", in: ns, isSource: false)
                }
            }

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
                .opacity(projectChromeFading ? 0 : 1)
            }
        }
        .padding(projectAssembling ? 24 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
                .opacity(projectChromeFading ? 0 : cardBgOpacity)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .trim(from: 0, to: borderDrawProgress)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                .opacity(projectChromeFading ? 0 : 1)
        )
    }

    private func morphingTaskRow(_ task: TutorialData.TaskCard, index: Int) -> some View {
        let s = taskStatuses[index]
        let statusLabel = s == 0 ? "BOOKED" : s == 1 ? "IN PROGRESS" : "COMPLETE"
        let statusColor: Color = s == 0 ? OPSStyle.Colors.inactiveStatus
            : s == 1 ? OPSStyle.Colors.warningStatus
            : OPSStyle.Colors.successStatus

        return HStack(spacing: projectAssembling ? 8 : 12) {
            if !projectAssembling {
                RoundedRectangle(cornerRadius: 1)
                    .fill(task.color)
                    .frame(width: 3)
            }

            if projectAssembling {
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
        .padding(.horizontal, projectAssembling ? (projectChromeFading ? 8 : 0) : 16)
        .padding(.vertical, projectAssembling ? (projectChromeFading ? 4 : 2) : 8)
        .background(
            Group {
                if !projectAssembling {
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                } else if projectChromeFading {
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
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                        .trim(from: 0, to: taskDetachBorders[index])
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                }
            }
        )
        .opacity(!projectAssembling && s == 2 ? 0.5 : 1.0)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 5: Review with Completed Stack
    // MARK: ─────────────────────────────────────────────────────────────────

    private var reviewStackView: some View {
        let cards = TutorialData.reviewCards
        let remaining = Array(cards.dropFirst(reviewCurrentIndex))
        let hasCards = reviewCurrentIndex < cards.count
        let visible: [(idx: Int, card: TutorialData.ReviewCard)] = Array(
            remaining.prefix(3).enumerated().map { (idx: $0.offset, card: $0.element) }
        ).reversed()

        return VStack(spacing: 0) {
            if hasCards {
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
                    let actualCardIndex = reviewCurrentIndex + item.idx
                    FlowReviewCardV2(
                        card: item.card,
                        cardIndex: actualCardIndex,
                        onSwiped: { direction in handleReviewSwipe(direction: direction) }
                    )
                    .scaleEffect(1.0 - (CGFloat(item.idx) * 0.03), anchor: .top)
                    .offset(y: CGFloat(item.idx) * 8)
                    // matchedGeometryEffect — destination for calendar→review morph.
                    // isSource: false means this view takes the source's frame during transition,
                    // then animates to its own natural position.
                    .matchedGeometryEffect(
                        id: "calToReview_\(actualCardIndex)",
                        in: ns,
                        isSource: false
                    )
                    .allowsHitTesting(item.idx == 0 && showingCompletion == nil)
                    .zIndex(Double(3 - item.idx))
                }
            }

            // Swipe hints with animated arrows — only visible while cards remain
            if hasCards {
                Spacer().frame(height: 20)

                HStack(spacing: 0) {
                    // Left hint — animated arrow pulses left
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 11, weight: .medium))
                            .symbolEffect(.pulse, options: .repeating.speed(0.5))
                        Text("SKIP")
                            .font(.smallCaption)
                            .tracking(1.2)
                    }
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)

                    Spacer()

                    Text("SWIPE")
                        .font(.microLabel)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                        .tracking(2)

                    Spacer()

                    // Right hint — animated arrow pulses right
                    HStack(spacing: 6) {
                        Text("COMPLETE")
                            .font(.smallCaption)
                            .tracking(1.2)
                        Image(systemName: "arrow.right")
                            .font(.system(size: 11, weight: .medium))
                            .symbolEffect(.pulse, options: .repeating.speed(0.5))
                    }
                    .foregroundStyle(OPSStyle.Colors.successStatus.opacity(0.7))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
        }
    }

    /// Completed stack — small cards stacking bottom-right, each offset right + down
    private var completedStackView: some View {
        ZStack(alignment: .bottomTrailing) {
            ForEach(Array(completedCardIndices.enumerated()), id: \.element) { stackIdx, cardIdx in
                let card = TutorialData.reviewCards[cardIdx]
                RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                            .stroke(card.color.opacity(0.3), lineWidth: 0.5)
                    )
                    .overlay(
                        VStack(alignment: .leading, spacing: 2) {
                            Rectangle()
                                .fill(card.color)
                                .frame(height: 2)
                            Spacer()
                            Text(card.project.uppercased())
                                .font(.custom("Mohave-Medium", size: 7))
                                .foregroundStyle(OPSStyle.Colors.secondaryText)
                                .tracking(0.3)
                                .lineLimit(1)
                                .padding(.horizontal, 4)
                                .padding(.bottom, 3)
                        }
                    )
                    .frame(width: 56, height: 72)
                    // Each card offsets down and slightly right from the previous
                    .offset(
                        x: CGFloat(stackIdx) * 4,
                        y: CGFloat(stackIdx) * -8
                    )
                    .scaleEffect(1.0 - CGFloat(stackIdx) * 0.02, anchor: .bottomTrailing)
                    .zIndex(Double(stackIdx))
            }
        }
        // Success glow during ALL CAUGHT UP moment
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.successStatus, lineWidth: 1.5)
                .opacity(stackGlowOpacity)
                .frame(width: 60, height: 76)
        )
        .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
    }

    /// Left-swipe result card — shows project as incomplete with reschedule options.
    /// Only shown for left swipes. Right swipes have no popup.
    private func inlineSwipeResultCard(for cardIndex: Int, wasRight: Bool) -> some View {
        let card = TutorialData.reviewCards[cardIndex]

        return VStack(alignment: .leading, spacing: 0) {
            // Header — project incomplete
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(OPSStyle.Colors.warningStatus)

                VStack(alignment: .leading, spacing: 2) {
                    Text("PROJECT INCOMPLETE")
                        .font(.status)
                        .foregroundStyle(OPSStyle.Colors.warningStatus)
                        .tracking(1.5)
                    Text("\(card.project.uppercased()) — \(card.client)")
                        .font(.smallCaption)
                        .foregroundStyle(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.bottom, 12)

            // Skipped task
            HStack(spacing: 8) {
                Circle()
                    .stroke(OPSStyle.Colors.warningStatus, lineWidth: 1)
                    .frame(width: 12, height: 12)
                    .frame(width: 14)

                Text(card.task.uppercased())
                    .font(.bodyBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.5)

                Spacer()

                Text("SKIPPED")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.warningStatus)
                    .tracking(1)
            }
            .padding(.vertical, 4)

            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 0.5)
                .padding(.vertical, 12)

            if leftSwipeAction == nil {
                // Action buttons — user picks how to reschedule
                Text("RESCHEDULE THIS TASK")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .tracking(1.5)
                    .padding(.bottom, 12)

                VStack(spacing: 8) {
                    Button { handleLeftSwipeAction("push") } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.right.circle")
                                .font(.system(size: 14))
                            Text("PUSH FINISH DATE")
                                .font(.button)
                                .tracking(1)
                            Spacer()
                        }
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 48)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                    }

                    Button { handleLeftSwipeAction("reschedule") } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.system(size: 14))
                            Text("RESCHEDULE")
                                .font(.button)
                                .tracking(1)
                            Spacer()
                        }
                        .foregroundStyle(OPSStyle.Colors.primaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 48)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .fill(Color.white.opacity(0.05))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                    }
                }
            } else {
                // Response after user taps an action
                HStack(spacing: 10) {
                    Image(systemName: leftSwipeAction == "push" ? "checkmark.circle.fill" : "calendar.badge.checkmark")
                        .font(.system(size: 16))
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(leftSwipeAction == "push" ? "FINISH DATE EXTENDED" : "AUTO-SCHEDULED")
                            .font(.status)
                            .foregroundStyle(OPSStyle.Colors.primaryAccent)
                            .tracking(1.5)
                        Text(leftSwipeAction == "push"
                            ? "Task ends in 1 day."
                            : "Scheduled at assigned team's next availability.")
                            .font(.smallCaption)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                    }
                }
                .transition(.opacity)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.warningStatus.opacity(0.2), lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    /// ALL CAUGHT UP — centered behind the last swipe card.
    /// Revealed when the final card flies away, already in position.
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

            Text("ALL CAUGHT UP")
                .font(.heading)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(2)
        }
        .scaleEffect(reviewDoneScale)
        .opacity(reviewDoneOpacity)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASES 6-7: Closeout Card Content
    // MARK: ─────────────────────────────────────────────────────────────────

    /// Card content body — @ViewBuilder computed property (NOT a function).
    /// Computed properties preserve SwiftUI state tracking. Functions break it.
    @ViewBuilder
    private var closeoutCardContent: some View {
        if closeoutCurrentProject < closeoutProjectOrder.count {
            let cardIdx = closeoutProjectOrder[closeoutCurrentProject]
            let project = TutorialDataV2.closeoutProject(for: cardIdx)
            let lineItems = TutorialDataV2.invoiceLineItems(for: cardIdx)

            let borderColor: Color = {
                if closeoutStep >= 3 { return OPSStyle.Colors.successStatus.opacity(0.3) }
                if closeoutStep >= 1 { return OPSStyle.Colors.primaryAccent.opacity(0.2) }
                return project.color.opacity(0.2)
            }()

            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(project.color)
                        .frame(width: 3, height: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        if closeoutStep >= 1 && closeoutStep <= 4 {
                            HStack(spacing: 6) {
                                Text("INVOICE")
                                    .font(.status)
                                    .foregroundStyle(OPSStyle.Colors.primaryAccent)
                                    .tracking(1.5)
                                Text(project.invoiceNumber)
                                    .font(.microLabel)
                                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                                    .tracking(1)
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        Text(project.projectName.uppercased())
                            .font(.headingLarge)
                            .foregroundStyle(OPSStyle.Colors.primaryText)
                            .tracking(0.8)

                        Text(project.clientName)
                            .font(.caption)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                    }

                    Spacer()

                    if showPaidBanner {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 14))
                            Text("PAID")
                                .font(.status)
                                .tracking(1.5)
                        }
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if showSentIndicator && !showPaidBanner {
                        HStack(spacing: 6) {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 12))
                            Text("SENT")
                                .font(.microLabel)
                                .tracking(1)
                        }
                        .foregroundStyle(OPSStyle.Colors.primaryAccent)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }

                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 0.5)
                    .padding(.vertical, 12)

                if closeoutStep == 0 && showCloseoutTasks {
                    ForEach(Array(project.tasks.enumerated()), id: \.offset) { _, task in
                        let isSwipedTask = task.name == project.swipedTaskName
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(OPSStyle.Colors.successStatus)
                                .frame(width: 14)
                            Text(task.name.uppercased())
                                .font(.smallCaption)
                                .foregroundStyle(OPSStyle.Colors.secondaryText)
                                .tracking(0.5)
                            Spacer()
                            if isSwipedTask {
                                Text("JUST NOW")
                                    .font(.microLabel)
                                    .foregroundStyle(OPSStyle.Colors.primaryAccent)
                                    .tracking(1)
                            }
                        }
                        .padding(.vertical, 3)
                    }
                    .transition(.opacity)
                }

                if closeoutStep >= 1 && closeoutStep <= 4 && showInvoiceLines {
                    ForEach(Array(lineItems.enumerated()), id: \.offset) { _, item in
                        HStack {
                            Text(item.name.uppercased())
                                .font(.smallCaption)
                                .foregroundStyle(OPSStyle.Colors.secondaryText)
                                .tracking(0.3)
                            Spacer()
                            Text(TutorialData.formatCurrency(item.amount))
                                .font(.smallCaption)
                                .foregroundStyle(OPSStyle.Colors.primaryText)
                        }
                        .padding(.vertical, 3)
                    }

                    Rectangle()
                        .fill(OPSStyle.Colors.cardBorder)
                        .frame(height: 1)
                        .padding(.vertical, 8)

                    HStack {
                        Text("TOTAL")
                            .font(.status)
                            .foregroundStyle(OPSStyle.Colors.secondaryText)
                            .tracking(1.5)
                        Spacer()
                        Text(TutorialData.formatCurrency(project.invoiceTotal))
                            .font(.headingLarge)
                            .foregroundStyle(OPSStyle.Colors.primaryText)
                    }
                }

                if closeoutStep >= 5 {
                    ForEach(0..<min(closeoutTasksReturned, project.tasks.count), id: \.self) { i in
                        let task = project.tasks[i]
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(OPSStyle.Colors.successStatus)
                                .frame(width: 14)
                            Text(task.name.uppercased())
                                .font(.smallCaption)
                                .foregroundStyle(OPSStyle.Colors.secondaryText)
                                .tracking(0.5)
                            Spacer()
                        }
                        .padding(.vertical, 3)
                        .transition(.opacity)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .fill(OPSStyle.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(borderColor, lineWidth: OPSStyle.Layout.Border.standard)
            )
            .animation(.easeOut(duration: 0.3), value: closeoutStep)
            .animation(.easeOut(duration: 0.25), value: showCloseoutTasks)
            .animation(.easeOut(duration: 0.25), value: showInvoiceLines)
            .animation(.easeOut(duration: 0.25), value: showPaidBanner)
            .animation(.easeOut(duration: 0.25), value: showSentIndicator)
        }
    }

    // MARK: ─────────────────────────────────────────────────────────────────
    // MARK: PHASE 8: Closing Sequence
    // MARK: ─────────────────────────────────────────────────────────────────

    private var closingSequenceView: some View {
        let steps = TutorialData.closingSteps
        let opsIndices = steps.enumerated().filter { $0.element.opsHandles }.map { $0.offset }
        let opsSteps = steps.filter(\.opsHandles)
        let userSteps = steps.filter { !$0.opsHandles }

        return VStack(spacing: 0) {
            Spacer()

            // ── Phase A+B: 13 steps with strikethrough, then morph to two columns ──
            if !showClosingLists {
                VStack(spacing: 5) {
                    ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                        let isVisible = idx < closingStepsVisible
                        let isStruck = step.opsHandles
                            && (opsIndices.firstIndex(of: idx).map { $0 < closingStrikeCount } ?? false)
                        let strikeDrawProgress = closingStrikeProgress[idx]

                        Text(step.text)
                            .font(step.opsHandles ? .heading : .headingBold)
                            .foregroundStyle(
                                isStruck ? OPSStyle.Colors.tertiaryText.opacity(0.4) :
                                !step.opsHandles ? OPSStyle.Colors.primaryText :
                                OPSStyle.Colors.secondaryText
                            )
                            .tracking(2.5)
                            .overlay(alignment: .leading) {
                                if step.opsHandles && strikeDrawProgress > 0 {
                                    Rectangle()
                                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.5))
                                        .frame(height: 1.5)
                                        .scaleEffect(x: strikeDrawProgress, y: 1, anchor: .leading)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .opacity(isVisible ? 1 : 0)
                            .offset(y: isVisible ? 0 : 8)
                    }
                }
                .padding(.horizontal, 32)
                .transition(.opacity)
            }

            // ── Phase C: Two-column morph — OPS left, YOU right ──
            // Collapse: lists shrink to 0 height, then fade out one at a time
            if showClosingLists && closingTaglineProgress == 0 {
                HStack(alignment: .top, spacing: 12) {
                    // OPS column — fades out first
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(OPSStyle.Colors.primaryAccent)
                                .frame(width: 2, height: 12)
                            Text("OPS")
                                .font(.status)
                                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                                .tracking(2)
                        }
                        .padding(.bottom, 10)

                        Rectangle()
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.12))
                            .frame(height: 0.5)

                        if !closingListsCollapsing {
                            VStack(alignment: .leading, spacing: 3) {
                                ForEach(opsSteps, id: \.id) { step in
                                    Text(step.text)
                                        .font(.microLabel)
                                        .foregroundStyle(OPSStyle.Colors.tertiaryText)
                                        .tracking(1)
                                        .strikethrough(true, color: OPSStyle.Colors.primaryAccent.opacity(0.35))
                                }
                            }
                            .padding(.top, 8)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(OPSStyle.Colors.primaryAccent.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.08), lineWidth: 0.5)
                    )
                    .opacity(closingOpsListFaded ? 0 : 1)
                    .scaleEffect(closingOpsListFaded ? 0.95 : 1, anchor: .center)

                    // YOU column — fades out second
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(OPSStyle.Colors.primaryText)
                                .frame(width: 2, height: 12)
                            Text("YOU")
                                .font(.status)
                                .foregroundStyle(OPSStyle.Colors.primaryText)
                                .tracking(2)
                        }
                        .padding(.bottom, 10)

                        Rectangle()
                            .fill(OPSStyle.Colors.primaryText.opacity(0.12))
                            .frame(height: 0.5)

                        if !closingListsCollapsing {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(userSteps, id: \.id) { step in
                                    Text(step.text)
                                        .font(.bodyBold)
                                        .foregroundStyle(OPSStyle.Colors.primaryText)
                                        .tracking(1)
                                }
                            }
                            .padding(.top, 8)
                            .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .fill(OPSStyle.Colors.primaryText.opacity(0.02))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.primaryText.opacity(0.06), lineWidth: 0.5)
                    )
                    .opacity(closingYouListFaded ? 0 : 1)
                    .scaleEffect(closingYouListFaded ? 0.95 : 1, anchor: .center)
                }
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            // ── Phase D+E: Tagline — typewriter, one line at a time ──
            if closingTaglineProgress > 0 {
                let lines = ["OPS HANDLES 85%.", "YOU HANDLE THE JOB SITE.", "LEAVE THE PAPERWORK TO US."]
                let fonts: [Font] = [.smallCaption, .headingLarge, .headingLarge]
                let colors: [Color] = [OPSStyle.Colors.tertiaryText, OPSStyle.Colors.primaryText, OPSStyle.Colors.primaryAccent]

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(0..<3, id: \.self) { i in
                        if closingTaglineProgress > i {
                            let fullText = lines[i]
                            let charCount = closingTaglineChars[i]
                            let visibleText = charCount >= fullText.count
                                ? fullText
                                : String(fullText.prefix(charCount))

                            Text(visibleText)
                                .font(fonts[i])
                                .foregroundStyle(colors[i])
                                .tracking(2)
                        }
                    }
                }
                .padding(.top, 32)
                .padding(.horizontal, 24)
                .transition(.opacity)
            }

            Spacer()

            // ── Phase F: CTA ──
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
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                .transition(.opacity)
            }
        }
    }

    // MARK: - Shared Components

    /// CONTINUE button — ultra-thin material fill, accent border, 56pt height, full width.
    /// Frosted glass over content behind it. Used for all intermediate actions.
    private func continueButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("CONTINUE")
                .font(.button)
                .tracking(1.5)
                .foregroundStyle(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .fill(.ultraThinMaterial)
                        .environment(\.colorScheme, .dark)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                )
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

    private func transitionHeader() {
        // Content changes automatically via .id(state.currentPhase) cross-fade on contextHeader.
        // No manual opacity animation — that caused fade-out-then-fade-in-then-fade-in triple blink.
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

        transitionHeader()

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
        transitionHeader()

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
        case .crewExecutes:     transitionToCalendar()
        default: break
        }
    }

    // MARK: → Crew Execution

    private func transitionToCrewExecution() {
        // Advance phase first — this makes assemblingProjectView appear (crewExecutes gate).
        // The phase 2 task cards (gated by currentPhase != .crewExecutes) disappear in the
        // same transaction. matchedGeometryEffect morphs them into the assembling task rows.
        state.advancePhase() // → crewExecutes

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            showApproval = false
            showCrewOnTasks = false
            // peeledCount stays > 0 — the phase gate handles hiding phase 2 cards.
            // matchedGeometryEffect morphs them into the assemblingProjectView rows.
        }

        transitionHeader()

        guard !reduceMotion else {
            taskStatuses = [2, 2, 1]
            projectAssembling = true
            borderDrawProgress = 1
            cardBgOpacity = 1
            projectTitleChars = TutorialData.projectTitle.count
            progressBarValue = 0.66
            showContinue = true
            return
        }

        // 2 of 3 tasks complete. Railing Touch-Up stays IN PROGRESS.
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

        let task2Base = 0.3 + 2 * 1.6
        DispatchQueue.main.asyncAfter(deadline: .now() + task2Base) {
            withAnimation(.easeOut(duration: 0.2)) { taskStatuses[2] = 1 }
            TutorialHaptics.arrival()
        }

        let assemblyStart = task2Base + 1.2

        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart) {
            withAnimation(.easeOut(duration: 0.4)) { projectAssembling = true }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.3) {
            withAnimation(.easeOut(duration: 0.4)) { cardBgOpacity = 1 }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.4) {
            withAnimation(.easeOut(duration: 0.6)) { borderDrawProgress = 1 }
            TutorialHaptics.commit()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + assemblyStart + 0.8) {
            startProjectTitleTypewriter()
        }

        let titleDone = assemblyStart + 0.8 + (Double(TutorialData.projectTitle.count) * 0.035) + 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + titleDone) {
            withAnimation(.easeOut(duration: 0.5)) { progressBarValue = 0.66 }
        }

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

    // MARK: → Calendar (13-stage sequence)

    private func transitionToCalendar() {
        let schedule = TutorialData.calendarSchedule

        guard !reduceMotion else {
            state.advancePhase()
            hideProjectCard = true
            calendarVisibleTasks = Set(schedule.map(\.id))
            calendarCompletedTasks = Set(schedule.filter { $0.completesOnDay != nil }.map(\.id))
            calendarFadeCompleted = true
            showCalendar = true
            showCalendarHeader = true

            // Skip directly to review
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                showCalendar = false
                showCalendarHeader = false
                state.advancePhase() // → weeklyReview
                showReviewStack = true
                transitionHeader()
            }
            return
        }

        let deckTasks = schedule.filter { $0.isDeckTask }
        let otherTasks = schedule.filter { !$0.isDeckTask }
        var t: Double = 0.5

        // STAGE 1: Project card chrome dissolves
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.5)) {
                projectChromeFading = true
                borderDrawProgress = 0
                cardBgOpacity = 0
                progressBarValue = 0
                projectTitleChars = 0
            }
        }
        t += 0.8

        // STAGE 2: Individual borders draw around each task
        for i in 0..<3 {
            let drawTime = t + Double(i) * 0.4
            DispatchQueue.main.asyncAfter(deadline: .now() + drawTime) {
                withAnimation(.easeOut(duration: 0.35)) { taskDetachBorders[i] = 1 }
                TutorialHaptics.arrival()
            }
        }
        t += 3 * 0.4 + 0.5

        // STAGE 3: Calendar grid appears
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) { showCalendar = true }
        }
        t += 0.5

        // STAGE 4: Project card slides up, deck tasks fly to calendar
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            state.advancePhase() // → calendarWeek
            transitionHeader()

            withAnimation(.easeOut(duration: 0.35)) { hideProjectCard = true }
        }

        for (idx, task) in deckTasks.enumerated() {
            let flyTime = t + 0.2 + Double(idx) * 0.35
            DispatchQueue.main.asyncAfter(deadline: .now() + flyTime) {
                withAnimation(.easeOut(duration: 0.4)) {
                    _ = calendarVisibleTasks.insert(task.id)
                }
                TutorialHaptics.arrival()
            }
        }
        t += 0.2 + Double(deckTasks.count) * 0.35 + 0.5

        // STAGE 5: Other tasks appear — stagger in more slowly
        for (idx, task) in otherTasks.enumerated() {
            let addTime = t + Double(idx) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + addTime) {
                withAnimation(.easeOut(duration: 0.25)) {
                    _ = calendarVisibleTasks.insert(task.id)
                }
            }
        }
        t += Double(otherTasks.count) * 0.2 + 0.8

        // STAGE 6: Day-by-day focus — hold each day longer so user can read
        for day in 0..<5 {
            let dayStart = t

            DispatchQueue.main.asyncAfter(deadline: .now() + dayStart) {
                withAnimation(.easeOut(duration: 0.4)) { calendarFocusDay = day }
                TutorialHaptics.arrival()
            }
            t += 0.7

            let dayCompletions = schedule.filter { $0.completesOnDay == day }
            for task in dayCompletions {
                let completeTime = t
                DispatchQueue.main.asyncAfter(deadline: .now() + completeTime) {
                    withAnimation(.easeOut(duration: 0.25)) {
                        _ = calendarCompletedTasks.insert(task.id)
                    }
                    TutorialHaptics.arrival()
                }
                t += 0.45
            }
            t += 0.4
        }

        // STAGE 7: Zoom back out — let user see the full picture
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.45)) { calendarFocusDay = -1 }
        }
        t += 1.0

        // STAGE 8: Completed tasks fade
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeIn(duration: 0.5)) { calendarFadeCompleted = true }
        }
        t += 1.2

        // STAGE 9: "4 TASKS NOT COMPLETE" header — hold longer
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) { showCalendarHeader = true }
        }
        t += 2.0

        // STAGE 10: Bars expand into card shapes
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.6)) { calendarExtractPhase = 1 }
            TutorialHaptics.arrival()
        }
        t += 1.0

        // STAGE 11: Titles appear
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.35)) { calendarExtractPhase = 2 }
        }
        t += 0.6

        // STAGE 12: Wireframe illustrations draw in (mask-based reveal)
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) { calendarExtractPhase = 3 }
        }
        t += 0.8

        // STAGE 13: Calendar disappears, review stack appears — matchedGeometryEffect
        // morphs the extracted cards into the review stack cards (hero transition).
        // Both state changes in one animation block so SwiftUI sees the source disappear
        // and destination appear simultaneously, triggering the matched geometry morph.
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            state.advancePhase() // → weeklyReview
            transitionHeader()

            withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                showCalendar = false
                showCalendarHeader = false
                showReviewStack = true
            }

            // Show swipe onboarding after cards settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                beginSwipeOnboarding()
            }
        }
    }

    // MARK: Review Swipe Onboarding

    private func beginSwipeOnboarding() {
        guard !reduceMotion else { return } // Skip for reduced motion — labels shown statically

        showSwipeOnboarding = true
        swipeOnboardingPhase = 0

        var t: Double = 0.4

        // Phase 1: Ghost card slides right
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) { swipeOnboardingPhase = 1 }
            TutorialHaptics.arrival()
        }
        t += 0.5

        // Phase 2: Hold right position, show COMPLETE label
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.2)) { swipeOnboardingPhase = 2 }
        }
        t += 1.0

        // Phase 3: Return to center
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            // dampingFraction 0.8 = controlled return, no bounce
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { swipeOnboardingPhase = 3 }
        }
        t += 0.5

        // Phase 4: Ghost card slides left
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.4)) { swipeOnboardingPhase = 4 }
            TutorialHaptics.arrival()
        }
        t += 0.5

        // Phase 5: Hold left position, show INCOMPLETE label
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.2)) { swipeOnboardingPhase = 5 }
        }
        t += 1.0

        // Phase 6: Return to center
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { swipeOnboardingPhase = 6 }
        }
        t += 0.5

        // Phase 7: Dismiss overlay
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                swipeOnboardingPhase = 7
                showSwipeOnboarding = false
            }
        }
    }

    // MARK: Review Swipe (with stacking)

    private func handleReviewSwipe(direction: String) {
        let wasRight = direction == "right"
        let justSwipedIndex = reviewCurrentIndex

        swipeResults.append(wasRight)
        state.recordSwipe(cardIndex: reviewCurrentIndex, direction: direction)

        // Add to completed stack if right-swiped
        if wasRight {
            if !showCompletedStack { showCompletedStack = true }
            withAnimation(.easeOut(duration: 0.3)) {
                completedCardIndices.append(justSwipedIndex)
            }
        }

        withAnimation(.easeOut(duration: 0.15)) {
            reviewCurrentIndex += 1
        }

        if wasRight {
            // RIGHT SWIPE: No popup. Task complete. Move on.
            TutorialHaptics.milestone()
            let isLast = reviewCurrentIndex >= TutorialData.reviewCards.count
            DispatchQueue.main.asyncAfter(deadline: .now() + (isLast ? 0.8 : 0.3)) {
                checkIfReviewDone()
            }
        } else {
            // LEFT SWIPE: Show "project incomplete" popup with reschedule options
            leftSwipeAction = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                completionSlideX = -120
                showingCompletion = justSwipedIndex

                withAnimation(.easeOut(duration: 0.3)) {
                    completionOpacity = 1
                    completionSlideX = 0
                }
                TutorialHaptics.arrival()
            }
        }
    }

    /// User tapped a reschedule action on left-swipe popup
    private func handleLeftSwipeAction(_ action: String) {
        TutorialHaptics.commit()
        withAnimation(.easeOut(duration: 0.2)) {
            leftSwipeAction = action
        }

        // Auto-dismiss 1.5s after action
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeIn(duration: 0.2)) {
                completionOpacity = 0
                completionSlideX = 60
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showingCompletion = nil
                completionSlideX = 0
                leftSwipeAction = nil
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
        // "All caught up" is already positioned behind the card stack.
        // Show it immediately — it's revealed when the last card flies away.
        showReviewDone = true
        reviewDoneScale = 1.0
        reviewDoneOpacity = 0

        // Brief pause, then reveal (last card has already flown off)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.3)) {
                showReviewStack = false
                reviewDoneOpacity = 1
            }
            TutorialHaptics.milestone()
        }

        // Hold, then transition to closeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            transitionToCloseout()
        }
    }

    // MARK: → Closeout + Financials (Phases 6-7 — merged per-project sequence)

    private func transitionToCloseout() {
        state.advancePhase() // → projectCloseout

        // Fade out "All caught up"
        withAnimation(.easeIn(duration: 0.25)) {
            reviewDoneOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showReviewDone = false
        }

        transitionHeader()

        // If no projects were completed, skip to closing
        guard !completedCardIndices.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                transitionToClosing()
            }
            return
        }

        guard !reduceMotion else {
            // Reduced motion: show final state of last project
            closeoutProjectOrder = completedCardIndices
            showCompletedStack = false
            showCloseoutCard = true
            closeoutCardScale = 1.0
            closeoutCardOffset = .zero
            closeoutStep = 5
            showCloseoutTasks = false
            showInvoiceLines = false
            showSentIndicator = false
            showPaidBanner = true
            closeoutTasksReturned = 10
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                showCloseoutCard = false
                transitionToClosing()
            }
            return
        }

        closeoutCurrentProject = 0
        closeoutProjectOrder = completedCardIndices // Snapshot before we start removing from the visual stack
        animateCloseoutForProject()
    }

    /// Handle user tap to advance to next project in closeout
    private func handleCloseoutContinue() {
        TutorialHaptics.commit()
        closeoutWaitingForTap = false

        withAnimation(.easeOut(duration: 0.15)) { showCloseoutContinue = false }

        // Shrink card and advance
        withAnimation(.easeIn(duration: 0.25)) {
            closeoutCardScale = 0.85
            closeoutCardOpacity = 0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            showCloseoutCard = false
            closeoutCurrentProject += 1
            animateCloseoutForProject()
        }
    }

    /// Animate the full lifecycle for one completed project:
    /// expand from stack → project tasks → invoice → sent → paid → financial bars → wait for tap.
    /// User taps CONTINUE to acknowledge, then next project begins.
    private func animateCloseoutForProject() {
        let completedProjects = closeoutProjectOrder
        guard closeoutCurrentProject < completedProjects.count else {
            // All projects done — transition to closing
            withAnimation(.easeOut(duration: 0.2)) { showCompletedStack = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                transitionToClosing()
            }
            return
        }

        // Reset per-project morph state
        closeoutStep = 0
        showCloseoutTasks = false
        showInvoiceLines = false
        showSentIndicator = false
        showPaidBanner = false
        revenueBarProgress = 0
        expenseBarProgress = 0
        showProfitLine = false
        closeoutTasksReturned = 0
        closeoutSwipeDrag = .zero
        closeoutSwipeCommitted = false
        closeoutSwipeHapticFired = false
        closeoutCardScale = 0.35
        let offsetX = stackCenter.x - contentCenter.x
        let offsetY = stackCenter.y - contentCenter.y
        closeoutCardOffset = CGSize(width: offsetX, height: offsetY)
        closeoutCardOpacity = 0
        showCloseoutContinue = false

        // Get task count for this project (used for step 6 task return)
        let cardIdx = completedProjects[closeoutCurrentProject]
        let taskCount = TutorialDataV2.closeoutProject(for: cardIdx).tasks.count

        var t: Double = 0.15

        // ── STEP 1: Card expands from stack to center ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.15)) {
                completedCardIndices.removeAll { $0 == cardIdx }
            }
            showCloseoutCard = true
            closeoutCardOpacity = 1
            // dampingFraction 0.8 = controlled expansion, no bounce
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                closeoutCardScale = 1.0
                closeoutCardOffset = .zero
            }
            TutorialHaptics.arrival()
        }
        t += 0.7

        // ── STEP 2: Task checklist appears ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) { showCloseoutTasks = true }
            TutorialHaptics.arrival()
        }
        t += 1.0

        // ── STEP 3: Tasks crossfade to invoice ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                showCloseoutTasks = false
                closeoutStep = 1
            }
        }
        t += 0.4

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) { showInvoiceLines = true }
            TutorialHaptics.arrival()
        }
        t += 0.8

        // ── STEP 4: SENT + PAID ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.2)) {
                closeoutStep = 2
                showSentIndicator = true
            }
            TutorialHaptics.commit()
        }
        t += 0.8

        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.25)) {
                closeoutStep = 3
                showPaidBanner = true
            }
            TutorialHaptics.milestone()
        }
        t += 1.0

        // ── STEP 5: Invoice fades, tasks return one at a time → project card ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            if state.currentPhase == .projectCloseout {
                state.advancePhase()
                transitionHeader()
            }
            withAnimation(.easeOut(duration: 0.3)) {
                showInvoiceLines = false
                closeoutStep = 5
            }
        }
        t += 0.4

        // Fade tasks back in one at a time (200ms apart)
        for i in 0..<taskCount {
            let taskDelay = t + Double(i) * 0.2
            DispatchQueue.main.asyncAfter(deadline: .now() + taskDelay) {
                withAnimation(.easeOut(duration: 0.2)) {
                    closeoutTasksReturned = i + 1
                }
                TutorialHaptics.arrival()
            }
        }
        t += Double(taskCount) * 0.2 + 0.4

        // ── STEP 7: Enable swipe-to-close — matches job board pattern ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            closeoutSwipeCommitted = false
            closeoutSwipeDrag = .zero
            closeoutSwipeHapticFired = false
            withAnimation(.easeOut(duration: 0.25)) { showSwipeHint = true }
        }
    }

    private func startCloseoutNameTypewriter() {
        guard closeoutCurrentProject < closeoutProjectOrder.count else { return }
        let cardIdx = closeoutProjectOrder[closeoutCurrentProject]
        let name = TutorialData.reviewCards[cardIdx].project.uppercased()
        var charCount = 0

        closeoutNameTimer?.invalidate()
        closeoutNameTimer = Timer.scheduledTimer(withTimeInterval: 0.035, repeats: true) { timer in
            charCount += 1
            closeoutNameChars = charCount
            if charCount >= name.count {
                timer.invalidate()
            }
        }
    }

    /// Matches job board handleSwipeEndedWidth exactly:
    /// 1. Snap card content back to center (swipeOffset → 0)
    /// 2. Show confirmation flash (isChangingStatus = true, full CLOSED card on top)
    /// 3. Brief hold, then dismiss and transition to next project
    private func commitCloseoutSwipe() {
        closeoutSwipeCommitted = true

        // Step 1: Snap card back — matches job board .easeInOut(duration: 0.25)
        withAnimation(.easeInOut(duration: 0.25)) {
            closeoutSwipeDrag = .zero
        }

        // Step 2: Confirmation flash — matches job board 50ms delay for tutorial mode
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            TutorialHaptics.milestone()
        }

        // Step 3: Brief hold on confirmation, then dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.25)) {
                self.closeoutSwipeCommitted = false
            }
        }

        // Step 4: Transition — stack mode for remaining projects, or closing if done
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.showCloseoutCard = false
            self.showSwipeHint = false
            self.closeoutSwipeDrag = .zero
            self.closeoutSwipeCommitted = false
            self.closeoutSwipeHapticFired = false

            let remainingCount = self.closeoutProjectOrder.count - (self.closeoutCurrentProject + 1)

            if remainingCount > 0 {
                self.enterCloseoutStackMode()
            } else {
                withAnimation(.easeOut(duration: 0.2)) { self.showCompletedStack = false }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    self.transitionToClosing()
                }
            }
        }
    }

    // MARK: → Stack Mode (expedited closeout for remaining projects)

    /// Runs expedited invoice → SENT → PAID animation for each remaining project,
    /// then transitions to the swipeable stack with hint overlay.
    private func enterCloseoutStackMode() {
        let remainingIndices = (closeoutCurrentProject + 1)..<closeoutProjectOrder.count

        guard !remainingIndices.isEmpty else {
            withAnimation(.easeOut(duration: 0.2)) { showCompletedStack = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.transitionToClosing() }
            return
        }

        // Store the card indices for the stack (stable reference, independent of closeoutCurrentProject)
        closeoutStackCards = remainingIndices.map { closeoutProjectOrder[$0] }

        var totalDelay: Double = 0.3

        for projectIndex in remainingIndices {
            let cardIdx = closeoutProjectOrder[projectIndex]
            let startDelay = totalDelay

            // ── Expand card from completed stack ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay) {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.completedCardIndices.removeAll { $0 == cardIdx }
                }

                // Reset per-card state
                self.closeoutCurrentProject = projectIndex
                self.closeoutStep = 0
                self.showCloseoutTasks = false
                self.showInvoiceLines = false
                self.showSentIndicator = false
                self.showPaidBanner = false
                self.closeoutTasksReturned = 0
                self.closeoutSwipeDrag = .zero
                self.closeoutSwipeCommitted = false
                self.closeoutSwipeHapticFired = false
                self.showSwipeHint = false
                self.closeoutCardScale = 0.35
                let offsetX = self.stackCenter.x - self.contentCenter.x
                let offsetY = self.stackCenter.y - self.contentCenter.y
                self.closeoutCardOffset = CGSize(width: offsetX, height: offsetY)
                self.closeoutCardOpacity = 0

                self.showCloseoutCard = true
                self.closeoutCardOpacity = 1
                // dampingFraction 0.85 = fast controlled expansion, no bounce
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    self.closeoutCardScale = 1.0
                    self.closeoutCardOffset = .zero
                }
                TutorialHaptics.arrival()
            }

            // ── Invoice header ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + 0.4) {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.closeoutStep = 1
                    self.showInvoiceLines = true
                }
            }

            // ── SENT ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + 0.7) {
                withAnimation(.easeOut(duration: 0.12)) {
                    self.closeoutStep = 2
                    self.showSentIndicator = true
                }
            }

            // ── PAID ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + 1.0) {
                withAnimation(.easeOut(duration: 0.15)) {
                    self.closeoutStep = 3
                    self.showPaidBanner = true
                }
                TutorialHaptics.milestone()
            }

            // ── Shrink + fade ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + 1.5) {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.closeoutCardScale = 0.85
                    self.closeoutCardOpacity = 0
                }
            }

            // ── Hide card ──
            DispatchQueue.main.asyncAfter(deadline: .now() + startDelay + 1.75) {
                self.showCloseoutCard = false
            }

            totalDelay = startDelay + 1.9
        }

        // After all expedited animations, show the stack with swipe hint
        DispatchQueue.main.asyncAfter(deadline: .now() + totalDelay + 0.2) {
            self.showCloseoutStackWithHint()
        }
    }

    /// Transitions to the swipeable stack with hint overlay on the first card.
    private func showCloseoutStackWithHint() {
        if state.currentPhase == .projectCloseout {
            state.advancePhase()
            transitionHeader()
        }

        withAnimation(.easeOut(duration: 0.2)) {
            showCompletedStack = false
        }

        closeoutStackClosed = []
        closeoutStackHintShowing = true
        closeoutStackVisible = closeoutStackCards.count

        withAnimation(.easeOut(duration: 0.3)) {
            closeoutStackMode = true
        }
    }

    private func handleStackCardClosed(_ cardIdx: Int) {
        withAnimation(.easeInOut(duration: 0.35)) {
            closeoutStackClosed.insert(cardIdx)
            // After first card is swiped, remove the hint overlay — rest become fully interactive
            if closeoutStackHintShowing {
                closeoutStackHintShowing = false
            }
        }
        TutorialHaptics.milestone()

        if closeoutStackClosed.count >= closeoutStackCards.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.2)) {
                    self.closeoutStackMode = false
                }
                self.transitionToClosing()
            }
        }
    }

    // MARK: → Closing Sequence (Phase 8)

    private func startClosingTypewriter(lineIndex: Int) {
        let lines = ["OPS HANDLES 85%.", "YOU HANDLE THE JOB SITE.", "LEAVE THE PAPERWORK TO US."]
        guard lineIndex < lines.count else { return }
        let text = lines[lineIndex]
        var charCount = 0

        closingTaglineTimers[lineIndex]?.invalidate()
        closingTaglineTimers[lineIndex] = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { timer in
            charCount += 1
            closingTaglineChars[lineIndex] = charCount
            if charCount >= text.count {
                timer.invalidate()
            }
        }
    }

    private func transitionToClosing() {
        // Advance to closing phase (may need to skip financials if we're still there)
        while state.currentPhase != .closing {
            if state.currentPhase.next == nil { break }
            state.advancePhase()
        }

        transitionHeader()

        // Hide any remaining UI from previous phases — force-clear everything
        withAnimation(.easeOut(duration: 0.2)) {
            showCompletedStack = false
            showCloseoutCard = false
            completedCardIndices.removeAll()
        }

        guard !reduceMotion else {
            showClosing = true
            closingStepsVisible = TutorialData.closingSteps.count
            closingStrikeCount = TutorialData.closingSteps.filter(\.opsHandles).count
            for i in 0..<closingStrikeProgress.count {
                if TutorialData.closingSteps[i].opsHandles { closingStrikeProgress[i] = 1 }
            }
            closingCollapsed = true
            closingSurvivorsHighlighted = true
            showClosingLists = true
            closingTaglineProgress = 3
            closingTaglineChars = [50, 50, 50] // Full text visible
            showCTA = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            withAnimation(.easeOut(duration: 0.25)) { showClosing = true }
            startClosingSequence()
        }
    }

    private func startClosingSequence() {
        let steps = TutorialData.closingSteps
        let opsIndices = steps.enumerated().filter { $0.element.opsHandles }.map { $0.offset }
        var t: Double = 0.3

        // ── Phase A: Type in all 13 steps (0.15s apart) ──
        for i in 0..<steps.count {
            let writeTime = t + Double(i) * 0.15
            DispatchQueue.main.asyncAfter(deadline: .now() + writeTime) {
                withAnimation(.easeOut(duration: 0.12)) { closingStepsVisible = i + 1 }
                TutorialHaptics.arrival()
            }
        }
        t += Double(steps.count) * 0.15 + 0.6

        // ── Phase B: Strikethrough draws across each OPS step (0.1s apart) ──
        for (strikeOrder, stepIdx) in opsIndices.enumerated() {
            let strikeTime = t + Double(strikeOrder) * 0.1
            DispatchQueue.main.asyncAfter(deadline: .now() + strikeTime) {
                closingStrikeCount = strikeOrder + 1
                withAnimation(.easeOut(duration: 0.12)) {
                    closingStrikeProgress[stepIdx] = 1.0
                }
                TutorialHaptics.strikethrough()
            }
        }
        t += Double(opsIndices.count) * 0.1 + 0.8

        // ── Phase C: Morph into two columns ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.35)) {
                showClosingLists = true
            }
            TutorialHaptics.milestone()
        }
        t += 2.0 // Hold the two-column view so user can read it

        // ── Phase D: Columns dissolve, then tagline ──

        // Step 1: Items collapse within columns
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.35)) {
                closingListsCollapsing = true
            }
        }
        t += 0.45

        // Step 2: Both column containers fade + scale out together
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeInOut(duration: 0.4)) {
                closingOpsListFaded = true
                closingYouListFaded = true
            }
        }
        t += 0.6

        // Step 3: Begin tagline typewriter
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) {
                closingTaglineProgress = 1 // Shows line 0, hides columns
            }
            startClosingTypewriter(lineIndex: 0)
        }

        // Typewriter line 0: "OPS HANDLES 85%." — 16 chars at 40ms = 0.64s
        t += 1.0

        // Step 5: Line 2 starts
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.15)) { closingTaglineProgress = 2 }
            startClosingTypewriter(lineIndex: 1)
        }

        // "YOU HANDLE THE JOB SITE." — 24 chars at 40ms = 0.96s
        t += 1.2

        // Step 6: Line 3 starts
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.15)) { closingTaglineProgress = 3 }
            startClosingTypewriter(lineIndex: 2)
            TutorialHaptics.commit()
        }

        // "LEAVE THE PAPERWORK TO US." — 26 chars at 40ms = 1.04s
        t += 1.4

        // ── Phase E: CTA ──
        DispatchQueue.main.asyncAfter(deadline: .now() + t) {
            withAnimation(.easeOut(duration: 0.3)) { showCTA = true }
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Closeout Swipe Hint (shimmer)
// MARK: ═══════════════════════════════════════════════════════════════════════

/// "TAP THE LEAD" hint with a pulsing glow.
private struct TapToBeginHint: View {
    @State private var glowActive = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.tap")
                .font(.system(size: 12, weight: .medium))

            Text("TAP THE LEAD")
                .font(.custom("Mohave-Medium", size: 12))
                .tracking(2)
        }
        .foregroundStyle(Color.white.opacity(glowActive ? 0.6 : 0.2))
        .shadow(color: Color.white.opacity(glowActive ? 0.3 : 0), radius: 8, x: 0, y: 0)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowActive = true
            }
        }
    }
}

/// Compact PAID card for stack mode — self-contained swipe-to-close with graceful collapse.
/// Shows project name, client, color stripe, and PAID badge. Swipe right to close.
/// On commit: snaps back, flashes CLOSED state, then calls onClosed for parent to collapse.
private struct CloseoutStackCard: View {
    let projectName: String
    let clientName: String
    let color: Color
    let onClosed: () -> Void

    @State private var dragOffset: CGFloat = 0
    @State private var committed = false
    @State private var hapticFired = false

    private let threshold: CGFloat = 140

    var body: some View {
        let closedColor = OPSStyle.Colors.statusColor(for: .closed)

        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1)
                .fill(committed ? closedColor : color)
                .frame(width: 3, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(projectName.uppercased())
                    .font(.headingBold)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.8)

                Text(clientName)
                    .font(.caption)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            if committed {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("CLOSED")
                        .font(.status)
                        .tracking(1.5)
                }
                .foregroundStyle(closedColor)
                .transition(.opacity)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                    Text("PAID")
                        .font(.status)
                        .tracking(1.5)
                }
                .foregroundStyle(OPSStyle.Colors.successStatus)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(committed
                    ? closedColor.opacity(0.05)
                    : OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(
                    committed
                        ? closedColor.opacity(0.3)
                        : OPSStyle.Colors.successStatus.opacity(0.2),
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
        .offset(x: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard !committed else { return }
                    dragOffset = max(0, value.translation.width) // Right-swipe only
                    if dragOffset >= threshold && !hapticFired {
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        hapticFired = true
                    }
                }
                .onEnded { value in
                    guard !committed else { return }
                    if value.translation.width >= threshold {
                        // Commit: snap back, show CLOSED, then collapse
                        committed = true
                        withAnimation(.easeInOut(duration: 0.2)) {
                            dragOffset = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            onClosed()
                        }
                    } else {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            dragOffset = 0
                        }
                        hapticFired = false
                    }
                }
        )
        .animation(.easeOut(duration: 0.2), value: committed)
    }
}

/// "SWIPE TO CLOSE" hint with a pulsing glow ripple.
/// Glow pulses between dim and bright on a 1.5s loop — subtle, ambient, not aggressive.
private struct CloseoutSwipeHint: View {
    @State private var glowActive = false

    var body: some View {
        HStack(spacing: 8) {
            Text("SWIPE TO CLOSE")
                .font(.custom("Mohave-Medium", size: 12))
                .tracking(2)

            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(Color.white.opacity(glowActive ? 0.6 : 0.2))
        // Glow shadow — pulses with the text opacity
        .shadow(color: Color.white.opacity(glowActive ? 0.3 : 0), radius: 8, x: 0, y: 0)
        .onAppear {
            // easeInOut 1.5s autoreverses = smooth breathing glow
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                glowActive = true
            }
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Calendar Week View (V2)
// MARK: ═══════════════════════════════════════════════════════════════════════

/// Gantt-style week calendar with animated column widths and bar extraction.
/// V2: Uses mask-based wireframe reveal, matchedGeometryEffect for calendar→review morph.
private struct FlowCalendarWeekV2: View {
    let visibleTasks: Set<String>
    let completedTasks: Set<String>
    let focusDay: Int
    let fadeCompleted: Bool
    let extractPhase: Int
    var calendarNS: Namespace.ID      // Shared namespace for calendar→review hero morph

    private let schedule = TutorialData.calendarSchedule
    private let dayLabels = TutorialData.dayLabels
    private let totalRows = 6
    private let barHeight: CGFloat = 34
    private let barSpacing: CGFloat = 4
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
                // Day column separators
                ForEach(1..<5, id: \.self) { i in
                    let cw = colWidth(i, in: w)
                    Rectangle()
                        .fill(OPSStyle.Colors.separator.opacity(0.3))
                        .frame(width: 0.5, height: normalCalH - headerHeight)
                        .offset(x: colX(i, in: w), y: headerHeight)
                        .opacity(isExtracting ? 0 : (cw > 1 ? 1 : 0))
                }

                // Day labels
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

                // Task bars — use .position() for all bars so matchedGeometryEffect
                // captures correct screen-space frame for the calendar→review morph
                ForEach(schedule) { task in
                    if visibleTasks.contains(task.id) {
                        let isComplete = completedTasks.contains(task.id)
                        let isIncomplete = task.completesOnDay == nil

                        let startX = colX(task.startDay, in: w) + barInset
                        let endX = colX(task.endDay, in: w) + colWidth(task.endDay, in: w) - barInset
                        let normalWidth = max(endX - startX, 0)
                        let normalY = headerHeight + 4 + CGFloat(task.row) * (barHeight + barSpacing)

                        let extractIdx = CGFloat(task.reviewCardIndex ?? 0)
                        let shouldExtract = isExtracting && isIncomplete

                        let bw = shouldExtract ? extractedCardW : normalWidth
                        let bh = shouldExtract ? extractedCardH : barHeight
                        // Center point for .position() — converts from top-left origin
                        let centerX = (shouldExtract ? 16 : startX) + bw / 2
                        let centerY = (shouldExtract ? (extractIdx * 8) : normalY) + bh / 2

                        ZStack(alignment: .topLeading) {
                            if shouldExtract {
                                // Extracting: show the full review card
                                extractedCard(task: task)
                            } else {
                                // Normal: show the gantt bar
                                ganttBar(task: task, isComplete: isComplete, isIncomplete: isIncomplete)
                            }
                        }
                        .frame(width: bw, height: bh)
                        .background {
                            let bgColor: Color = shouldExtract ? .clear :
                                (isIncomplete && fadeCompleted ? task.color.opacity(0.12) : OPSStyle.Colors.cardBackgroundDark)
                            RoundedRectangle(cornerRadius: shouldExtract
                                ? OPSStyle.Layout.cardCornerRadius
                                : OPSStyle.Layout.smallCornerRadius)
                                .fill(bgColor)
                        }
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
                        .position(x: centerX, y: centerY)
                        .scaleEffect(shouldExtract ? (1.0 - extractIdx * 0.03) : 1.0,
                                     anchor: .top)
                        // matchedGeometryEffect on extracted cards — connects to review stack cards
                        .matchedGeometryEffect(
                            id: shouldExtract ? "calToReview_\(task.reviewCardIndex ?? 0)" : "calBar_\(task.id)",
                            in: calendarNS,
                            isSource: true
                        )
                        .zIndex(shouldExtract ? Double(10 + 4 - (task.reviewCardIndex ?? 0)) : 0)
                        .opacity(
                            shouldExtract ? 1.0 :
                            isExtracting ? 0 :
                            bw < 2 ? 0 :
                            fadeCompleted && isComplete ? 0.1 :
                            isComplete ? 0.5 : 1.0
                        )
                        .transition(task.isDeckTask
                            ? .asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity)
                            : .opacity)
                    }
                }
            }
        }
        .frame(height: isExtracting ? 500 : (headerHeight + CGFloat(totalRows) * (barHeight + barSpacing) + 16))
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

    // MARK: - Gantt Bar

    /// Crew name for a completed task — alternates between the two crew members
    private func crewForTask(_ task: TutorialData.CalendarScheduleTask) -> TutorialData.CrewMember {
        // Assign crew based on row parity for visual variety
        let members = TutorialData.crewMembers
        return members[task.row % members.count]
    }

    private func ganttBar(task: TutorialData.CalendarScheduleTask, isComplete: Bool, isIncomplete: Bool) -> some View {
        ZStack {
            // Normal task bar content — color stripe flush left via overlay
            VStack(alignment: .leading, spacing: 1) {
                Text(task.name.uppercased())
                    .font(.custom("Mohave-Medium", size: 11))
                    .minimumScaleFactor(0.55)
                    .foregroundStyle(isComplete ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .tracking(0.3)
                    .lineLimit(1)

                Text(task.projectName)
                    .font(.system(size: 8))
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 4)
            .padding(.top, 5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Color stripe as overlay on the left edge — no layout impact
            .overlay(alignment: .leading) {
                task.color
                    .frame(width: 3)
            }
            .opacity(isComplete ? 0.3 : 1)

            // Completed overlay — crew name with avatar
            if isComplete {
                let crew = crewForTask(task)
                HStack(spacing: 4) {
                    Circle()
                        .fill(crew.color.opacity(0.3))
                        .frame(width: 16, height: 16)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 7))
                                .foregroundStyle(crew.color)
                        )

                    Text(crew.name.split(separator: " ").first.map(String.init) ?? "")
                        .font(.custom("Mohave-Medium", size: 9))
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                        .tracking(0.5)

                    Image(systemName: "checkmark")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                }
                .transition(.opacity)
            }
        }
        // Background fill moved to outer ZStack wrapper — guarantees frame alignment
    }

    // MARK: - Extracted Card

    @State private var wireframeDrawProgress: CGFloat = 0

    /// Extracted card must be pixel-identical to FlowReviewCardV2 at extractPhase 3.
    /// Phases: 1 = colored background only. 2 = text + gradients appear. 3 = wireframe draws in (full match).
    private func extractedCard(task: TutorialData.CalendarScheduleTask) -> some View {
        let cardIdx = task.reviewCardIndex ?? 0
        let card = TutorialData.reviewCards[cardIdx]
        let showText = extractPhase >= 2
        let showWireframe = extractPhase >= 3

        return ZStack(alignment: .bottomLeading) {
            // Base layers — identical to FlowReviewCardV2
            Color.black // FlowReviewCardV2 has .background(Color.black)

            OPSStyle.Colors.cardBackgroundDark

            // Wireframe — mask-based reveal for draw-in, full opacity at 0.22
            FlowWireframeV2(variant: cardIdx)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: showWireframe ? geo.size.width : 0)
                            .animation(.easeOut(duration: 0.8), value: showWireframe)
                    }
                }
                .opacity(0.22)

            // Color stripe at top — always present (matches FlowReviewCardV2)
            VStack {
                Rectangle()
                    .fill(card.color)
                    .frame(height: 3)
                Spacer()
            }

            // Top gradient — always present in FlowReviewCardV2, fades in here at phase 2
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

            // Bottom gradient — always present in FlowReviewCardV2, fades in here at phase 2
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )
            .opacity(showText ? 1 : 0)

            // Info overlay — identical layout to FlowReviewCardV2
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
            .padding(24)
            .padding(.bottom, 40)
            .opacity(showText ? 1 : 0)
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Review Swipe Card (V2)
// MARK: ═══════════════════════════════════════════════════════════════════════

private struct FlowReviewCardV2: View {

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
            ZStack {
                OPSStyle.Colors.cardBackgroundDark

                FlowWireframeV2(variant: cardIndex)
                    .opacity(0.22)
            }

            // Color stripe at top
            VStack {
                Rectangle()
                    .fill(card.color)
                    .frame(height: 3)
                Spacer()
            }

            // Top gradient
            VStack {
                LinearGradient(
                    gradient: Gradient(colors: [.black.opacity(0.55), .clear]),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 100)
                Spacer()
            }

            // Bottom gradient
            LinearGradient(
                gradient: Gradient(colors: [.clear, .black.opacity(0.85)]),
                startPoint: .center,
                endPoint: .bottom
            )

            // Info overlay
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
            .padding(24)
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

        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = CGSize(width: flyX, height: dragOffset.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwiped(direction)
        }
    }
}

// MARK: ═══════════════════════════════════════════════════════════════════════
// MARK: Wireframe Illustrations (V2)
// MARK: ═══════════════════════════════════════════════════════════════════════

/// Four distinct wireframe line drawings for review cards.
/// Monochrome white lines. Blueprint aesthetic.
private struct FlowWireframeV2: View {
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

    private func drawDuplex(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        path.move(to: CGPoint(x: w * 0.1, y: ground))
        path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.3, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.5, y: ground))
        path.move(to: CGPoint(x: w * 0.5, y: ground))
        path.addLine(to: CGPoint(x: w * 0.5, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.7, y: h * 0.2))
        path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.35))
        path.addLine(to: CGPoint(x: w * 0.9, y: ground))
        path.addRect(CGRect(x: w * 0.25, y: h * 0.6, width: w * 0.08, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.67, y: h * 0.6, width: w * 0.08, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.15, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.38, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.55, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        path.addRect(CGRect(x: w * 0.8, y: h * 0.45, width: w * 0.07, height: w * 0.07))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

    private func drawDeckRailing(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        let deckTop = h * 0.55
        let deckLeft = w * 0.15
        let deckRight = w * 0.85
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        path.move(to: CGPoint(x: deckLeft, y: deckTop))
        path.addLine(to: CGPoint(x: deckRight, y: deckTop))
        path.addLine(to: CGPoint(x: deckRight, y: deckTop + 4))
        path.addLine(to: CGPoint(x: deckLeft, y: deckTop + 4))
        path.closeSubpath()
        for i in 0..<5 {
            let x = deckLeft + (deckRight - deckLeft) * CGFloat(i) / 4.0
            path.move(to: CGPoint(x: x, y: deckTop))
            path.addLine(to: CGPoint(x: x, y: ground))
        }
        let railTop = h * 0.35
        for i in 0...6 {
            let x = deckLeft + (deckRight - deckLeft) * CGFloat(i) / 6.0
            path.move(to: CGPoint(x: x, y: deckTop))
            path.addLine(to: CGPoint(x: x, y: railTop))
        }
        path.move(to: CGPoint(x: deckLeft, y: railTop))
        path.addLine(to: CGPoint(x: deckRight, y: railTop))
        let midRail = (railTop + deckTop) / 2
        path.move(to: CGPoint(x: deckLeft, y: midRail))
        path.addLine(to: CGPoint(x: deckRight, y: midRail))
        let stepW = w * 0.08
        for i in 0..<3 {
            let sy = deckTop + CGFloat(i) * (ground - deckTop) / 3
            path.move(to: CGPoint(x: deckRight, y: sy))
            path.addLine(to: CGPoint(x: deckRight + stepW, y: sy))
            path.addLine(to: CGPoint(x: deckRight + stepW, y: sy + (ground - deckTop) / 3))
        }
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

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
        let doorTop = h * 0.45
        path.move(to: CGPoint(x: partition - 1, y: doorTop))
        path.addLine(to: CGPoint(x: partition - 1, y: bottom))
        var arc = Path()
        arc.addArc(center: CGPoint(x: partition, y: bottom),
                   radius: bottom - doorTop,
                   startAngle: .degrees(180),
                   endAngle: .degrees(270),
                   clockwise: false)
        context.stroke(arc, with: .color(color), lineWidth: 0.4)
        let winY = h * 0.3
        let winH = h * 0.15
        let winMid = winY + winH / 2
        path.move(to: CGPoint(x: left - 3, y: winY))
        path.addLine(to: CGPoint(x: left + 3, y: winY))
        path.move(to: CGPoint(x: left - 3, y: winY + winH))
        path.addLine(to: CGPoint(x: left + 3, y: winY + winH))
        path.move(to: CGPoint(x: left - 3, y: winMid))
        path.addLine(to: CGPoint(x: left + 3, y: winMid))
        let counterY = h * 0.65
        path.move(to: CGPoint(x: partition + w * 0.05, y: counterY))
        path.addLine(to: CGPoint(x: right - w * 0.05, y: counterY))
        path.addLine(to: CGPoint(x: right - w * 0.05, y: counterY + h * 0.04))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }

    private func drawHouseReno(context: GraphicsContext, w: CGFloat, h: CGFloat, color: Color) {
        var path = Path()
        let ground = h * 0.88
        let left = w * 0.2
        let right = w * 0.75
        let wallTop = h * 0.32
        path.move(to: CGPoint(x: 0, y: ground))
        path.addLine(to: CGPoint(x: w, y: ground))
        path.move(to: CGPoint(x: left, y: ground))
        path.addLine(to: CGPoint(x: left, y: wallTop))
        path.addLine(to: CGPoint(x: right, y: wallTop))
        path.addLine(to: CGPoint(x: right, y: ground))
        path.move(to: CGPoint(x: left - w * 0.04, y: wallTop))
        path.addLine(to: CGPoint(x: (left + right) / 2, y: h * 0.15))
        path.addLine(to: CGPoint(x: right + w * 0.04, y: wallTop))
        path.addRect(CGRect(x: w * 0.4, y: h * 0.6, width: w * 0.1, height: ground - h * 0.6))
        path.addRect(CGRect(x: w * 0.55, y: h * 0.45, width: w * 0.1, height: w * 0.08))
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
        path.move(to: CGPoint(x: scafLeft, y: ground))
        path.addLine(to: CGPoint(x: scafRight, y: ground - (ground - h * 0.2) / 4))
        path.move(to: CGPoint(x: scafRight, y: ground))
        path.addLine(to: CGPoint(x: scafLeft, y: ground - (ground - h * 0.2) / 4))
        context.stroke(path, with: .color(color), lineWidth: 0.8)
    }
}
