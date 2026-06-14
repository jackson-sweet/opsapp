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
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // User avatar
            UserAvatar(user: user, size: 60)
            
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text(user.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(user.email ?? "")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(user.role.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            
            Spacer()
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.largeCornerRadius)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }
}