//
//  NotificationBanner.swift
//  OPS
//
//  A minimal notification banner that slides down from the top
//

import SwiftUI

struct NotificationBanner: View {
    let message: String
    let type: BannerType
    @Binding var isPresented: Bool
    
    enum BannerType {
        case success
        case error
        case info
        
        var backgroundColor: Color {
            switch self {
            case .success:
                return OPSStyle.Colors.cardBackgroundDark
            case .error:
                return OPSStyle.Colors.cardBackgroundDark
            case .info:
                return OPSStyle.Colors.cardBackgroundDark
            }
        }
        
        var iconColor: Color {
            switch self {
            case .success:
                return Color.green
            case .error:
                return Color.red
            case .info:
                return OPSStyle.Colors.primaryAccent
            }
        }
        
        var iconName: String {
            switch self {
            case .success:
                return "checkmark.circle.fill"
            case .error:
                return "xmark.circle.fill"
            case .info:
                return "info.circle.fill"
            }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Status bar background
            Color.clear
                .frame(height: 50) // Status bar height
                .background(
                    BlurView(style: .systemUltraThinMaterialDark)
                        .overlay(type.backgroundColor.opacity(0.85))
                )
            
            // Banner content
            HStack(spacing: 10) {
                Image(systemName: type.iconName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(type.iconColor)
                
                Text(message)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                BlurView(style: .systemUltraThinMaterialDark)
                    .overlay(type.backgroundColor.opacity(0.85))
            )
        }
        .shadow(color: OPSStyle.Colors.shadowColor, radius: 10, x: 0, y: 5)
        .transition(.asymmetric(
            insertion: .move(edge: .top),
            removal: .move(edge: .top)
        ))
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(.easeInOut(duration: 0.3)) {
                    isPresented = false
                }
            }
        }
    }
}

// View modifier for easy application
struct NotificationBannerModifier: ViewModifier {
    @Binding var isPresented: Bool
    let message: String
    let type: NotificationBanner.BannerType
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
            
            if isPresented {
                NotificationBanner(
                    message: message,
                    type: type,
                    isPresented: $isPresented
                )
                .ignoresSafeArea()
                .zIndex(999)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isPresented)
            }
        }
    }
}

extension View {
    func notificationBanner(
        isPresented: Binding<Bool>,
        message: String,
        type: NotificationBanner.BannerType = .info
    ) -> some View {
        modifier(NotificationBannerModifier(
            isPresented: isPresented,
            message: message,
            type: type
        ))
    }
}