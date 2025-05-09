//
//  CompanyTeamListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import SwiftData

/// Displays a list of team members for a company
struct CompanyTeamListView: View {
    let company: Company
    @EnvironmentObject private var dataController: DataController
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
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
                // Team member list with lazy loading for performance
                LazyVStack(spacing: 12) {
                    ForEach(company.teamMembers, id: \.id) { member in
                        CompanyTeamMemberRow(teamMember: member)
                    }
                }
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(12)
    }
}

/// Row component for displaying a single team member
struct CompanyTeamMemberRow: View {
    let teamMember: TeamMember
    @State private var profileImage: Image?
    @State private var isLoadingImage = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar or initials
            ZStack {
                if let profileImage = profileImage {
                    profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 48, height: 48)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 48, height: 48)
                    
                    Text(teamMember.initials)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .overlay(
                Circle()
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
            )
            
            // Contact info
            VStack(alignment: .leading, spacing: 4) {
                Text(teamMember.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(teamMember.role)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                if let email = teamMember.email {
                    Button {
                        openEmail(email)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "envelope")
                                .font(.system(size: 10))
                            Text(email)
                                .font(OPSStyle.Typography.caption)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            
            Spacer()
            
            // Contact buttons
            if let phone = teamMember.phone, !phone.isEmpty {
                Button {
                    callPhone(phone)
                } label: {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(8)
            }
        }
        .padding(8)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(8)
        .onAppear {
            loadProfileImage()
        }
    }
    
    private func loadProfileImage() {
        guard !isLoadingImage, let urlString = teamMember.avatarURL, !urlString.isEmpty else {
            return
        }
        
        isLoadingImage = true
        
        // First check if the image is in the cache
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            self.profileImage = Image(uiImage: cachedImage)
            isLoadingImage = false
            return
        }
        
        // Otherwise load from the URL
        guard let url = URL(string: urlString) else {
            isLoadingImage = false
            return
        }
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.profileImage = Image(uiImage: uiImage)
                        ImageCache.shared.set(uiImage, forKey: urlString)
                    }
                }
            } catch {
                print("Failed to load profile image: \(error.localizedDescription)")
            }
            
            await MainActor.run {
                isLoadingImage = false
            }
        }
    }
    
    private func openEmail(_ email: String) {
        if let url = URL(string: "mailto:\(email)") {
            openURL(url)
        }
    }
    
    private func callPhone(_ phone: String) {
        // Clean phone number by removing non-numeric characters
        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        if let url = URL(string: "tel:\(cleaned)") {
            openURL(url)
        }
    }
}

// MARK: - Preview

struct CompanyTeamListView_Previews: PreviewProvider {
    static var previews: some View {
        let company = previewCompany()
        
        return CompanyTeamListView(company: company)
            .environmentObject(DataController())
            .padding()
            .previewLayout(.sizeThatFits)
    }
    
    static func previewCompany() -> Company {
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
        
        company.teamMembers = [member1, member2, member3]
        
        return company
    }
}