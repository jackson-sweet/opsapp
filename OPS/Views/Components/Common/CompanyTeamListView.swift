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
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            // Header
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, OPSStyle.Layout.spacing1)
            
            if company.teamMembers.isEmpty {
                // Empty state with refresh button
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    Text("No team members found")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Button {
                        // Force a team member sync
                        Task {
                            await dataController.triggerTeamMembersSync(companyId: company.id)
                        }
                    } label: {
                        Label("Load Team Members", systemImage: "arrow.clockwise")
                            .font(OPSStyle.Typography.smallButton)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing2)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .nestedCard()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing3)
            } else {
                // Team member list with lazy loading for performance
                LazyVStack(spacing: OPSStyle.Layout.spacing2_5) {
                    ForEach(company.teamMembers, id: \.id) { member in
                        CompanyTeamMemberRow(teamMember: member)
                    }
                }
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }
}

/// Row component for displaying a single team member
struct CompanyTeamMemberRow: View {
    let teamMember: TeamMember
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Avatar - using unified UserAvatar component
            TeamMemberAvatar(teamMember: teamMember, size: 48)
            
            // Contact info
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
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
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "envelope")
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
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
                        .font(.system(size: OPSStyle.Layout.IconSize.lg))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding(OPSStyle.Layout.spacing2)
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .nestedCard()
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
            role: "Crew",
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
