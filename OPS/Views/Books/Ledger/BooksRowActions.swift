//
//  BooksRowActions.swift
//  OPS
//
//  Money & Leads redesign — swipe actions for the flat ledger rows.
//  Implements the MOBILE.md §7.2 swipe spec on rows that live in a plain
//  LazyVStack (SwiftUI's `.swipeActions` is List-only): an 80pt action strip
//  per side (max 2), revealed by a horizontal drag that follows the finger and
//  snaps open past 50% of the strip width. A full right-swipe (>75% of the row)
//  commits the primary leading action — enabled only for non-destructive
//  actions; destructive ones (VOID / DELETE) always require the deliberate tap,
//  and their handlers confirm before mutating.
//
//  One row open at a time: the ledger owns `openRowID`; opening a row closes
//  the previous one, and a tap on an open row closes it instead of navigating.
//

import SwiftUI

// MARK: - Action model

struct OPSRowAction: Identifiable {
    let id: String
    /// Strip label — uppercase, single word (PAYMENT / VOID / SEND / …).
    let label: String
    /// Long-press menu title — the fuller native-menu phrasing
    /// ("Record Payment", "Void Invoice").
    let menuTitle: String
    /// SF Symbol (outline variant — icons are metadata, monochrome).
    let icon: String
    /// Earth-tone semantic: olive = positive, rose = destructive.
    let tone: Color
    /// Destructive actions get the menu's destructive role (and never full-swipe).
    var isDestructive: Bool = false
    let handler: () -> Void
}

// MARK: - Swipeable row wrapper

struct OPSSwipeRow<Content: View>: View {
    let rowID: String
    var leading: [OPSRowAction] = []
    var trailing: [OPSRowAction] = []
    /// Full right-swipe (>75% of row width) fires `leading.first`. Only set
    /// for non-destructive primaries (record payment / send / convert).
    var allowsFullSwipe: Bool = false
    @Binding var openRowID: String?
    @ViewBuilder var content: () -> Content

    /// Preview/snapshot support — starts the row with a side revealed.
    var initialReveal: Reveal? = nil

    @State private var dragOffset: CGFloat = 0
    @State private var isOpen = false
    @State private var rowWidth: CGFloat = 0
    @State private var fullSwipeArmed = false
    /// Anchor captured on the first movement of each drag — the settled offset
    /// the translation applies against. Recomputing it per-change would make
    /// the anchor jump the moment a drag crosses zero.
    @State private var dragBase: CGFloat?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var actionWidth: CGFloat { 80 }   // MOBILE.md §7.2 — 80pt per action
    private var leadingWidth: CGFloat { CGFloat(min(leading.count, 2)) * actionWidth }
    private var trailingWidth: CGFloat { CGFloat(min(trailing.count, 2)) * actionWidth }

