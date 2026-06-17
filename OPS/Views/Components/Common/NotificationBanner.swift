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

        var iconColor: Color {
            switch self {
            case .success:
                return OPSStyle.Colors.successStatus
            case .error:
                return OPSStyle.Colors.errorStatus
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
            // Status bar spacer
            Color.clear
                .frame(height: 50) // Status bar height

            // Banner content
            HStack(spacing: 10) {
                Image(systemName: type.iconName)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(type.iconColor)

                Text(message)
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
        .glassDense(cornerRadius: 0)
        .transition(.asymmetric(
            insertion: .move(edge: .top),
            removal: .move(edge: .top)
        ))
        .onAppear {
            // Auto-dismiss after 2 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation(OPSStyle.Animation.standard) {
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
                .animation(OPSStyle.Animation.standard, value: isPresented)
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