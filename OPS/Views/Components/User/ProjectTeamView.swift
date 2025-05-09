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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with see all button
            HStack {
                Text("TEAM MEMBERS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                if project.teamMembers.count > 3 {
                    Button(action: {
                        // Show full team member list
                        showingTeamMemberDetails = true
                        selectedTeamMember = nil
                    }) {
                        Text("See All")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.bottom, 4)
            
            if project.teamMembers.isEmpty {
                // Empty state
                Text("No team members assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                // Show only first 3 team members with avatars for compact view
                let visibleMembers = project.teamMembers.prefix(3)
                
                ForEach(Array(visibleMembers), id: \.id) { member in
                    Button(action: {
                        selectedTeamMember = member
                        showingTeamMemberDetails = true
                    }) {
                        HStack(spacing: 12) {
                            // Avatar
                            TeamMemberAvatar(user: member, size: 40)
                            
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
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Show the count of additional members if any
                if project.teamMembers.count > 3 {
                    Text("+ \(project.teamMembers.count - 3) more team members...")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.top, 4)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let selectedMember = selectedTeamMember {
                // Show details for a single member
                TeamMemberDetailView(user: selectedMember, teamMember: nil)
            } else {
                // Show full team list
                FullTeamListView(project: project)
            }
        }
    }
}

/// Avatar component for team members
struct TeamMemberAvatar: View {
    let user: User
    let size: CGFloat
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let imageData = user.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let profileImage = image {
                profileImage
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                            .font(.system(size: size * 0.4, weight: .bold))
                            .foregroundColor(.white)
                    )
            }
        }
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        // Only load if we don't have local data and don't already have an image
        guard user.profileImageData == nil, image == nil, let imageURL = user.profileImageURL, !imageURL.isEmpty else {
            return
        }
        
        // Check cache first
        if let cachedImage = ImageCache.shared.get(forKey: imageURL) {
            self.image = Image(uiImage: cachedImage)
            return
        }
        
        // Load from URL
        Task {
            do {
                // Handle URLs that start with // by adding https:
                var finalURL = imageURL
                if imageURL.hasPrefix("//") {
                    finalURL = "https:" + imageURL
                }
                
                guard let url = URL(string: finalURL) else { return }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.image = Image(uiImage: uiImage)
                        ImageCache.shared.set(uiImage, forKey: imageURL)
                    }
                }
            } catch {
                print("Failed to load profile image: \(error.localizedDescription)")
            }
        }
    }
}

/// Full team list view that shows in a sheet
struct FullTeamListView: View {
    let project: Project
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamMember: User? = nil
    @State private var showingMemberDetails = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(project.teamMembers) { member in
                            Button(action: {
                                selectedTeamMember = member
                                showingMemberDetails = true
                            }) {
                                HStack(spacing: 16) {
                                    // Avatar
                                    TeamMemberAvatar(user: member, size: 50)
                                    
                                    // Details
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("\(member.firstName) \(member.lastName)")
                                            .font(.system(size: 16, weight: .medium))
                                            .foregroundColor(.white)
                                        
                                        Text(member.role.displayName)
                                            .font(.system(size: 14))
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        
                                        if let email = member.email, !email.isEmpty {
                                            Text(email)
                                                .font(.system(size: 12))
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                                .lineLimit(1)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                        .font(.system(size: 14))
                                }
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Project Team")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showingMemberDetails) {
                if let member = selectedTeamMember {
                    TeamMemberDetailView(user: member, teamMember: nil)
                }
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