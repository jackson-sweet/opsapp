//
//  CustomAlert.swift
//  OPS
//
//  Custom alert component with styled appearance and overlay
//

import SwiftUI

struct CustomAlertConfig: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String?
    let color: Color
    let duration: TimeInterval

    init(title: String, message: String? = nil, color: Color = OPSStyle.Colors.primaryAccent, duration: TimeInterval = 2.0) {
        self.title = title
        self.message = message
        self.color = color
        self.duration = duration
    }

    static func == (lhs: CustomAlertConfig, rhs: CustomAlertConfig) -> Bool {
        lhs.id == rhs.id
    }
}

struct CustomAlertModifier: ViewModifier {
    @Binding var alert: CustomAlertConfig?
    @State private var isVisible = false

    func body(content: Content) -> some View {
        ZStack {
            content

            if alert != nil {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity)

                if let config = alert, isVisible {
                    VStack(spacing: 16) {
                        Text(config.title)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(config.color)
                            .multilineTextAlignment(.center)

                        if let message = config.message {
                            Text(message)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.95))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(config.color, lineWidth: 2)
                            )
                    )
                    .padding(.horizontal, 40)
                    .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: alert?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isVisible)
        .onChange(of: alert) { _, newValue in
            if let config = newValue {
                isVisible = true
                DispatchQueue.main.asyncAfter(deadline: .now() + config.duration) {
                    withAnimation {
                        isVisible = false
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        alert = nil
                    }
                }
            } else {
                isVisible = false
            }
        }
    }
}

extension View {
    func customAlert(_ alert: Binding<CustomAlertConfig?>) -> some View {
        modifier(CustomAlertModifier(alert: alert))
    }
}
