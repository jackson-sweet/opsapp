//
//  ProfileCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI
import UIKit

/// A reusable component for user profile information display
/// NOTE: This is commented out because it conflicts with the existing UserProfileCard defined elsewhere
/// See /OPS/Views/Components/User/UserProfileCard.swift
/*
struct UserProfileCard: View {
    var user: User
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // User avatar
                ZStack {
                    if let profileURL = user.profileImageURL, 
                       !profileURL.isEmpty,
                       let cachedImage = ImageCache.shared.get(forKey: profileURL) {
                        Image(uiImage: cachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 60, height: 60)
                            .clipShape(Circle())
                    } else {
                        // Default profile circle with initial
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 60, height: 60)
                        
                        Text(getInitials())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    // Name and role
                    HStack(spacing: 8) {
                        Text(user.fullName)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text("| \(user.role.displayName)")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Email
                    if let email = user.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Phone
                    if let phone = user.phone, !phone.isEmpty {
                        Text(phone)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    // Helper to get user initials
    private func getInitials() -> String {
        if let firstInitial = user.firstName.first, let lastInitial = user.lastName.first {
            return "\(firstInitial)\(lastInitial)".uppercased()
        } else if let firstInitial = user.firstName.first {
            return String(firstInitial).uppercased()
        } else if let lastInitial = user.lastName.first {
            return String(lastInitial).uppercased()
        }
        return "U"
    }
}
*/

// All preview code removed - use the original UserProfileCard from Views/Components/User instead