//
//  ProjectTeamView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

/// Compact team member view for projects with navigation to details
struct ProjectTeamView: View {
    let project: Project
    @State private var selectedTeamMember: User? = nil
    @State private var showingTeamMemberDetails = false
    @EnvironmentObject private var dataController: DataController
    @State private var teamsRefreshed = false
    @State private var refreshKey = UUID() // Force refresh when this changes
    @State private var refreshedProject: Project? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Use refreshedProject if available, otherwise use original project
            let activeProject = refreshedProject ?? project
            
            // Show team member info or loading state
            if !teamsRefreshed && activeProject.getTeamMemberIds().count > 0 && activeProject.teamMembers.isEmpty {
                // Loading state - team members are loading
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Text("Loading team members...")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.vertical, 8)
            } else if activeProject.teamMembers.isEmpty {
                // Empty state
                Text(activeProject.getTeamMemberIds().isEmpty ? 
                   "No team members assigned" : 
                   "Team member data unavailable")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                // Show ALL team members - no limit
                ForEach(activeProject.teamMembers, id: \.id) { member in
                    HStack(spacing: 12) {
                        // Avatar - using unified UserAvatar component
                        UserAvatar(user: member, size: 40)
                        
                        // Name & role
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(member.firstName) \(member.lastName)")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Text(member.role.rawValue)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        Spacer()
                        
                        // Indicator
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 6)
                    .onTapGesture {
                        selectedTeamMember = member
                        showingTeamMemberDetails = true
                    }
                    .onLongPressGesture {
                        // Same action as tap for now, can be customized later
                        selectedTeamMember = member
                        showingTeamMemberDetails = true
                    }
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                // Show team member details
                TeamMemberDetailView(user: selectedMember)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            } else {
                // Show full team list using the refreshed project if available
                if let refreshed = refreshedProject {
                    FullTeamListView(project: refreshed)
                } else {
                    FullTeamListView(project: project)
                }
            }
        }
        .onAppear {
            // Debug log the project team members when this view appears
            
            // Trigger manual team member sync
            if !teamsRefreshed {
                Task {
                    // Sync team members
                    await dataController.syncProjectTeamMembers(project)
                    
                    // Print updated info after sync
                    await MainActor.run {
                        
                        // Fetch fresh project from DataController (critical step)
                        if let freshProject = dataController.getProject(id: project.id) {
                            
                            if freshProject.teamMembers.isEmpty {
                            } else {
                                for (index, member) in freshProject.teamMembers.enumerated() {
                            }
                            
                            }
                            
                            // Update the refreshed project to trigger UI refresh
                            refreshedProject = freshProject
                        } else {
                        }
                        
                        // Update state to refresh the view
                        teamsRefreshed = true
                        refreshKey = UUID() // Force refresh
                    }
                }
            }
        }
        .id(refreshKey) // Force view to refresh when key changes
    }
}

// TeamMemberAvatar component removed - using unified UserAvatar instead

/// Full team list view that shows in a sheet
struct FullTeamListView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamMember: User? = nil
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(project.teamMembers) { member in
                            HStack(spacing: 16) {
                                // Avatar
                                UserAvatar(user: member, size: 50)
                                
                                // Details
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("\(member.firstName) \(member.lastName)")
                                        .font(OPSStyle.Typography.body.weight(.medium))
                                        .foregroundColor(.white)
                                    
                                    Text(member.role.displayName)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                    
                                    if let email = member.email, !email.isEmpty {
                                        Text(email)
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .lineLimit(1)
                                    }
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .font(OPSStyle.Typography.smallBody)
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(12)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedTeamMember = member
                            }
                            .onLongPressGesture {
                                // Same action as tap for now, can be customized later
                                selectedTeamMember = member
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PROJECT TEAM")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                }
            }
            .sheet(item: $selectedTeamMember) { member in
                TeamMemberDetailView(user: member)
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

struct ProjectTeamView_Previews: PreviewProvider {
    static var previews: some View {
        let project = Project(id: "123", title: "Sample Project", status: .inProgress)
        
        // Add sample team members
        let member1 = User(id: "1", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: "company-123")
        let member2 = User(id: "2", firstName: "Jane", lastName: "Smith", role: .officeCrew, companyId: "company-123")
        let member3 = User(id: "3", firstName: "Mike", lastName: "Johnson", role: .fieldCrew, companyId: "company-123")
        let member4 = User(id: "4", firstName: "Sarah", lastName: "Williams", role: .officeCrew, companyId: "company-123")
        
        project.teamMembers = [member1, member2, member3, member4]
        
        return Group {
            ProjectTeamView(project: project)
                .environmentObject(DataController())
                .padding()
                .background(OPSStyle.Colors.background)
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
            
            FullTeamListView(project: project)
                .preferredColorScheme(.dark)
        }
    }
}
