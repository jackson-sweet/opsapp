//
//  ComingSoonView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-22.
//

import SwiftUI

struct ComingSoonView: View {
    @Environment(\.dismiss) private var dismiss
    let featureTitle: String
    let featureIcon: String
    let features: [FeatureItem]
    
    struct FeatureItem {
        let icon: String
        let title: String
        let description: String
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: featureTitle,
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Coming soon content
                ScrollView {
                    VStack(spacing: 32) {
                        Spacer(minLength: 40)
                        
                        Image(systemName: featureIcon)
                            .font(.system(size: 60, weight: .light))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        VStack(spacing: 16) {
                            Text("COMING SOON")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text("This feature will be available in the future.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 40)
                        }
                        
                        // Feature preview
                        VStack(alignment: .leading, spacing: 20) {
                            Text("PLANNED FEATURES")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.bottom, 4)
                            
                            ForEach(Array(features.enumerated()), id: \.offset) { _, feature in
                                featureRow(feature: feature)
                            }
                        }
                        .padding(20)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                        
                        // Update timeline
                        VStack(alignment: .leading, spacing: 16) {
                            Text("TIMELINE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.bottom, 4)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "clock")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Next Update")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(.white)
                                    
                                    Text("Expected in the coming weeks")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                
                                Spacer()
                            }
                        }
                        .padding(20)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(12)
                        .padding(.horizontal, 32)
                        
                        Spacer(minLength: 40)
                    }
                    .padding(.vertical, 20)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func featureRow(feature: FeatureItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(feature.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(feature.description)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
        }
    }
}

// MARK: - Predefined Coming Soon Views

extension ComingSoonView {
    static func expenses() -> ComingSoonView {
        ComingSoonView(
            featureTitle: "Expenses",
            featureIcon: "dollarsign.circle",
            features: [
                FeatureItem(
                    icon: "receipt",
                    title: "Expense Submission",
                    description: "Submit expenses with photo receipts directly from your phone"
                ),
                FeatureItem(
                    icon: "chart.bar",
                    title: "Approval Tracking",
                    description: "Track expense approvals and payment status in real-time"
                ),
                FeatureItem(
                    icon: "folder.badge.plus",
                    title: "Project Organization",
                    description: "Organize expenses by projects and categories for easy reporting"
                ),
                FeatureItem(
                    icon: "icloud.and.arrow.up",
                    title: "Office Integration",
                    description: "Automatic syncing with office accounting systems"
                )
            ]
        )
    }
    
    static func teamManagement() -> ComingSoonView {
        ComingSoonView(
            featureTitle: "Team Management",
            featureIcon: "person.3",
            features: [
                FeatureItem(
                    icon: "person.badge.plus",
                    title: "Invite Team Members",
                    description: "Send invitations to new team members to join your organization"
                ),
                FeatureItem(
                    icon: "lock.shield",
                    title: "Permission Management",
                    description: "Edit team member permissions and access levels"
                ),
                FeatureItem(
                    icon: "message",
                    title: "Direct Messaging",
                    description: "Send direct messages between team members"
                ),
                FeatureItem(
                    icon: "person.badge.minus",
                    title: "Member Management",
                    description: "Remove team members and manage their access"
                )
            ]
        )
    }
}

#Preview {
    ComingSoonView.expenses()
        .preferredColorScheme(.dark)
}
