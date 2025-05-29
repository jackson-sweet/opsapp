//
//  TeamMemberDetailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

/// Detail view for a team member, shown in a sheet with updated aesthetic
struct TeamMemberDetailView: View {
    // Can accept either a User or TeamMember
    let user: User?
    let teamMember: TeamMember?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var profileImage: Image?
    @State private var isLoadingImage = false
    @State private var showFullContact = false // For animating contact display
    
    // Constants for styling
    private let avatarSize: CGFloat = 120
    private let contactIconSize: CGFloat = 28
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile header with avatar - larger and more prominent
                        profileHeader
                            .padding(.top, 20)
                        
                        // Action buttons
                        contactButtons
                            .padding(.horizontal)
                        
                        Divider()
                            .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                            .padding(.horizontal)
                        
                        // Contact information with improved styling
                        contactSection
                            .padding(.horizontal)
                        
                        // Role information with improved card styling
                        // Only show role section if not a client
                        if !isClient {
                            roleSection
                                .padding(.horizontal)
                        }
                        
                        // Spacer for bottom padding
                        Spacer(minLength: 40)
                    }
                }
                .tabBarPadding()
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(width: 44, height: 44)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(isClient ? "CLIENT" : "TEAM MEMBER")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                }
            }
            .onAppear {
                loadProfileImage()
                // Animate contact info appearing
                withAnimation(.easeInOut.delay(0.3)) {
                    showFullContact = true
                }
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        VStack(spacing: 20) {
            // Profile image - now larger and with animation
            ZStack {
                if isLoadingImage {
                    // Show loading indicator
                    ZStack {
                        Circle()
                            .stroke(OPSStyle.Colors.secondaryText.opacity(0.3), lineWidth: 2)
                            .frame(width: avatarSize, height: avatarSize)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(1.5)
                    }
                } else if let profileImage = profileImage {
                    // Actual avatar image with glow effect
                    profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: avatarSize, height: avatarSize)
                        .clipShape(Circle())
                        .shadow(color: OPSStyle.Colors.primaryAccent.opacity(0.4), radius: 10)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 3)
                        )
                        .transition(.opacity)
                } else {
                    // Fallback with initials - no fill, primary text color stroke and font
                    Circle()
                        .stroke(OPSStyle.Colors.primaryText, lineWidth: 2)
                        .frame(width: avatarSize, height: avatarSize)
                        .shadow(color: Color.black.opacity(0.2), radius: 8)
                    
                    Text(initials)
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding(.bottom, 10)
            
            // Name and role on one row
            HStack(spacing: 8) {
                Text(fullName)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("|")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(role)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 16)
    }
    
    // MARK: - Contact Buttons
    
    private var contactButtons: some View {
        HStack(spacing: 36) {
            // Call Button
            if let phone = self.phone, !phone.isEmpty {
                Button(action: {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let phoneURL = URL(string: "tel:\(cleaned)") {
                        openURL(phoneURL)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "phone")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text("Call")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            
            // Message Button
            if let phone = self.phone, !phone.isEmpty {
                Button(action: {
                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                    if let smsURL = URL(string: "sms:\(cleaned)") {
                        openURL(smsURL)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "message")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text("Message")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            
            // Email Button
            if let email = self.email, !email.isEmpty {
                Button(action: {
                    if let emailURL = URL(string: "mailto:\(email)") {
                        openURL(emailURL)
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text("Email")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
        }
        .padding(.vertical, 10)
        .opacity(showFullContact ? 1 : 0)
        .offset(y: showFullContact ? 0 : 20)
        .animation(.easeInOut(duration: 0.4), value: showFullContact)
    }
    
    // MARK: - Contact Section
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text("CONTACT INFORMATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            // Contact cards with improved visuals
            VStack(spacing: 12) {
                // Email
                if let email = self.email, !email.isEmpty {
                    Button(action: {
                        if let emailURL = URL(string: "mailto:\(email)") {
                            openURL(emailURL)
                        }
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: contactIconSize, height: contactIconSize)
                                
                                Image(systemName: "envelope")
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Email")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(email)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .font(OPSStyle.Typography.smallBody)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Phone with formatter
                if let phone = self.phone, !phone.isEmpty {
                    Button(action: {
                        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        if let phoneURL = URL(string: "tel:\(cleaned)") {
                            openURL(phoneURL)
                        }
                    }) {
                        HStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                                    .frame(width: contactIconSize, height: contactIconSize)
                                
                                Image(systemName: "phone")
                                    .font(OPSStyle.Typography.smallBody)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phone")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(formatPhoneNumber(phone))
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .font(OPSStyle.Typography.smallBody)
                        }
                        .padding(.vertical, 14)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .opacity(showFullContact ? 1 : 0)
            .offset(y: showFullContact ? 0 : 20)
            .animation(.easeInOut(duration: 0.5).delay(0.1), value: showFullContact)
        }
    }
    
    // MARK: - Role Section
    
    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text("ROLE INFORMATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            // Role info card with improved styling
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackground)
                        .frame(width: contactIconSize, height: contactIconSize)
                    
                    Image(systemName: isClient ? "building.2" : "person.badge.shield.checkmark")
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(isClient ? "Type" : "Employee Type")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(role)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .opacity(showFullContact ? 1 : 0)
            .offset(y: showFullContact ? 0 : 20)
            .animation(.easeInOut(duration: 0.5).delay(0.2), value: showFullContact)
        }
        .padding(.bottom, 16)
    }
    
    // MARK: - Helper Computed Properties
    
    private var isClient: Bool {
        // Check if the role indicates this is a client
        if let teamMember = teamMember {
            return teamMember.role.lowercased() == "client"
        }
        return false
    }
    
    private var fullName: String {
        if let user = user {
            return "\(user.firstName) \(user.lastName)"
        } else if let teamMember = teamMember {
            return teamMember.fullName
        } else {
            return "Unknown User"
        }
    }
    
    private var initials: String {
        if let user = user {
            let firstInitial = user.firstName.first?.uppercased() ?? ""
            let lastInitial = user.lastName.first?.uppercased() ?? ""
            return "\(firstInitial)\(lastInitial)"
        } else if let teamMember = teamMember {
            return teamMember.initials
        } else {
            return "??"
        }
    }
    
    private var role: String {
        if let user = user {
            return user.role.displayName
        } else if let teamMember = teamMember {
            return teamMember.role
        } else {
            return "Unknown Role"
        }
    }
    
    private var email: String? {
        if let user = user {
            return user.email
        } else if let teamMember = teamMember {
            return teamMember.email
        } else {
            return nil
        }
    }
    
    private var phone: String? {
        if let user = user {
            return user.phone
        } else if let teamMember = teamMember {
            return teamMember.phone
        } else {
            return nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Format phone number for display (US format)
    private func formatPhoneNumber(_ phoneNumber: String) -> String {
        let cleaned = phoneNumber.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        
        // Format based on length
        if cleaned.count == 10 {
            let areaCode = cleaned.prefix(3)
            let prefix = cleaned.dropFirst(3).prefix(3)
            let number = cleaned.dropFirst(6)
            return "(\(areaCode)) \(prefix)-\(number)"
        } else if cleaned.count == 11 && cleaned.first == "1" {
            let countryCode = cleaned.prefix(1)
            let areaCode = cleaned.dropFirst().prefix(3)
            let prefix = cleaned.dropFirst(4).prefix(3)
            let number = cleaned.dropFirst(7)
            return "+\(countryCode) (\(areaCode)) \(prefix)-\(number)"
        }
        
        // If not a standard format, return as is with some basic formatting
        return phoneNumber
    }
    
    private func loadProfileImage() {
        // Already have an image
        if profileImage != nil {
            return
        }
        
        isLoadingImage = true
        
        // Check if we have a User with profile image data
        if let user = user, let imageData = user.profileImageData, let uiImage = UIImage(data: imageData) {
            self.profileImage = Image(uiImage: uiImage)
            isLoadingImage = false
            return
        }
        
        // Check if we have a User with a profile image URL
        if let user = user, let profileURL = user.profileImageURL, !profileURL.isEmpty {
            loadImageFromURL(profileURL)
            return
        }
        
        // Check if we have a TeamMember with an avatar URL
        if let teamMember = teamMember, let avatarURL = teamMember.avatarURL, !avatarURL.isEmpty {
            loadImageFromURL(avatarURL)
            return
        }
        
        // No image available
        isLoadingImage = false
    }
    
    private func loadImageFromURL(_ urlString: String) {
        // First check in-memory cache
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            self.profileImage = Image(uiImage: cachedImage)
            isLoadingImage = false
            return
        }
        
        // Check local file system cache
        if let image = ImageFileManager.shared.loadImage(localID: urlString) {
            self.profileImage = Image(uiImage: image)
            ImageCache.shared.set(image, forKey: urlString) // Add to memory cache
            isLoadingImage = false
            return
        }
        
        // Load from URL if not found in any cache
        Task {
            guard let url = URL(string: urlString) else {
                await MainActor.run {
                    isLoadingImage = false
                }
                return
            }
            
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let uiImage = UIImage(data: data) {
                    await MainActor.run {
                        self.profileImage = Image(uiImage: uiImage)
                        ImageCache.shared.set(uiImage, forKey: urlString)
                        // Save to file system for persistence
                        let _ = ImageFileManager.shared.saveImage(data: data, localID: urlString)
                        isLoadingImage = false
                    }
                }
            } catch {
                print("Failed to load team member profile image: \(error.localizedDescription)")
                await MainActor.run {
                    isLoadingImage = false
                }
            }
        }
    }
}

// MARK: - Preview

struct TeamMemberDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let user = User(id: "123", firstName: "John", lastName: "Doe", role: .fieldCrew, companyId: "company123")
        user.email = "john.doe@example.com"
        user.phone = "555-123-4567"
        
        let teamMember = TeamMember(
            id: "456",
            firstName: "Jane",
            lastName: "Smith",
            role: "Office Crew",
            avatarURL: nil,
            email: "jane.smith@example.com",
            phone: "555-987-6543"
        )
        
        return Group {
            TeamMemberDetailView(user: user, teamMember: nil)
                .preferredColorScheme(.dark)
            
            TeamMemberDetailView(user: nil, teamMember: teamMember)
                .preferredColorScheme(.dark)
        }
    }
}
