//
//  GracePeriodBanner.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Non-dismissible banner shown at top of app during grace period

import SwiftUI

struct GracePeriodBanner: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var dataController: DataController
    @State private var showPlanSelection = false
    
    private var bannerHeight: CGFloat = 44
    
    var body: some View {
        if subscriptionManager.shouldShowGracePeriodBanner {
            VStack(spacing: 0) {
                // Banner content
                HStack(spacing: 12) {
                    // Warning icon - smaller, more subtle
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.black.opacity(0.9))
                    
                    // Message - uppercase tactical style
                    Text(bannerMessage.uppercased())
                        .font(OPSStyle.Typography.captionBold)  // Bold tactical font
                        .foregroundColor(.black)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    // Action button (only for admins)
                    if subscriptionManager.isUserAdmin {
                        Button(action: {
                            showPlanSelection = true
                        }) {
                            Text(actionButtonText.uppercased())
                                .font(OPSStyle.Typography.smallCaption)  // Smaller tactical font
                                .foregroundColor(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 2)
                                        .stroke(OPSStyle.Colors.darkBorder, lineWidth: 1)
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: bannerHeight)
                .frame(maxWidth: .infinity)
                .background(bannerBackgroundColor.opacity(0.9))  // Slightly transparent
                
                // Separator - thinner line
                Rectangle()
                    .fill(OPSStyle.Colors.darkBorder)
                    .frame(height: 1)
            }
            .sheet(isPresented: $showPlanSelection) {
                PlanSelectionView()
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeInOut(duration: 0.3), value: subscriptionManager.shouldShowGracePeriodBanner)
        }
    }
    
    private var bannerMessage: String {
        if let days = subscriptionManager.graceDaysRemaining {
            if days == 1 {
                return "Expires Tomorrow"
            } else if days == 0 {
                return "Expires Today"
            } else {
                return "\(days) Days Remaining"
            }
        }
        return "Action Required"
    }
    
    private var actionButtonText: String {
        switch subscriptionManager.subscriptionStatus {
        case .grace:
            // Check if it's payment-related or seat-related
            if let company = dataController.getCurrentUserCompany(),
               company.seatGraceStartDate != nil {
                return "Manage"
            } else {
                return "Payment"
            }
        default:
            return "Fix"
        }
    }
    
    private var bannerBackgroundColor: Color {
        // Use warning color for grace period
        return OPSStyle.Colors.warningStatus
    }
}

// MARK: - View Modifier for Easy Integration

struct GracePeriodBannerModifier: ViewModifier {
    @StateObject private var subscriptionManager = SubscriptionManager.shared
    @EnvironmentObject private var dataController: DataController
    
    func body(content: Content) -> some View {
        ZStack(alignment: .top) {
            content
                .offset(y: subscriptionManager.shouldShowGracePeriodBanner ? 44 : 0)
                .animation(.easeInOut(duration: 0.3), value: subscriptionManager.shouldShowGracePeriodBanner)
            
            GracePeriodBanner()
                .environmentObject(subscriptionManager)
                .environmentObject(dataController)
        }
    }
}

extension View {
    /// Adds grace period banner overlay to any view
    func gracePeriodBanner() -> some View {
        modifier(GracePeriodBannerModifier())
    }
}

// MARK: - Preview

struct GracePeriodBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            // Sample content
            NavigationView {
                List {
                    Text("Sample Content")
                    Text("More Content")
                }
                .navigationTitle("Home")
            }
        }
        .gracePeriodBanner()
        .environmentObject({
            let manager = SubscriptionManager.shared
            manager.shouldShowGracePeriodBanner = true
            manager.graceDaysRemaining = 3
            manager.isUserAdmin = true
            return manager
        }())
        .preferredColorScheme(.dark)
    }
}