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
    var lineColor: Color {
        switch self {
        case .success: return OPSStyle.Colors.oliveLineM
        case .warning: return OPSStyle.Colors.tanLineM
        case .error:   return OPSStyle.Colors.roseLineM
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

// MARK: - Toast value

struct Toast: Identifiable, Equatable {
    let id: UUID
    let label: String
    let tone: ToastTone
    let autoDismissAfter: TimeInterval
    /// Optional trailing tap-through. `nil` → plain dismiss-on-tap toast.
    let action: ToastAction?

    init(
        id: UUID = UUID(),
        label: String,
        tone: ToastTone,
        autoDismissAfter: TimeInterval = 3.0,
        action: ToastAction? = nil
    ) {
        self.id = id
        self.label = label
        self.tone = tone
        self.autoDismissAfter = autoDismissAfter
        self.action = action
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

    /// Pending toasts behind `current`, FIFO. Readable for tests.
    private(set) var queue: [Toast] = []

    /// Max queued toasts (excludes the visible one). Overflow drops the oldest
    /// auto-dismissing entry; manual-dismiss (error) toasts are never dropped.
    private let maxQueue = 3

    /// When a backlog exists, auto-dismiss toasts compress to this interval so a
    /// burst drains quickly instead of holding the screen for the full 3s each.
    private let compressedInterval: TimeInterval = 1.2

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Enqueue a toast. Identical consecutive labels are coalesced (a burst of
    /// the same event reads as one). If nothing is showing it appears
    /// immediately; otherwise it queues behind the current toast. Pass a toast
    /// with `autoDismissAfter: 0` for manual-only dismiss (errors with an action).
    func present(_ toast: Toast) {
        if current?.label == toast.label { return }
        if queue.last?.label == toast.label { return }
        guard current != nil else { show(toast); return }
        queue.append(toast)
        trimQueue()
    }

    /// Dismiss the visible toast and advance to the next queued one. Called by
    /// tap and by the auto-dismiss timer.
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        if queue.isEmpty { current = nil }
        else { show(queue.removeFirst()) }
    }

    /// Test/teardown hook — clears all state.
    func reset() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        queue.removeAll()
    }

    private func show(_ toast: Toast) {
        current = toast
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

/// Internal layer that renders the active toast. Mounted via `.toastHost()`.
struct ToastHostView: View {
    @ObservedObject private var center = ToastCenter.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            VStack {
                if let toast = center.current {
                    ToastBanner(toast: toast, reduceMotion: reduceMotion) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        center.dismiss()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, geometry.safeAreaInsets.top + 8)
                    .transition(transition)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .ignoresSafeArea(edges: .top)
            // Single OPS easing curve cubic-bezier(0.22, 1, 0.36, 1) on every
            // path: enter = .standard (250ms), exit = .panel (200ms),
            // reduced-motion crossfade = .hover (150ms). Durations are
            // unchanged; only the curve is corrected — .fast/.faster are legacy
            // easeInOut/easeOut aliases that violated the single-curve rule.
            // (review W-9)
            .animation(
                reduceMotion
                    ? OPSStyle.Animation.hover
                    : (center.current == nil
                        ? OPSStyle.Animation.panel
                        : OPSStyle.Animation.standard),
                value: center.current?.id
            )
        }
        .allowsHitTesting(center.current != nil)
    }

    private var transition: AnyTransition {
        reduceMotion
            ? .opacity
            : .move(edge: .top).combined(with: .opacity)
    }
}

// MARK: - Banner pill

private struct ToastBanner: View {
    let toast: Toast
    let reduceMotion: Bool
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            messageRow
            if let action = toast.action {
                actionDivider
                actionButton(action)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .glassDense()
        .overlay(
            // Tone hairline tint over the glass border — subtle, not loud.
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.modalRadius,
                style: .continuous
            )
            .strokeBorder(toast.tone.lineColor, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onAppear {
            UINotificationFeedbackGenerator().notificationOccurred(toast.tone.hapticType)
        }
    }

    /// Icon + `//` label — the confirmation message. The banner-wide tap
    /// gesture dismisses; this stays one combined VoiceOver element.
    private var messageRow: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.tone.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(toast.tone.textColor)
                .frame(width: 16, height: 16)

            labelText
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(accessibilityLabel)
        }
        .padding(.leading, 20)
        .padding(.trailing, toast.action == nil ? 20 : 12)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Tap to dismiss")
    }

    /// 1pt tone hairline separating the message from the tap-through action.
    private var actionDivider: some View {
        Rectangle()
            .fill(toast.tone.lineColor)
            .frame(width: 1)
            .padding(.vertical, 8)
            .accessibilityHidden(true)
    }

    /// Trailing tap-through. Fires the action handler, then dismisses the
    /// toast through the same path as a body tap.
    private func actionButton(_ action: ToastAction) -> some View {
        Button {
            action.handler()
            onTap()
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
            .padding(.leading, 16)
            .padding(.trailing, 20)
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
        HStack(spacing: 4) {
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
    /// Mounts the toast layer above this view. Apply once at a root container
    /// (MainTabView) so toasts persist across tab swaps.
    func toastHost() -> some View {
        overlay(ToastHostView())
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Toast tones") {
    struct PreviewHost: View {
        var body: some View {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 16) {
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
