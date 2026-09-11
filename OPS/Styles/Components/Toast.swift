//
//  Toast.swift
//  OPS
//
//  Transient confirmation banner — the silent "yes, that landed" surface for
//  sheet-action success/error moments. Subscribes via `ToastCenter.shared`
//  and renders a single glass-dense pill below the safe-area inset.
//
//  Voice + visual contract (single source: design-intent §9 / DESIGN.md §2):
//    • JetBrains Mono 11pt semibold, 1.6 kerning, uppercase
//    • `//` prefix in textMute, label in tone-text colour
//    • Tones: success → olive, warning → tan, error → rose. No accent.
//    • Surface: `.glassDense()` modifier (L1 dense, 12pt radius)
//    • Enter: slide-in from top + opacity, OPSStyle.Animation.standard (250ms)
//    • Exit:  slide-out + opacity, OPSStyle.Animation.fast (200ms)
//    • Reduced motion: opacity-only crossfade
//    • Haptic on present: notificationOccurred matching the tone
//      (opt out with `haptics: false` — unsolicited toasts only)
//    • Tap to dismiss → light impact haptic
//    • Auto-dismiss default: 3.0s
//    • Optional action: a trailing tap-through affordance (label + handler).
//      Action-bearing toasts pass a longer autoDismissAfter (~6s).
//
//  Mount the host with `.toastHost()` on a root container (MainTabView).
//  Anywhere in the app: `ToastCenter.shared.present(.init(label: "// SAVED", tone: .success))`.
//

import SwiftUI
import UIKit

// MARK: - Tone

enum ToastTone {
    case success
    case warning
    case error

    /// Tone-foreground colour for the label (mobile-uplift `*TextM` token).
    var textColor: Color {
        switch self {
        case .success: return OPSStyle.Colors.oliveTextM
        case .warning: return OPSStyle.Colors.tanTextM
        case .error:   return OPSStyle.Colors.roseTextM
        }
    }

    /// Hairline overlay colour that tints the toast border to the tone.
    ///
    /// Carries `ToastM.border`, not the `*LineM` status-tag family it used to
    /// borrow — see `OPSStyle.Colors.ToastM` for why a banner and a chip do
    /// not want the same edge.
    var lineColor: Color {
        switch self {
        case .success: return OPSStyle.Colors.olive.opacity(OPSStyle.Colors.ToastM.border)
        case .warning: return OPSStyle.Colors.tan.opacity(OPSStyle.Colors.ToastM.border)
        case .error:   return OPSStyle.Colors.rose.opacity(OPSStyle.Colors.ToastM.border)
        }
    }

    /// SF Symbol leading the label. Tone-coloured.
    var iconName: String {
        switch self {
        case .success: return "checkmark"
        case .warning: return "exclamationmark"
        case .error:   return "xmark"
        }
    }

    /// Notification haptic that fires when the toast appears.
    var hapticType: UINotificationFeedbackGenerator.FeedbackType {
        switch self {
        case .success: return .success
        case .warning: return .warning
        case .error:   return .error
        }
    }
}

// MARK: - Toast action

/// Optional tap-through affordance on a toast. The banner renders `label`
/// as a trailing button; tapping it runs `handler`, then dismisses the toast.
struct ToastAction {
    let label: String
    let accessibilityLabel: String?
    let handler: () -> Void

    init(
        label: String,
        accessibilityLabel: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.label = label
        self.accessibilityLabel = accessibilityLabel
        self.handler = handler
    }
}

enum ToastTapTarget: Equatable {
    case message
    case action
}

// MARK: - Toast value

struct Toast: Identifiable, Equatable {
    let id: UUID
    let label: String
    let tone: ToastTone
    let autoDismissAfter: TimeInterval
    /// Optional trailing tap-through. `nil` → plain dismiss-on-tap toast.
    let action: ToastAction?
    /// Opt-in for confirmations whose entire pill opens the created entity.
    /// Other message taps keep their existing dismiss-only behavior.
    let bodyTapInvokesAction: Bool
    /// Defaults to the label. Entity-specific actions can retain distinct
    /// destinations even when two confirmations have identical visible copy.
    let coalescingKey: String
    /// Whether presenting this toast fires its tone haptic. Default `true` —
    /// a toast normally confirms something the operator just did, and the
    /// haptic is the confirmation.
    ///
    /// Set `false` for an *unsolicited* toast the operator did not ask for.
    /// The screenshot bug-report offer is the case: iOS has already flashed
    /// the screen and played the shutter, so a buzz on top of that reads as
    /// the app reacting to being watched rather than confirming an action.
    let haptics: Bool
    /// A visible reconnect toast already communicates sync state and links to
    /// Pending Work, so the compact sync indicator yields for its real on-screen
    /// lifetime. Queued toasts do not suppress anything until they become current.
    let suppressesSyncStatusIndicator: Bool