    /// One authorized curve, 150ms — "swipe action reveal" (MOBILE.md §11).
    /// Reduced motion keeps the interaction (it's direct manipulation) but
    /// snaps with a plain short ease instead of the branded curve.
    private var snap: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .timingCurve(OPSStyle.Animation.easeSmoothP1x, OPSStyle.Animation.easeSmoothP1y,
                           OPSStyle.Animation.easeSmoothP2x, OPSStyle.Animation.easeSmoothP2y,
                           duration: 0.15)
    }

    init(
        rowID: String,
        leading: [OPSRowAction] = [],
        trailing: [OPSRowAction] = [],
        allowsFullSwipe: Bool = false,
        openRowID: Binding<String?>,
        initialReveal: Reveal? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.rowID = rowID
        self.leading = Array(leading.prefix(2))
        self.trailing = Array(trailing.prefix(2))
        self.allowsFullSwipe = allowsFullSwipe
        self._openRowID = openRowID
        self.initialReveal = initialReveal
        self.content = content
        // Snapshot/preview support — render the strip revealed at frame 0.
        switch initialReveal {
        case .leading:
            _dragOffset = State(initialValue: CGFloat(min(leading.count, 2)) * 80)
            _isOpen = State(initialValue: true)
        case .trailing:
            _dragOffset = State(initialValue: -CGFloat(min(trailing.count, 2)) * 80)
            _isOpen = State(initialValue: true)
        default:
            break
        }
    }

    var body: some View {
        ZStack {
            // Action strips sit under the row; the row content carries an
            // opaque canvas fill so the strip is hidden until revealed.
            if dragOffset > 0 {
                strip(actions: leading, edge: .leading, revealed: dragOffset)
            } else if dragOffset < 0 {
                strip(actions: trailing, edge: .trailing, revealed: -dragOffset)
            }

            content()
                .background(OPSStyle.Colors.background)
                .overlay {
                    // Tap on an open row closes it instead of navigating.
                    if isOpen {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture { setOpen(nil) }
                    }
                }
                .offset(x: dragOffset)
                // Long-press menu mirrors the swipe strip — the discoverable
                // second path to the same actions (old embed parity).
                .modifier(RowContextMenu(actions: leading + trailing))
        }
        .clipped()
        .background(
            GeometryReader { geo in
                Color.clear.onAppear { rowWidth = geo.size.width }
            }
        )
        .directionalDrag(
            isEnabled: !leading.isEmpty || !trailing.isEmpty,
            onChanged: { translation in handleDrag(translation) },
            onEnded: { translation in settle(translation) }
        )
        .onChange(of: openRowID) { _, newValue in
            // Another row opened (or the ledger reset) — close this one.
            if newValue != rowID && isOpen {
                withAnimation(snap) { dragOffset = 0 }
                isOpen = false
            }
        }
        .modifier(RowAccessibilityActions(actions: leading + trailing))
    }

    // MARK: Strip

    @ViewBuilder
    private func strip(actions: [OPSRowAction], edge: HorizontalEdge, revealed: CGFloat) -> some View {
        let isLeading = edge == .leading
        HStack(spacing: 0) {
            if !isLeading { Spacer(minLength: 0) }
            HStack(spacing: 0) {
                ForEach(actions) { action in
                    stripButton(action, stretched: isLeading && fullSwipeArmed && action.id == actions.first?.id)
                }
            }
            // Content slides in from the edge as a fixed-width unit —
            // the container clips it until enough of the strip is revealed.
            .frame(width: max(stripWidth(for: actions), revealed), alignment: isLeading ? .leading : .trailing)
            if isLeading { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func stripWidth(for actions: [OPSRowAction]) -> CGFloat {
        CGFloat(actions.count) * actionWidth
    }

    private func stripButton(_ action: OPSRowAction, stretched: Bool) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            setOpen(nil)
            action.handler()
        } label: {
            VStack(spacing: 4) {   // icon over label, 4pt gap (MOBILE.md §7.2)
                Image(systemName: action.icon)
                    .font(.system(size: 20, weight: .regular))
                Text(action.label)
                    .font(.custom("JetBrainsMono-Medium", size: 9))
                    .tracking(0.9)
                    .textCase(.uppercase)
            }
            .foregroundColor(action.tone)
            .frame(width: stretched ? nil : actionWidth)
            .frame(maxWidth: stretched ? .infinity : actionWidth, maxHeight: .infinity)
            .background(action.tone.opacity(0.15))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action.label.capitalized)
    }

    // MARK: Drag mechanics

    private func handleDrag(_ translation: CGFloat) {
        if dragBase == nil {
            dragBase = isOpen ? (dragOffset > 0 ? leadingWidth : -trailingWidth) : 0
        }
        var next = (dragBase ?? 0) + translation

        // Clamp toward sides with no actions.
        if leading.isEmpty { next = min(next, 0) }
        if trailing.isEmpty { next = max(next, 0) }

        // Past the strip: rubber-band — unless this is the full-swipe side,
        // which keeps 1:1 travel so the commit gesture feels unbroken.
        if next > leadingWidth {
            if !(allowsFullSwipe && !leading.isEmpty) {
                next = leadingWidth + (next - leadingWidth) * 0.25
            }
        } else if next < -trailingWidth {
            next = -trailingWidth - (-next - trailingWidth) * 0.25
        }

        // Arm/disarm the full-swipe commit with a light tick at the threshold.
        if allowsFullSwipe, !leading.isEmpty, rowWidth > 0 {
            let armed = next > rowWidth * 0.75
            if armed != fullSwipeArmed {
                fullSwipeArmed = armed
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }

        dragOffset = next
    }

    private func settle(_ translation: CGFloat) {
        defer {
            fullSwipeArmed = false
            dragBase = nil
        }

        // Full swipe — commit the primary leading action and close.
        if allowsFullSwipe, let primary = leading.first, rowWidth > 0, dragOffset > rowWidth * 0.75 {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            withAnimation(snap) { dragOffset = 0 }
            isOpen = false
            if openRowID == rowID { openRowID = nil }
            primary.handler()
            return
        }

        // Snap open past 50% of the strip width; otherwise snap closed.
        if !leading.isEmpty, dragOffset > leadingWidth * 0.5 {
            open(to: leadingWidth)
        } else if !trailing.isEmpty, dragOffset < -trailingWidth * 0.5 {
            open(to: -trailingWidth)
        } else {
            withAnimation(snap) { dragOffset = 0 }
            if isOpen {
                isOpen = false
                if openRowID == rowID { openRowID = nil }
            }
        }
    }

    private func open(to offset: CGFloat) {
        let wasClosed = !isOpen
        withAnimation(snap) { dragOffset = offset }
        isOpen = true
        openRowID = rowID
        if wasClosed {
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func setOpen(_ id: String?) {
        withAnimation(snap) { dragOffset = 0 }
        isOpen = false
        if openRowID == rowID { openRowID = id }
    }
}

// MARK: - Long-press menu

/// Attaches the row's context menu only when it actually has actions —
/// action-less rows (paid / won / locked) keep a plain long-press.
private struct RowContextMenu: ViewModifier {
    let actions: [OPSRowAction]

    func body(content: Content) -> some View {
        if actions.isEmpty {
            content
        } else {
            content.contextMenu {
                ForEach(actions) { action in
                    Button(role: action.isDestructive ? .destructive : nil) {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        action.handler()
                    } label: {
                        Label(action.menuTitle, systemImage: action.icon)
                    }
                }
            }
        }
    }
}

// MARK: - VoiceOver parity

/// Swipe strips aren't reachable by VoiceOver — expose every action as a
/// rotor action on the row itself.
private struct RowAccessibilityActions: ViewModifier {
    let actions: [OPSRowAction]

    func body(content: Content) -> some View {
        actions.reduce(AnyView(content)) { view, action in
            AnyView(view.accessibilityAction(named: Text(action.label.capitalized)) {
                action.handler()
            })
        }
    }
}

// MARK: - Reveal side (preview support)

extension OPSSwipeRow {
    enum Reveal { case leading, trailing }
}

// Existing ledger call sites keep source compatibility while new product
// surfaces consume the platform-neutral names above.
typealias BooksRowAction = OPSRowAction
typealias BooksSwipeRow<Content: View> = OPSSwipeRow<Content>
