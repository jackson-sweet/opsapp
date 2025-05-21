//
//  ListItems.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI
import UIKit

/// A reusable basic list item component with consistent styling
struct ListItem: View {
    var title: String
    var description: String? = nil
    var iconName: String? = nil
    var showChevron: Bool = true
    var isDisabled: Bool = false
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // Icon if provided
                if let icon = iconName {
                    ZStack {
                        Circle()
                            .stroke(
                                isDisabled ? 
                                    OPSStyle.Colors.tertiaryText.opacity(0.3) : 
                                    OPSStyle.Colors.primaryText.opacity(0.5),
                                lineWidth: 1.5
                            )
                            .frame(width: 40, height: 40)
                        
                        Image(systemName: icon)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    }
                }
                
                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : .white)
                    
                    if let description = description, !description.isEmpty {
                        Text(description)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Chevron
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                }
            }
            .padding(16)
            .background(isDisabled ? OPSStyle.Colors.cardBackgroundDark.opacity(0.4) : OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .disabled(isDisabled)
    }
}

// Note: Commenting out UserListItem and ProjectListItem to fix compilation errors
// We'll need to reimplement these once we have enough information about the User and Project models
/*
/// A reusable user list item with avatar, name and role
struct UserListItem: View {
    var user: User
    var showChevron: Bool = true
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                // User avatar
                ZStack {
                    if let profileURL = user.profileImageURL, 
                       !profileURL.isEmpty,
                       let cachedImage = ImageCache.shared.get(forKey: profileURL) {
                        Image(uiImage: cachedImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                    } else {
                        // Default profile circle with initial
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 44, height: 44)
                        
                        Text(getInitials(user: user))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(.white)
                    }
                }
                
                // Name and role
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.fullName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                    
                    Text(user.role.displayName)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
                
                // Chevron
                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
        }
    }
    
    // Helper to get user initials
    private func getInitials(user: User) -> String {
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

/// A reusable project list item with title, status and description
struct ProjectListItem: View {
    var project: Project
    var showChevron: Bool = true
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                // Header with title and status
                HStack {
                    Text(project.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    StatusBadge.forJobStatus(project.status)
                }
                
                // Description
                if !project.clientName.isEmpty {
                    Text(project.clientName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                if !project.address.isEmpty {
                    Text(project.address)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }
                
                if let startDate = project.startDate {
                    Text("Start: \(formatDate(startDate))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                // View details link
                if showChevron {
                    HStack {
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("View Details")
                                .font(OPSStyle.Typography.captionBold)
                            
                            Image(systemName: "arrow.right")
                                .font(.system(size: 12))
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.top, 4)
                    }
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
        }
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
*/

struct ListItemsPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            ListItem(
                title: "App Settings",
                description: "Manage app preferences",
                iconName: "gearshape.fill",
                action: {}
            )
            
            ListItem(
                title: "Notifications",
                description: "Configure push notifications",
                iconName: "bell.fill",
                isDisabled: true,
                action: {}
            )
            
            // UserListItem and ProjectListItem previews removed (commented out)
        }
        .padding()
        .background(OPSStyle.Colors.backgroundGradient)
        .preferredColorScheme(.dark)
    }
}

#if swift(>=5.9)
#Preview {
    ListItemsPreview()
}
#else
struct ListItemsPreview_Previews: PreviewProvider {
    static var previews: some View {
        ListItemsPreview()
    }
}
#endif
