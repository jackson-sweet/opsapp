//
//  TeamMemberListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct TeamMemberListView: View {
    let teamMembers: [User]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            if teamMembers.isEmpty {
                // Empty state
                Text("No team members assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.vertical, 8)
            } else {
                // Team member list
                ForEach(teamMembers) { member in
                    TeamMemberRow(user: member)
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct TeamMemberRow: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            // User avatar
            ZStack {
                if let imageData = user.profileImageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 40, height: 40)
                        .clipShape(Circle())
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 40, height: 40)
                        .overlay(
                            Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                        )
                }
            }
            
            // User details
            VStack(alignment: .leading, spacing: 4) {
                Text("\(user.firstName) \(user.lastName)")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(user.role.rawValue)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Call button
            if let phone = user.phone, !phone.isEmpty {
                Button(action: {
                    if let url = URL(string: "tel:\(phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                }
            }
        }
        .padding(.vertical, 4)
    }
}