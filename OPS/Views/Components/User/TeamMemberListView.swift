//
//  TeamMemberListView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//  Updated to support TeamMember model on 2025-05-08.
//

import SwiftUI
import SwiftData

/// A generic view that can display team members from either the User model or TeamMember model
struct TeamMemberListView: View {
    var userMembers: [User]? = nil
    var teamMembers: [TeamMember]? = nil
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var dataController: DataController
    
    private var isEmpty: Bool {
        (userMembers?.isEmpty ?? true) && (teamMembers?.isEmpty ?? true)
    }
    
    private var currentUserId: String? {
        dataController.currentUser?.id
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            
            if isEmpty {
                emptyStateView
            } else {
                memberListView
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private var headerView: some View {
        Text("TEAM MEMBERS")
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.bottom, 4)
    }
    
    private var emptyStateView: some View {
        Text("No team members assigned")
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
            .padding(.vertical, 8)
    }
    
    @ViewBuilder
    private var memberListView: some View {
        if let teamMembers = teamMembers, !teamMembers.isEmpty {
            ForEach(teamMembers, id: \.id) { member in
                TeamMemberRowV2(
                    teamMember: member,
                    isCurrentUser: member.id == currentUserId
                )
            }
        } else if let userMembers = userMembers {
            ForEach(userMembers) { member in
                TeamMemberRowV1(
                    user: member,
                    isCurrentUser: member.id == currentUserId
                )
            }
        }
    }
}

// MARK: - Legacy support for User model
struct TeamMemberRowV1: View {
    let user: User
    let isCurrentUser: Bool
    @Environment(\.openURL) private var openURL
    
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
                HStack(spacing: 6) {
                    Text("\(user.firstName) \(user.lastName)")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if isCurrentUser {
                        Text("(Me)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Text(user.role.rawValue)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Call button
            if let phone = user.phone, !phone.isEmpty {
                Button {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let url = URL(string: "tel:\(cleaned)") {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "phone.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - New version for TeamMember model
struct TeamMemberRowV2: View {
    let teamMember: TeamMember
    let isCurrentUser: Bool
    @State private var profileImage: Image?
    @State private var isLoadingImage = false
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        HStack(spacing: 12) {
            // Avatar 
            ZStack {
                if let profileImage = profileImage {
                    profileImage
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
            
            // Details
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(teamMember.fullName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if isCurrentUser {
                        Text("(Me)")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Text(teamMember.role)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Contact buttons
            HStack(spacing: 12) {
                // Email button
                if let email = teamMember.email, !email.isEmpty {
                    Button {
                        if let url = URL(string: "mailto:\(email)") {
                            openURL(url)
                        }
                    } label: {
                        Image(systemName: "envelope.circle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                
                // Call button
                if let phone = teamMember.phone, !phone.isEmpty {
                    Button {
                        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        if let url = URL(string: "tel:\(cleaned)") {
                            openURL(url)
                        }
                    } label: {
                        Image(systemName: "phone.circle.fill")
                            .font(.system(size: 24))
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
}
