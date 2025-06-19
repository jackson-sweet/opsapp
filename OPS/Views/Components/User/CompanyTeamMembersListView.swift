//
//  CompanyTeamMembersListView.swift 
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//  Renamed from CompanyTeamListView to avoid naming conflict
//

import SwiftUI

/// Team member list view that works with the lightweight TeamMember model
/// Used to display company team members without loading the full User objects
struct CompanyTeamMembersListView: View {
    let company: Company
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            if company.teamMembers.isEmpty {
                // Empty state
                Text("No team members loaded")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.vertical, 8)
                
                // Loading button
                Button(action: { 
                    fetchTeamMembers()
                }) {
                    Label("Load Team Members", systemImage: "arrow.clockwise")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.vertical, 8)
                }
            } else {
                // Team member list
                ForEach(company.teamMembers, id: \.id) { member in
                    CompanyTeamMemberListRow(teamMember: member)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func fetchTeamMembers() {
        // Use DataController from environment
        guard let syncManager = dataController.syncManager else {
            return
        }
        
        // Trigger team members fetch
        Task {
            await syncManager.syncCompanyTeamMembers(company)
        }
    }
}

/// Row component to display a single team member from the Company model
struct CompanyTeamMemberListRow: View {
    let teamMember: TeamMember
    @State private var profileImage: UIImage?
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                if let image = profileImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(teamMember.initials)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            
            // User details
            VStack(alignment: .leading, spacing: 4) {
                Text(teamMember.fullName)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(teamMember.role)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                // Email (if available)
                if let email = teamMember.email, !email.isEmpty {
                    Text(email)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 12) {
                // Email button
                if let email = teamMember.email, !email.isEmpty {
                    Button(action: {
                        if let url = URL(string: "mailto:\(email)") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.secondaryAccent.opacity(0.8))
                    }
                }
                
                // Call button
                if let phone = teamMember.phone, !phone.isEmpty {
                    Button(action: {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard let avatarURL = teamMember.avatarURL, !avatarURL.isEmpty else {
            return
        }
        
        // First check if image is already cached
        if let cachedImage = ImageCache.shared.get(forKey: avatarURL) {
            self.profileImage = cachedImage
            return
        }
        
        // Otherwise load from URL
        Task {
            do {
                var imageURL = avatarURL
                
                // Fix for URLs starting with //
                if imageURL.starts(with: "//") {
                    imageURL = "https:" + imageURL
                }
                
                // Create URL
                guard let url = URL(string: imageURL) else { return }
                
                // Fetch image data
                let (data, _) = try await URLSession.shared.data(from: url)
                
                // Create image and update UI on main thread
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        // Cache the image for future use
                        ImageCache.shared.set(image, forKey: avatarURL)
                        self.profileImage = image
                    }
                }
            } catch {
                print("Error loading team member profile image: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    // Sample data for preview
    let company = Company(id: "sample-company", name: "Sample Company")
    
    // Add sample team members
    let member1 = TeamMember(id: "1", firstName: "John", lastName: "Doe", role: "Field Crew", email: "john@example.com", phone: "555-123-4567")
    member1.company = company
    company.teamMembers.append(member1)
    
    let member2 = TeamMember(id: "2", firstName: "Jane", lastName: "Smith", role: "Office Crew", email: "jane@example.com", phone: "555-987-6543")
    member2.company = company
    company.teamMembers.append(member2)
    
    return CompanyTeamMembersListView(company: company)
        .environmentObject(DataController())
        .padding()
        .background(OPSStyle.Colors.backgroundGradient)
        .preferredColorScheme(.dark)
}