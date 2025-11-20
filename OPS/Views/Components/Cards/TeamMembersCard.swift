//
//  TeamMembersCard.swift
//  OPS
//
//  Reusable team members display card
//

import SwiftUI

struct TeamMembersCard: View {
    let title: String
    let teamMembers: [User]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: OPSStyle.Icons.crew)
                    .font(.system(size: 20))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(title.uppercased())
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Spacer()
                
                // Team count
                Text("\(teamMembers.count)")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                    )
            }
            .padding(.bottom, 8)
            
            // Team member list
            if teamMembers.isEmpty {
                Text("No team members assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .padding(.vertical, 8)
            } else {
                ForEach(teamMembers, id: \.id) { member in
                    HStack(spacing: 12) {
                        // Avatar
                        UserAvatar(user: member, size: 40)
                        
                        // Member info
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.fullName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            HStack(spacing: 8) {
                                // Role
                                Text(member.role.displayName)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                // Phone if available
                                if let phone = member.phone, !phone.isEmpty {
                                    Text("•")
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    
                                    Text(phone)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.tertiaryText.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            logTeamMembersCardData()
        }
    }
    
    // MARK: - Debug Logging
    
    private func logTeamMembersCardData() {
        
        if teamMembers.isEmpty {
        } else {
            for (index, member) in teamMembers.enumerated() {
            }
        }
        
    }
}