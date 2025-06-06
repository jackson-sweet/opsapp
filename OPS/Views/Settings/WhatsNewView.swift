//
//  WhatsNewView.swift
//  OPS
//
//  Shows upcoming features and what the team is working on
//

import SwiftUI

struct WhatsNewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    
    @State private var expandedCategories: Set<String> = []
    @State private var votingFeatures: Set<String> = []
    @State private var votedFeatures: Set<String> = []
    @State private var showVoteError = false
    @State private var voteErrorMessage = ""
    
    // Use feature categories from AppConfiguration
    private let featureCategories = AppConfiguration.WhatsNew.featureCategories
    
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
                                    },
                                    votingFeatures: votingFeatures,
                                    votedFeatures: votedFeatures,
                                    onVote: voteForFeature
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
        .alert("Error", isPresented: $showVoteError) {
            Button("OK") { }
        } message: {
            Text(voteErrorMessage)
        }
        .onAppear {
            // Load previously voted features
            if let savedVotes = UserDefaults.standard.array(forKey: "votedFeatures") as? [String] {
                votedFeatures = Set(savedVotes)
            }
        }
    }
    
    private func voteForFeature(_ feature: AppConfiguration.WhatsNew.FeatureItem) {
        // Check if already voting or voted
        guard !votingFeatures.contains(feature.title),
              !votedFeatures.contains(feature.title) else { return }
        
        // Mark as voting
        votingFeatures.insert(feature.title)
        
        Task {
            do {
                try await submitFeatureVote(feature)
                
                await MainActor.run {
                    votingFeatures.remove(feature.title)
                    votedFeatures.insert(feature.title)
                    
                    // Store voted features in UserDefaults
                    UserDefaults.standard.set(Array(votedFeatures), forKey: "votedFeatures")
                }
            } catch {
                await MainActor.run {
                    votingFeatures.remove(feature.title)
                    voteErrorMessage = "Failed to submit vote. Please try again."
                    showVoteError = true
                }
            }
        }
    }
    
    private func submitFeatureVote(_ feature: AppConfiguration.WhatsNew.FeatureItem) async throws {
        // Get the current user ID
        guard let userId = dataController.currentUser?.id else {
            throw NSError(domain: "WhatsNewView", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Create standardized parameters - exact same format every time for accurate counting
        let parameters: [String: Any] = [
            "feature_title": feature.title,
            "feature_description": feature.description,
            "user": userId,
            "platform": "iOS mobile +1",
            "Requested By": userId,
            "isBug": false // This is a feature vote, not a bug
        ]
        
        // Create JSON body
        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        
        // Create URL
        let endpoint = "api/1.1/wf/request_feature"
        var request = URLRequest(url: AppConfiguration.bubbleBaseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Execute request
        let (_, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "WhatsNewView", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Check status code
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "WhatsNewView", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Request failed"])
        }
    }
}

struct FeatureCategorySection: View {
    let category: AppConfiguration.WhatsNew.FeatureCategory
    let isExpanded: Bool
    let onToggle: () -> Void
    let votingFeatures: Set<String>
    let votedFeatures: Set<String>
    let onVote: (AppConfiguration.WhatsNew.FeatureItem) -> Void
    
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
                    
                    Text(category.name.uppercased())
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
                        FeatureCard(
                            feature: feature,
                            isVoting: votingFeatures.contains(feature.title),
                            hasVoted: votedFeatures.contains(feature.title),
                            onVote: { onVote(feature) }
                        )
                        .padding(.leading, 20)
                    }
                }
                .padding(.top, 8)
            }
        }
    }
}

struct FeatureCard: View {
    let feature: AppConfiguration.WhatsNew.FeatureItem
    let isVoting: Bool
    let hasVoted: Bool
    let onVote: () -> Void
    
    var statusColor: Color {
        switch feature.status {
        case .inDevelopment:
            return OPSStyle.Colors.secondaryAccent
        case .comingSoon:
            return OPSStyle.Colors.primaryAccent
        case .planned:
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
                    Text(feature.status.rawValue)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(statusColor.opacity(0.2))
                        .cornerRadius(4)
                }
                
                HStack {
                    Text(feature.description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    Spacer()
                    
                    // +1 Vote button
                    Button(action: onVote) {
                        HStack(spacing: 4) {
                            Image(systemName: hasVoted ? "hand.thumbsup.fill" : "hand.thumbsup")
                                .font(.system(size: 14))
                            Text("+1")
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(hasVoted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            hasVoted ? OPSStyle.Colors.successStatus.opacity(0.2) : OPSStyle.Colors.primaryAccent.opacity(0.2)
                        )
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    hasVoted ? OPSStyle.Colors.successStatus : OPSStyle.Colors.primaryAccent,
                                    lineWidth: 1
                                )
                        )
                    }
                    .disabled(isVoting || hasVoted)
                    .opacity(isVoting ? 0.6 : 1.0)
                }
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
            .environmentObject(DataController())
    }
    .preferredColorScheme(.dark)
}
