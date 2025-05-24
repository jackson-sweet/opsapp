//
//  WhatsNewView.swift
//  OPS
//
//  Shows upcoming features and what the team is working on
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    
    struct FeatureItem {
        let icon: String
        let title: String
        let description: String
        let status: String
    }
    
    let upcomingFeatures = [
        FeatureItem(
            icon: "person.2.fill",
            title: "Team Member Notes",
            description: "Add specific notes for each team member on a project, replacing general project notes",
            status: "In Development"
        ),
        FeatureItem(
            icon: "map.fill",
            title: "Team Member Locations",
            description: "See where your team members are on the map with real-time updates",
            status: "In Development"
        ),
        FeatureItem(
            icon: "checkmark.shield.fill",
            title: "Certifications & Training",
            description: "Track team member certifications, training records, and expiration dates",
            status: "Coming Soon"
        ),
        FeatureItem(
            icon: "message.fill",
            title: "In-App Messaging",
            description: "Message team members directly within the app with project context",
            status: "Coming Soon"
        ),
        FeatureItem(
            icon: "doc.text.fill",
            title: "Client Project History",
            description: "View all projects for a specific client in one place",
            status: "Planned"
        ),
        FeatureItem(
            icon: "chart.line.uptrend.xyaxis",
            title: "Project Analytics",
            description: "Track project completion times, team productivity, and trends",
            status: "Planned"
        )
    ]
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "WHAT'S COMING",
                    showEditButton: false,
                    onBackTapped: { dismiss() }
                )
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Intro text
                        VStack(alignment: .leading, spacing: 12) {
                        
                            Text("We're always working to make OPS better for our crews.")
                                .font(.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            Text("Here's what's coming next:".uppercased())
                                .font(.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 20)
                        
                        // Features list
                        VStack(spacing: 16) {
                            ForEach(upcomingFeatures, id: \.title) { feature in
                                FeatureCard(feature: feature)
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        // Feedback section
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Have a Feature Request?")
                                .font(.subtitle)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Text("We build OPS based on feedback from actual field crews. Your input shapes our roadmap.")
                                .font(.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            NavigationLink(destination: FeatureRequestView()) {
                                HStack {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 18))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    
                                    Text("Send Feature Request")
                                        .font(.bodyBold)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 14))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding()
                                .background(Color.clear)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                )
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 32)
                        .padding(.bottom, 40)
                    }
                }
                .tabBarPadding()
            }
        }
        .navigationBarBackButtonHidden(true)
        .enableNativeSwipeBack()
    }
}

struct FeatureCard: View {
    let feature: WhatsNewView.FeatureItem
    
    var statusColor: Color {
        switch feature.status {
        case "In Development":
            return OPSStyle.Colors.secondaryAccent
        case "Coming Soon":
            return OPSStyle.Colors.primaryAccent
        default:
            return OPSStyle.Colors.secondaryText
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(width: 44, height: 44)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(feature.title)
                        .font(.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Status badge
                    Text(feature.status)
                        .font(.smallCaption)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(feature.description)
                    .font(.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// Preview
#Preview {
    NavigationStack {
        WhatsNewView()
    }
    .preferredColorScheme(.dark)
}
