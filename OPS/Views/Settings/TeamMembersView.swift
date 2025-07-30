//
//  TeamMembersView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI
import SwiftData

struct TeamMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.openURL) private var openURL
    
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var teamMembers: [User] = []
    @State private var selectedMember: User? = nil
    
    var filteredMembers: [User] {
        if searchText.isEmpty { return teamMembers }
        
        return teamMembers.filter { member in
            return member.fullName.localizedCaseInsensitiveContains(searchText) ||
                   member.email?.localizedCaseInsensitiveContains(searchText) ?? false ||
                   member.role.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Team Members",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    TextField("Search team members", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.5)
                        .padding()
                    Spacer()
                } else if teamMembers.isEmpty {
                    emptyStateView
                } else {
                    // Team members list
                    ScrollView {
                        VStack(spacing: 16) {
                            SettingsSectionHeader(title: "TEAM MEMBERS")
                            
                            if filteredMembers.isEmpty && !searchText.isEmpty {
                                Text("No team members match '\(searchText)'")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.top, 24)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(filteredMembers) { member in
                                    memberCard(member)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                        .tabBarPadding() // Add padding for tab bar
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadTeamMembers()
        }
        .sheet(item: $selectedMember) { member in
            TeamMemberDetailView(user: member, teamMember: nil)
        }
    }
    
    // MARK: - Component Views
    
    private var emptyStateView: some View {
        VStack {
            Spacer()
            
            EmptyStateView(
                icon: "person.3.sequence.fill",
                title: "No Team Members",
                message: "There are no team members in your organization yet."
            )
            .padding(.horizontal, 20)
            
            Spacer()
        }
    }
    
    private func memberCard(_ member: User) -> some View {
        Button(action: {
            selectedMember = member
        }) {
            HStack(spacing: 16) {
                // Member avatar - using unified UserAvatar component
                UserAvatar(user: member, size: 50)
                
                // Member details
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(member.firstName) \(member.lastName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text(member.role.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    if let email = member.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Status indicator
                if member.isActive != false {
                    Circle()
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: 10, height: 10)
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    // MARK: - Data Loading
    
    private func loadTeamMembers() {
        isLoading = true
        
        Task {
            // Load team members from data controller
            if let companyId = dataController.currentUser?.companyId {
                let members = dataController.getTeamMembers(companyId: companyId)
                
                await MainActor.run {
                    self.teamMembers = members
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.teamMembers = []
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    TeamMembersView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
