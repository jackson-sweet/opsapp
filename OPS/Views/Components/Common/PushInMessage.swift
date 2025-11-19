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
                    // Banner content
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
                                        .fill(Color.white.opacity(0.05))
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
                        .foregroundColor(Color.white.opacity(0.1)),
                    alignment: .bottom
                )
                .shadow(color: Color.black, radius: 10, x: 0, y: 4)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    // Auto-dismiss after specified duration
                    if autoDismissAfter > 0 {
                        autoDismissTimer = Timer.scheduledTimer(withTimeInterval: autoDismissAfter, repeats: false) { _ in
                            dismissMessage()
                        }
                    }
                }
                .onDisappear {
                    autoDismissTimer?.invalidate()
                }
            }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isPresented)
        }
        .edgesIgnoringSafeArea(.top)
    }

    private func dismissMessage() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            isPresented = false
        }
        autoDismissTimer?.invalidate()
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
