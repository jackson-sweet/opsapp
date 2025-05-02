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
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 60, height: 60)
                
                Text(String(user.fullName.prefix(1)))
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(user.fullName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                
                Text(user.email ?? "")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(user.role.displayName)
                    .font(.system(size: 14))
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