    init(
        id: UUID = UUID(),
        label: String,
        tone: ToastTone,
        autoDismissAfter: TimeInterval = 3.0,
        action: ToastAction? = nil,
        bodyTapInvokesAction: Bool = false,
        coalescingKey: String? = nil,
        haptics: Bool = true,
        suppressesSyncStatusIndicator: Bool = false
    ) {
        self.id = id
        self.label = label
        self.tone = tone
        self.autoDismissAfter = autoDismissAfter
        self.action = action
        self.bodyTapInvokesAction = bodyTapInvokesAction
        self.coalescingKey = coalescingKey ?? label
        self.haptics = haptics
        self.suppressesSyncStatusIndicator = suppressesSyncStatusIndicator
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

// MARK: - ToastCenter

/// Globally-shared singleton that the toast host observes. Call
/// `ToastCenter.shared.present(...)` from anywhere — the active host renders.
@MainActor
final class ToastCenter: ObservableObject {
    static let shared = ToastCenter()

    @Published private(set) var current: Toast?
    @Published private(set) var isSuppressingSyncStatusIndicator = false

    /// Pending toasts behind `current`, FIFO. Readable for tests.
    private(set) var queue: [Toast] = []

    /// Max queued toasts (excludes the visible one). Overflow drops the oldest
    /// auto-dismissing entry; manual-dismiss (error) toasts are never dropped.
    private let maxQueue = 3

    /// When a backlog exists, auto-dismiss toasts compress to this interval so a
    /// burst drains quickly instead of holding the screen for the full 3s each.
    private let compressedInterval: TimeInterval = 1.2

    private var dismissTask: Task<Void, Never>?
    /// Only `reset()` invalidates transition callbacks. Each suppressing banner
    /// owns a distinct removal token so overlapping exits cannot release one
    /// another's indicator latch.
    private var suppressionResetGeneration = 0
    private var activeSuppressingRemovalTokens: Set<UUID> = []

    private init() {}

    /// Enqueue a toast. Identical consecutive labels are coalesced (a burst of
    /// the same event reads as one). If nothing is showing it appears
    /// immediately; otherwise it queues behind the current toast. Pass a toast
    /// with `autoDismissAfter: 0` for manual-only dismiss (errors with an action).
    func present(_ toast: Toast) {
        // Ensure the dedicated toast window exists before we show anything — this
        // is what lets a toast fired from inside a sheet appear ABOVE the sheet.
        ToastWindowController.shared.install()
        if current?.coalescingKey == toast.coalescingKey { return }
        if queue.last?.coalescingKey == toast.coalescingKey { return }
        guard current != nil else {
            withAnimation(presentationAnimation) {
                show(toast)
            }
            return
        }
        queue.append(toast)
        trimQueue()
    }

    /// Resolve taps against the visible identity. A trailing button and its
    /// parent gesture can never run one action twice or dismiss the next toast.
    func handleTap(toastID: UUID, target: ToastTapTarget) {
        guard let toast = current, toast.id == toastID else { return }
        if target == .action || toast.bodyTapInvokesAction {
            toast.action?.handler()
        }
        guard current?.id == toastID else { return }
        dismiss()
    }

    /// Dismiss the visible toast and advance to the next queued one. Called by
    /// tap and by the auto-dismiss timer.
    func dismiss() {
        guard let outgoing = current else { return }
        dismissTask?.cancel()
        dismissTask = nil

        let incoming = queue.isEmpty ? nil : queue.removeFirst()
        let resetGeneration = suppressionResetGeneration
        let removalToken = outgoing.suppressesSyncStatusIndicator ? UUID() : nil
        if let removalToken {
            activeSuppressingRemovalTokens.insert(removalToken)
            refreshSuppression()
        }

        withAnimation(
            dismissalAnimation(hasReplacement: incoming != nil),
            completionCriteria: .removed
        ) {
            if let incoming {
                show(incoming)
            } else {
                current = nil
                refreshSuppression()
            }
        } completion: { [weak self] in
            guard let self,
                  self.suppressionResetGeneration == resetGeneration else { return }
            if let removalToken {
                self.activeSuppressingRemovalTokens.remove(removalToken)
            }
            self.refreshSuppression()
        }
    }

    /// Test/teardown hook — clears all state.
    func reset() {
        dismissTask?.cancel()
        dismissTask = nil
        suppressionResetGeneration += 1
        activeSuppressingRemovalTokens.removeAll()
        current = nil
        queue.removeAll()
        refreshSuppression()
    }

    private var presentationAnimation: Animation {
        OPSStyle.Animation.reduceMotion
            ? OPSStyle.Animation.hover
            : OPSStyle.Animation.standard
    }

    private func dismissalAnimation(hasReplacement: Bool) -> Animation {
        if OPSStyle.Animation.reduceMotion {
            return OPSStyle.Animation.hover
        }
        return hasReplacement ? OPSStyle.Animation.standard : OPSStyle.Animation.panel
    }

    private func show(_ toast: Toast) {
        current = toast
        refreshSuppression()
        let base = toast.autoDismissAfter
        guard base > 0 else { return } // manual-dismiss (error + action)
        let interval = queue.isEmpty ? base : compressedInterval
        let id = toast.id
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.current?.id == id else { return }
                self.dismiss()
            }
        }
    }

