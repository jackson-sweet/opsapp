//
//  UserProfileCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import SwiftUI

struct UserProfileCard: View {
    var user: User
    
    var body: some View {
        HStack(spacing: 16) {
            // User avatar
            UserAvatar(user: user, size: 60)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(user.email ?? "")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(user.role.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
            Spacer()
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(16)
        .padding(.horizontal, 20)
    }
}