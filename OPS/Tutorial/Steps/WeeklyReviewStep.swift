import SwiftUI

/// Step 5: "End-of-Week Review" — THE HOOK
///
/// Emotional beat: COMMITMENT (Gamified)
/// Tinder-style card stack with large cards, wireframe illustrations,
/// and clear swipe instructions.
struct WeeklyReviewStep: View {

    let onComplete: () -> Void
    var onSwipe: ((Int, String) -> Void)?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var showIntro = true
    @State private var currentIndex: Int = 0
    @State private var showDone = false
    @State private var doneOpacity: Double = 0
    @State private var doneScale: CGFloat = 0.85

    private let cards = TutorialData.reviewCards

    var body: some View {
        ZStack {
            if showIntro {
                introView
            } else if showDone {
                doneView
            } else {
                swipeView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startSequence() }
    }

    // MARK: - Intro

    private var introView: some View {
        VStack(spacing: 6) {
            Text("FRIDAY.")
                .font(.headingLarge)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
                .tracking(2)
            Text("LET'S CLEAN UP.")
                .font(.headingLarge)
                .foregroundStyle(OPSStyle.Colors.secondaryText)
                .tracking(2)
        }
    }

    // MARK: - Swipe Stack

    private var swipeView: some View {
        let visibleCards: [(idx: Int, card: TutorialData.ReviewCard)] = Array(
            remainingCards.prefix(3).enumerated().map { (idx: $0.offset, card: $0.element) }
        ).reversed()

        return VStack(spacing: 0) {
            // Counter
            Text("\(currentIndex + 1) OF \(cards.count)")
                .font(.microLabel)
                .foregroundStyle(OPSStyle.Colors.tertiaryText)
                .tracking(2)
                .padding(.top, 60)
                .padding(.bottom, OPSStyle.Layout.spacing3)

            // Card stack
            ZStack {
                ForEach(visibleCards, id: \.card.id) { item in
                    TutorialReviewSwipeCard(
                        card: item.card,
                        isTop: item.idx == 0,
                        onSwiped: { direction in
                            handleSwipe(direction: direction)
                        }
                    )
                    .scaleEffect(1.0 - (CGFloat(item.idx) * 0.03))
                    .offset(y: CGFloat(item.idx) * 8)
                    .allowsHitTesting(item.idx == 0)
                    .zIndex(Double(3 - item.idx))
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)

            Spacer().frame(height: 24)

            // Swipe instruction
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

                Text("SWIPE TO REVIEW")
                    .font(.microLabel)
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
                    .tracking(1)

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
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Done

    private var doneView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Circle()
                .stroke(OPSStyle.Colors.successStatus.opacity(0.2), lineWidth: 1.5)
                .frame(width: 64, height: 64)
                .overlay(
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(OPSStyle.Colors.successStatus)
                )
                .scaleEffect(doneScale)

            Text("ALL CAUGHT UP")
                .font(.heading)
                .foregroundStyle(OPSStyle.Colors.primaryText)
                .tracking(2)
        }
        .opacity(doneOpacity)
    }

    // MARK: - Helpers

    private var remainingCards: [TutorialData.ReviewCard] {
        Array(cards.dropFirst(currentIndex))
    }

    private func startSequence() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                showIntro = false
            }
        }
    }

    private func handleSwipe(direction: String) {
        onSwipe?(currentIndex, direction)

        withAnimation(.easeOut(duration: 0.15)) {
            currentIndex += 1
        }

        if currentIndex >= cards.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                showAllDone()
            }
        }
    }

    private func showAllDone() {
        showDone = true
        TutorialHaptics.milestone()

        withAnimation(.easeOut(duration: 0.4)) {
            doneOpacity = 1
            doneScale = 1.0
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            onComplete()
        }
    }
}

// MARK: - Large Swipe Card with Wireframe Illustration

private struct TutorialReviewSwipeCard: View {