    private func refreshSuppression() {
        isSuppressingSyncStatusIndicator =
            current?.suppressesSyncStatusIndicator == true ||
            !activeSuppressingRemovalTokens.isEmpty
    }

    private func trimQueue() {
        while queue.count > maxQueue {
            if let idx = queue.firstIndex(where: { $0.autoDismissAfter > 0 }) {
                queue.remove(at: idx)
            } else {
                queue.removeFirst()
            }
        }
    }
}

// MARK: - Host view (overlay layer)

enum ToastBannerOwnership {
    static func isInteractive(phase: TransitionPhase) -> Bool {
        phase != .didDisappear
    }
}

struct ToastBannerTransition: Transition {
    let reduceMotion: Bool

    @ViewBuilder
    func body(content: Content, phase: TransitionPhase) -> some View {
        if reduceMotion {
            OpacityTransition()
                .apply(content: content, phase: phase)
                .allowsHitTesting(ToastBannerOwnership.isInteractive(phase: phase))
                .accessibilityHidden(!ToastBannerOwnership.isInteractive(phase: phase))
        } else {
            MoveTransition(edge: .top)
                .combined(with: OpacityTransition())
                .apply(content: content, phase: phase)
                .allowsHitTesting(ToastBannerOwnership.isInteractive(phase: phase))
                .accessibilityHidden(!ToastBannerOwnership.isInteractive(phase: phase))
        }
    }
}

/// Internal layer that renders the active toast. Mounted via `.toastHost()`.
struct ToastHostView: View {
    @ObservedObject private var center = ToastCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack {
                if let toast = center.current {
                    ToastBanner(toast: toast, reduceMotion: reduceMotion) { target in
                        guard center.current?.id == toast.id else { return }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        center.handleTap(toastID: toast.id, target: target)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, geometry.safeAreaInsets.top + 8)
                    .id(toast.id)
                    .transition(ToastBannerTransition(reduceMotion: reduceMotion))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            // ToastCenter owns the state transaction so reconnect suppression
            // is released by the same `.removed` completion that retires this
            // banner. Enter = standard, exit = panel, replacement = standard;
            // reduced motion keeps the existing 150ms opacity fallback.
        }
        .allowsHitTesting(center.current != nil)
    }
}

// MARK: - Banner pill

private struct ToastBanner: View {
    let toast: Toast
    let reduceMotion: Bool
    let onTap: (ToastTapTarget) -> Void

