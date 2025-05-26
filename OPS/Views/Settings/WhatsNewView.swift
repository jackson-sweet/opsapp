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
    
    struct FeatureCategory {
        let name: String
        let icon: String
        let features: [FeatureItem]
    }
    
    @State private var expandedCategories: Set<String> = []
    
    let featureCategories = [
        FeatureCategory(
            name: "Calendar & Scheduling",
            icon: "calendar",
            features: [
                FeatureItem(
                    icon: "calendar.badge.plus",
                    title: "Calendar Request System",
                    description: "Long press on calendar dates to request days off or schedule changes",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "cloud.sun.rain.fill",
                    title: "Weather Integration",
                    description: "Choose weather source in settings, mark jobs as weather dependent, get rain warnings",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Time & Analytics",
            icon: "clock.fill",
            features: [
                FeatureItem(
                    icon: "location.circle.fill",
                    title: "Automatic Time Tracking",
                    description: "Auto-start tracking when arriving at projects, stop when leaving",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Work Analytics",
                    description: "Track days worked, hours logged, jobs completed per hour, and productivity trends",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Project Analytics",
                    description: "Track project completion times, team productivity, and trends",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Team & Communication",
            icon: "person.2.fill",
            features: [
                FeatureItem(
                    icon: "person.2.fill",
                    title: "Team Member Notes",
                    description: "Add specific notes for each team member on a project",
                    status: "In Development"
                ),
                FeatureItem(
                    icon: "map.fill",
                    title: "Team Member Locations",
                    description: "See where your team members are on the map with real-time updates",
                    status: "In Development"
                ),
                FeatureItem(
                    icon: "message.fill",
                    title: "In-App Messaging",
                    description: "Message team members directly within the app with project context",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "person.crop.circle.badge.checkmark",
                    title: "Contact Info Updates",
                    description: "Update teammate contact info with approval notifications",
                    status: "Planned"
                ),
                FeatureItem(
                    icon: "bell.badge",
                    title: "Project Note Notifications",
                    description: "Get notified when teammates update project notes",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Business Features",
            icon: "dollarsign.circle.fill",
            features: [
                FeatureItem(
                    icon: "creditcard.fill",
                    title: "Payment Processing",
                    description: "Set up payment model for business transactions",
                    status: "Planned"
                ),
                FeatureItem(
                    icon: "receipt.fill",
                    title: "Expense Tracking",
                    description: "Detailed expense tracking and submission functionality",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "checkmark.shield.fill",
                    title: "Certifications & Training",
                    description: "Track team member certifications, training records, and expiration dates",
                    status: "Coming Soon"
                )
            ]
        ),
        FeatureCategory(
            name: "AI & Web Features",
            icon: "brain",
            features: [
                FeatureItem(
                    icon: "globe",
                    title: "Web Application",
                    description: "Access OPS from any web browser",
                    status: "Planned"
                ),
                FeatureItem(
                    icon: "doc.text.magnifyingglass",
                    title: "AI Quoting System",
                    description: "Upload price sheets and project drawings for AI-powered quotes",
                    status: "Planned"
                ),
                FeatureItem(
                    icon: "eyedropper.halffull",
                    title: "Smart UI Colors",
                    description: "Extract colors from company logo for personalized UI themes",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Data & Projects",
            icon: "folder.fill",
            features: [
                FeatureItem(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Multiple Project Visits",
                    description: "Track multiple visits to the same project with new 'visit' data type",
                    status: "Coming Soon"
                ),
                FeatureItem(
                    icon: "doc.text.fill",
                    title: "Client Project History",
                    description: "View all projects for a specific client in one place",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Technology Integration",
            icon: "apps.iphone",
            features: [
                FeatureItem(
                    icon: "car.fill",
                    title: "Apple CarPlay",
                    description: "Access OPS safely while driving with CarPlay integration",
                    status: "Planned"
                )
            ]
        ),
        FeatureCategory(
            name: "Marketing & Merchandise",
            icon: "tag.fill",
            features: [
                FeatureItem(
                    icon: "tshirt.fill",
                    title: "OPS Merchandise",
                    description: "Limited edition OPS apparel - launching soon!",
                    status: "Coming Soon"
                )
            ]
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
                        
                        // Categorized features list
                        VStack(spacing: 12) {
                            ForEach(featureCategories, id: \.name) { category in
                                FeatureCategorySection(
                                    category: category,
                                    isExpanded: expandedCategories.contains(category.name),
                                    onToggle: {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            if expandedCategories.contains(category.name) {
                                                expandedCategories.remove(category.name)
                                            } else {
                                                expandedCategories.insert(category.name)
                                            }
                                        }
                                    }
                                )
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

struct FeatureCategorySection: View {
    let category: WhatsNewView.FeatureCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            // Category header
            Button(action: onToggle) {
                HStack {
                    // Category icon
                    Image(systemName: category.icon)
                        .font(.system(size: 20))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 30)
                    
                    Text(category.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Feature count badge
                    Text("\(category.features.count)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(4)
                    
                    // Expand/collapse chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .padding(16)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded features
            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(category.features, id: \.title) { feature in
                        FeatureCard(feature: feature)
                            .padding(.leading, 20)
                    }
                }
                .padding(.top, 8)
            }
        }
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
                    .frame(width: 36, height: 36)
                
                Image(systemName: feature.icon)
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
            // Content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(feature.title)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    // Status badge
                    Text(feature.status)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .cornerRadius(4)
                }
                
                Text(feature.description)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
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