    let card: TutorialData.ReviewCard
    let isTop: Bool
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
        ZStack {
            cardContent

            // Stamps
            if isSwipingRight && swipeProgress > 0.1 {
                stampView(text: "COMPLETE", color: OPSStyle.Colors.successStatus, rotation: -12)
                    .opacity(swipeProgress)
            }
            if !isSwipingRight && swipeProgress > 0.1 {
                stampView(text: "SKIP", color: OPSStyle.Colors.inactiveStatus, rotation: 12)
                    .opacity(swipeProgress)
            }
        }
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
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            dragOffset = .zero
                        }
                    }
                }
        )
    }

    // MARK: - Card Content (Large, with wireframe)

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Wireframe illustration area
            ZStack {
                // Background — dark with subtle grid
                OPSStyle.Colors.cardBackgroundDark

                // Wireframe illustration — stylized house/jobsite outline
                wireframeIllustration
                    .opacity(0.12)
            }
            .frame(height: 180)
            .clipped()

            // Color stripe
            Rectangle()
                .fill(card.color)
                .frame(height: 3)

            // Card info
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                // Days ago badge
                HStack(spacing: 5) {
                    Circle()
                        .fill(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .frame(width: 5, height: 5)
                    Text(card.daysAgo == 1 ? "1 DAY AGO" : "\(card.daysAgo) DAYS AGO")
                        .font(.microLabel)
                        .foregroundStyle(card.daysAgo >= 5 ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.warningStatus)
                        .tracking(1)
                }

                // Task name — large
                Text(card.task.uppercased())
                    .font(.headingLarge)
                    .foregroundStyle(OPSStyle.Colors.primaryText)
                    .tracking(0.8)

                // Project + Client
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    HStack(spacing: 6) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 11))
                        Text(card.project)
                            .font(.caption)
                    }
                    .foregroundStyle(OPSStyle.Colors.secondaryText)

                    HStack(spacing: 6) {
                        Image(systemName: "person.circle.fill")
                            .font(.system(size: 11))
                        Text(card.client)
                            .font(.caption)
                    }
                    .foregroundStyle(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3_5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .fill(OPSStyle.Colors.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius))
    }

    // MARK: - Wireframe Illustration

    /// A minimal, architectural line drawing representing a jobsite.
    /// Different for each card based on the task color (used as seed).
    private var wireframeIllustration: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let strokeColor = Color.white

            // Ground line
            var ground = Path()
            ground.move(to: CGPoint(x: 0, y: h * 0.85))
            ground.addLine(to: CGPoint(x: w, y: h * 0.85))
            context.stroke(ground, with: .color(strokeColor), lineWidth: 1)

            // House/structure outline — varies by card
            var structure = Path()

            // Main structure rectangle
            let left = w * 0.2
            let right = w * 0.8
            let top = h * 0.3
            let bottom = h * 0.85

            structure.move(to: CGPoint(x: left, y: bottom))
            structure.addLine(to: CGPoint(x: left, y: top))
            structure.addLine(to: CGPoint(x: right, y: top))
            structure.addLine(to: CGPoint(x: right, y: bottom))

            // Roof — peaked
            structure.move(to: CGPoint(x: left - w * 0.05, y: top))
            structure.addLine(to: CGPoint(x: w * 0.5, y: h * 0.12))
            structure.addLine(to: CGPoint(x: right + w * 0.05, y: top))

            context.stroke(structure, with: .color(strokeColor), lineWidth: 0.8)

            // Door
            var door = Path()
            let doorLeft = w * 0.42
            let doorRight = w * 0.52
            let doorTop = h * 0.58
            door.addRect(CGRect(x: doorLeft, y: doorTop, width: doorRight - doorLeft, height: bottom - doorTop))
            context.stroke(door, with: .color(strokeColor), lineWidth: 0.6)

            // Windows
            let windowSize: CGFloat = w * 0.08
            let windowY = h * 0.42
            var windows = Path()
            // Left window
            windows.addRect(CGRect(x: left + w * 0.06, y: windowY, width: windowSize, height: windowSize))
            // Right window
            windows.addRect(CGRect(x: right - w * 0.06 - windowSize, y: windowY, width: windowSize, height: windowSize))
            context.stroke(windows, with: .color(strokeColor), lineWidth: 0.6)

            // Deck/platform at bottom (relevant to OPS — trades work)
            var deck = Path()
            deck.move(to: CGPoint(x: right, y: bottom))
            deck.addLine(to: CGPoint(x: right + w * 0.15, y: bottom))
            deck.addLine(to: CGPoint(x: right + w * 0.15, y: bottom - h * 0.08))
            deck.addLine(to: CGPoint(x: right, y: bottom - h * 0.08))
            // Horizontal rails
            deck.move(to: CGPoint(x: right, y: bottom - h * 0.04))
            deck.addLine(to: CGPoint(x: right + w * 0.15, y: bottom - h * 0.04))
            context.stroke(deck, with: .color(strokeColor), lineWidth: 0.6)
        }
    }

    // MARK: - Stamp

    private func stampView(text: String, color: Color, rotation: Double) -> some View {
        Text(text)
            .font(.headingBold)
            .foregroundStyle(color)
            .tracking(3)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(color, lineWidth: 2)
            )
            .rotationEffect(.degrees(rotation))
    }

    // MARK: - Commit

    private func commitSwipe() {
        committed = true
        let direction = isSwipingRight ? "right" : "left"
        let flyX: CGFloat = isSwipingRight ? 500 : -500

        if isSwipingRight {
            TutorialHaptics.commit()
        } else {
            TutorialHaptics.arrival()
        }

        withAnimation(.easeIn(duration: 0.2)) {
            dragOffset = CGSize(width: flyX, height: dragOffset.height)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            onSwiped(direction)
        }
    }
}