    var body: some View {
        HStack(spacing: 0) {
            messageRow
            if let action = toast.action {
                actionDivider
                actionButton(action)
            }
        }
        // Bug (site-visit report) — the pill hugs its content and centers in
        // the host instead of stretching edge-to-edge. Dropping the banner's
        // (and the label's) `maxWidth: .infinity` lets the HStack hug width;
        // `fixedSize(vertical:)` pins the height to the content so the action
        // button's `maxHeight: .infinity` matches the row instead of
        // ballooning the pill. The host VStack (center-aligned) centers it.
        .fixedSize(horizontal: false, vertical: true)
        .frame(minHeight: 44)
        .glassDense()
        .overlay(
            // Tone hairline tint over the glass border — subtle, not loud.
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.modalRadius,
                style: .continuous
            )
            .strokeBorder(toast.tone.lineColor, lineWidth: 1)
        )
        .background(ToastInteractionRegionReader())
        .contentShape(Rectangle())
        .onTapGesture { onTap(.message) }
        .onAppear {
            guard toast.haptics else { return }
            UINotificationFeedbackGenerator().notificationOccurred(toast.tone.hapticType)
        }
    }

    /// Icon + `//` label — the confirmation message. The banner-wide tap
    /// dismisses or invokes an opted-in action; VoiceOver follows that choice.
    private var messageRow: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.tone.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(toast.tone.textColor)
                .frame(width: 16, height: 16)

            labelText
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, toast.action == nil ? 20 : 12)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(toast.bodyTapInvokesAction ? (toast.action?.accessibilityLabel ?? "View") : "Tap to dismiss")
        .accessibilityAction { onTap(.message) }
    }

    /// 1pt tone hairline separating the message from the tap-through action.
    private var actionDivider: some View {
        Rectangle()
            .fill(toast.tone.lineColor)
            .frame(width: 1)
            .padding(.vertical, OPSStyle.Layout.spacing2)
            .accessibilityHidden(true)
    }

    /// Trailing tap-through. Fires the action handler, then dismisses the
    /// toast through the same path as a body tap.
    private func actionButton(_ action: ToastAction) -> some View {
        Button {
            onTap(.action)
        } label: {
            HStack(spacing: 5) {
                Text(action.label)
                    .font(OPSStyle.Typography.metadata)
                    .fontWeight(.semibold)
                    .kerning(1.4)
                    .textCase(.uppercase)
                Image(systemName: "arrow.right")
                    .font(.system(size: 10, weight: .semibold))
            }
            .foregroundColor(OPSStyle.Colors.text)
            .padding(.leading, OPSStyle.Layout.spacing3)
            .padding(.trailing, OPSStyle.Layout.spacing3_5)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(action.accessibilityLabel ?? action.label)
    }

    /// Two-segment label: `//` slashes in textMute, body in tone colour. Both
    /// segments share the JetBrains Mono 11pt semibold + 1.6 kerning treatment.
    @ViewBuilder
    private var labelText: some View {
        let parts = split(toast.label)
        HStack(spacing: OPSStyle.Layout.spacing1) {
            if !parts.prefix.isEmpty {
                Text(parts.prefix)
                    .font(OPSStyle.Typography.metadata)
                    .fontWeight(.semibold)
                    .kerning(1.6)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)
            }
            Text(parts.body)
                .font(OPSStyle.Typography.metadata)
                .fontWeight(.semibold)
                .kerning(1.6)
                .foregroundColor(toast.tone.textColor)
                .textCase(.uppercase)
        }
    }

    /// Strip a leading `//` prefix so we can render it in the muted colour.
    /// Falls back to (empty, label) when the label doesn't start with slashes.
    private func split(_ label: String) -> (prefix: String, body: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("//") else { return ("", trimmed) }
        let afterSlash = trimmed.dropFirst(2).drop(while: { $0 == " " })
        return ("//", String(afterSlash))
    }

    private var accessibilityLabel: String {
        // VoiceOver: read the label without the `//` system prefix.
        toast.label.replacingOccurrences(of: "//", with: "").trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - View extension — `.toastHost()`

extension View {
    /// Installs the toast layer in a dedicated window above everything (see
    /// `ToastWindowController`). Apply once at a root container (MainTabView).
    /// A plain `.overlay` can't clear a presented `.sheet` — UIKit presents the
    /// sheet above the whole root — so toasts fired from inside a form sheet
    /// rendered behind it. The window sits at `.alert` level and fixes that.
    func toastHost() -> some View {
        onAppear { ToastWindowController.shared.install() }
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Toast tones") {
    struct PreviewHost: View {
        var body: some View {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Button("// LEAD CREATED (success)") {
                        ToastCenter.shared.present(
                            Toast(label: "// LEAD CREATED", tone: .success)
                        )
                    }
                    Button("// LEAD LOST (warning)") {
                        ToastCenter.shared.present(
                            Toast(label: "// LEAD LOST", tone: .warning)
                        )
                    }
                    Button("// LEAD DELETED (error)") {
                        ToastCenter.shared.present(
                            Toast(label: "// LEAD DELETED", tone: .error)
                        )
                    }
                    Button("Dismiss") {
                        ToastCenter.shared.dismiss()
                    }
                }
                .foregroundColor(.white)
            }
            .toastHost()
        }
    }
    return PreviewHost()
        .preferredColorScheme(.dark)
}
#endif
