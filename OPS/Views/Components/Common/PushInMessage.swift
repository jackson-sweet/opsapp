//
//  PushInMessage.swift
//  OPS
//
//  Reusable component for messages that push in from top of screen
//  Ensures consistent styling across all push-in notifications
//

import SwiftUI

/// Message type determines icon and color scheme
enum PushInMessageType {
    case success
    case error
    case info
    case warning

    var icon: String {
        switch self {
        case .success: return "checkmark.circle"
        case .error: return "xmark.circle"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .success: return OPSStyle.Colors.successStatus
        case .error: return OPSStyle.Colors.errorStatus
        case .info: return OPSStyle.Colors.primaryAccent
        case .warning: return OPSStyle.Colors.warningStatus
        }
    }
}

/// Reusable push-in message component
struct PushInMessage: View {
    @Binding var isPresented: Bool

    let title: String
    let subtitle: String?
    let type: PushInMessageType
    let autoDismissAfter: TimeInterval
    let showDismissButton: Bool

    @State private var autoDismissTimer: Timer?
    @State private var dragOffset: CGFloat = 0
    @State private var isMinimized: Bool = false
    @State private var progress: Double = 1.0
    @State private var progressTimer: Timer?

    init(
        isPresented: Binding<Bool>,
        title: String,
        subtitle: String? = nil,
        type: PushInMessageType = .info,
        autoDismissAfter: TimeInterval = 3.0,
        showDismissButton: Bool? = nil
    ) {
        self._isPresented = isPresented
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.autoDismissAfter = autoDismissAfter
        // Don't show X button if auto-dismissing (unless explicitly requested)
        self.showDismissButton = showDismissButton ?? (autoDismissAfter <= 0)
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if isPresented {
                    if isMinimized {
                        // Minimized progress bar view
                        minimizedProgressBar(geometry: geometry)
                    } else {
                        // Full banner content
                        fullBannerContent(geometry: geometry)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPresented)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: isMinimized)
        }
        .edgesIgnoringSafeArea(.top)
        .onChange(of: isPresented) { _, newValue in
            // Clean up timers first
            progressTimer?.invalidate()
            progressTimer = nil
            autoDismissTimer?.invalidate()
            autoDismissTimer = nil

            // Always reset state (ensures clean slate for next show)
            // Use withAnimation to ensure state changes animate properly
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isMinimized = false
                dragOffset = 0
            }
            progress = 1.0
        }
    }

    // MARK: - Full Banner

    private func fullBannerContent(geometry: GeometryProxy) -> some View {
        HStack(spacing: 12) {
            // Status icon
            Image(systemName: type.icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(type.color)
                .frame(width: 32, height: 32)

            // Text content
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.custom("Kosugi-Regular", size: 16))
                    .fontWeight(.semibold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.custom("Kosugi-Regular", size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            // Dismiss button
            if showDismissButton {
                Button(action: {
                    dismissMessage()
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(OPSStyle.Colors.cardBackgroundDark)
                        )
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .padding(.top, max(geometry.safeAreaInsets.top + 8, 60))
        .background(
            Rectangle()
                .fill(type == .info ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.background)
                .overlay(
                    Group {
                        // Only show gradient for non-info types
                        if type != .info {
                            Rectangle()
                                .fill(
                                    LinearGradient(
                                        gradient: Gradient(colors: [
                                            type.color.opacity(0.1),
                                            Color.clear
                                        ]),
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                        }
                    }
                )
        )
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(OPSStyle.Colors.cardBorder),
            alignment: .bottom
        )
        .shadow(color: OPSStyle.Colors.shadowColor, radius: 10, x: 0, y: 4)
        .offset(y: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    // Only allow upward drag (negative translation)
                    if value.translation.height < 0 {
                        dragOffset = value.translation.height
                    }
                }
                .onEnded { value in
                    // If dragged up more than 50pt, minimize instead of dismiss
                    if value.translation.height < -50 {
                        minimizeMessage()
                    } else {
                        // Snap back
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            dragOffset = 0
                        }
                    }
                }
        )
        .transition(.move(edge: .top).combined(with: .opacity))
        .onAppear {
            // Reset state
            dragOffset = 0
            isMinimized = false
            progress = 1.0
            // Auto-dismiss after specified duration
            if autoDismissAfter > 0 {
                autoDismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { _ in
                    dismissMessage()
                }
            }
        }
        .onDisappear {
            autoDismissTimer?.invalidate()
            progressTimer?.invalidate()
        }
    }

    // MARK: - Minimized Progress Bar

    private func minimizedProgressBar(geometry: GeometryProxy) -> some View {
        VStack(spacing: 0) {
            // Thin colored progress bar at very top
            GeometryReader { barGeometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(type.color.opacity(0.2))

                    // Progress fill
                    Rectangle()
                        .fill(type.color)
                        .frame(width: barGeometry.size.width * progress)
                }
            }
            .frame(height: 3)
            .padding(.top, geometry.safeAreaInsets.top)
        }
        .background(OPSStyle.Colors.background)
        .onTapGesture {
            // Tap to expand back to full view
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                isMinimized = false
                dragOffset = 0
            }
            // Restart auto-dismiss timer
            restartAutoDismissTimer()
        }
        .transition(.opacity)
    }

    // MARK: - Actions

    private func minimizeMessage() {
        // Cancel current auto-dismiss timer
        autoDismissTimer?.invalidate()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isMinimized = true
            dragOffset = 0
        }

        // Start progress countdown (2 seconds for minimized state)
        let minimizedDuration: TimeInterval = 2.0
        progress = 1.0

        // Update progress every 50ms
        let updateInterval: TimeInterval = 0.05
        let decrementAmount = updateInterval / minimizedDuration

        progressTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { timer in
            progress -= decrementAmount
            if progress <= 0 {
                timer.invalidate()
                dismissMessage()
            }
        }
    }

    private func restartAutoDismissTimer() {
        progressTimer?.invalidate()
        autoDismissTimer?.invalidate()

        if autoDismissAfter > 0 {
            autoDismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { _ in
                dismissMessage()
            }
        }
    }

    private func dismissMessage() {
        progressTimer?.invalidate()
        autoDismissTimer?.invalidate()

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
            isMinimized = false
        }
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.background

        VStack(spacing: 20) {
            Button("Show Success") {
                // Preview button
            }
            Button("Show Error") {
                // Preview button
            }
            Button("Show Info") {
                // Preview button
            }
            Button("Show Warning") {
                // Preview button
            }
        }

        // Example usage
        PushInMessage(
            isPresented: .constant(true),
            title: "Connection Restored",
            subtitle: "5 items syncing",
            type: .success
        )
    }
}
