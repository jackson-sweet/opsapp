//
//  OrganizationTeamView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

struct OrganizationTeamView: View {
    let company: Company
    @EnvironmentObject private var dataController: DataController
    @State private var selectedTeamMember: TeamMember? = nil
    @State private var showingTeamMemberDetails = false
    @State private var showingFullTeamList = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with see all button
            HStack {
                Text("TEAM MEMBERS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                if company.teamMembers.count > 3 {
                    Button(action: {
                        showingFullTeamList = true
                    }) {
                        Text("See All")
                            .font(OPSStyle.Typography.smallButton)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            .padding(.bottom, 4)
            
            if company.teamMembers.isEmpty {
                // Empty state with refresh button
                VStack(spacing: 12) {
                    Text("No team members found")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Button {
                        // Force a team member sync
                        Task {
                            await dataController.syncManager?.syncCompanyTeamMembers(company)
                        }
                    } label: {
                        Label("Load Team Members", systemImage: "arrow.clockwise")
                            .font(OPSStyle.Typography.smallButton)
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(8)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                // Show only first 3 team members with avatars for compact view
                let visibleMembers = company.teamMembers.prefix(3)
                
                ForEach(Array(visibleMembers), id: \.id) { member in
                    Button(action: {
                        selectedTeamMember = member
                        showingTeamMemberDetails = true
                    }) {
                        HStack(spacing: 12) {
                            // Avatar
                            CompanyTeamMemberAvatar(teamMember: member, size: 40)
                            
                            // Name & role
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.fullName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                
                                Text(member.role)
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
                if company.teamMembers.count > 3 {
                    Text("+ \(company.teamMembers.count - 3) more team members...")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.top, 4)
                }
            }
        }
        .sheet(isPresented: $showingTeamMemberDetails) {
            if let member = selectedTeamMember {
                TeamMemberDetailView(user: nil, teamMember: member)
            }
        }
        .sheet(isPresented: $showingFullTeamList) {
            OrganizationFullTeamView(company: company)
        }
    }
}

/// Avatar component for company team members
struct CompanyTeamMemberAvatar: View {
    let teamMember: TeamMember
    let size: CGFloat
    @State private var image: Image?
    
    var body: some View {
        ZStack {
            if let profileImage = image {
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
                        Text(teamMember.initials)
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
        // Only load if we don't already have an image
        guard image == nil, let imageURL = teamMember.avatarURL, !imageURL.isEmpty else {
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

/// Full organization team list view that shows in a sheet
struct OrganizationFullTeamView: View {
    let company: Company
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTeamMember: TeamMember? = nil
    @State private var showingMemberDetails = false
    @State private var searchText = ""
    
    var filteredMembers: [TeamMember] {
        if searchText.isEmpty {
            return company.teamMembers
        } else {
            return company.teamMembers.filter { member in
                member.fullName.localizedCaseInsensitiveContains(searchText) ||
                member.role.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                // Team member grid
                VStack {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        TextField("Search team members", text: $searchText)
                            .foregroundColor(.white)
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(10)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    
                    if filteredMembers.isEmpty {
                        VStack(spacing: 20) {
                            Spacer()
                            
                            if searchText.isEmpty {
                                // No team members at all
                                Image(systemName: "person.3.sequence.fill")
                                    .font(.system(size: 48))
                                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.5))
                                
                                Text("No team members found")
                                    .font(.headline)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            } else {
                                // No search results
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.5))
                                
                                Text("No team members matching '\(searchText)'")
                                    .font(.headline)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Button("Clear Search") {
                                    searchText = ""
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(OPSStyle.Colors.primaryAccent)
                                .foregroundColor(.white)
                                .cornerRadius(8)
                            }
                            
                            Spacer()
                        }
                    } else {
                        // Team member list
                        ScrollView {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(filteredMembers, id: \.id) { member in
                                    Button(action: {
                                        selectedTeamMember = member
                                        showingMemberDetails = true
                                    }) {
                                        TeamMemberCard(teamMember: member)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                            .padding()
                        }
                    }
                }
            }
            .navigationTitle("\(company.name) Team")
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
                    TeamMemberDetailView(user: nil, teamMember: member)
                }
            }
        }
    }
}

/// Card for displaying team members in a grid
struct TeamMemberCard: View {
    let teamMember: TeamMember
    @State private var profileImage: Image?
    
    var body: some View {
        VStack(spacing: 8) {
            // Avatar
            ZStack {
                if let profileImage = profileImage {
                    profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 70, height: 70)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 70, height: 70)
                    
                    Text(teamMember.initials)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            
            // Name
            Text(teamMember.fullName)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)
                .multilineTextAlignment(.center)
            
            // Role
            Text(teamMember.role)
                .font(.system(size: 12))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 110, minHeight: 130)
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(12)
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard profileImage == nil, let avatarURL = teamMember.avatarURL, !avatarURL.isEmpty else {
            return
        }
        
        // Check cache first
        if let cachedImage = ImageCache.shared.get(forKey: avatarURL) {
            self.profileImage = Image(uiImage: cachedImage)
            return
        }
        
        // Load from URL
        Task {
            do {
                // Handle URLs that start with // by adding https:
                var finalURL = avatarURL
                if avatarURL.hasPrefix("//") {
                    finalURL = "https:" + avatarURL
                }
                
                guard let url = URL(string: finalURL) else { return }
                
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.profileImage = Image(uiImage: uiImage)
                        ImageCache.shared.set(uiImage, forKey: avatarURL)
                    }
                }
            } catch {
                print("Failed to load profile image: \(error.localizedDescription)")
            }
        }
    }
}

struct OrganizationTeamView_Previews: PreviewProvider {
    static var previews: some View {
        let company = Company(id: "123", name: "Acme Construction")
        
        // Add sample team members
        let member1 = TeamMember(
            id: "1", 
            firstName: "John", 
            lastName: "Doe", 
            role: "Project Manager",
            email: "john.doe@example.com",
            phone: "555-123-4567"
        )
        
        let member2 = TeamMember(
            id: "2", 
            firstName: "Jane", 
            lastName: "Smith", 
            role: "Field Crew",
            email: "jane.smith@example.com",
            phone: "555-987-6543"
        )
        
        let member3 = TeamMember(
            id: "3", 
            firstName: "Mike", 
            lastName: "Johnson", 
            role: "Office Manager",
            email: "mike.j@example.com",
            phone: ""
        )
        
        let member4 = TeamMember(
            id: "4", 
            firstName: "Sarah", 
            lastName: "Williams", 
            role: "Field Crew",
            email: "sarah.w@example.com",
            phone: "555-555-5555"
        )
        
        company.teamMembers = [member1, member2, member3, member4]
        
        return Group {
            OrganizationTeamView(company: company)
                .environmentObject(DataController())
                .padding()
                .background(OPSStyle.Colors.background)
                .preferredColorScheme(.dark)
                .previewLayout(.sizeThatFits)
            
            OrganizationFullTeamView(company: company)
                .preferredColorScheme(.dark)
        }
    }
}