//
//  TeamMemberDetailView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI

/// Detail view for a team member, shown in a sheet
struct TeamMemberDetailView: View {
    // Can accept either a User or TeamMember
    let user: User?
    let teamMember: TeamMember?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var profileImage: Image?
    @State private var isLoadingImage = false
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Profile header with avatar
                        profileHeader
                        
                        // Contact information
                        contactSection
                        
                        // Project history or role information
                        roleSection
                        
                        // Spacer for bottom padding
                        Spacer(minLength: 40)
                    }
                    .padding()
                }
            }
            .navigationTitle("Team Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadProfileImage()
            }
        }
    }
    
    private var profileHeader: some View {
        VStack(spacing: 16) {
            // Profile image
            ZStack {
                if let profileImage = profileImage {
                    profileImage
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipShape(Circle())
                        .shadow(color: Color.black.opacity(0.2), radius: 4)
                } else {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                        .frame(width: 120, height: 120)
                        .shadow(color: Color.black.opacity(0.2), radius: 4)
                    
                    Text(initials)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            
            // Name and role
            VStack(spacing: 4) {
                Text(fullName)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                
                Text(role)
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
    
    private var contactSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text("CONTACT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            // Contact cards
            VStack(spacing: 2) {
                // Email
                if let email = self.email, !email.isEmpty {
                    Button(action: {
                        if let emailURL = URL(string: "mailto:\(email)") {
                            openURL(emailURL)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "envelope.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24, height: 24)
                            
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
                                .font(.system(size: 14))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                // Phone
                if let phone = self.phone, !phone.isEmpty {
                    Button(action: {
                        let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                        if let phoneURL = URL(string: "tel:\(cleaned)") {
                            openURL(phoneURL)
                        }
                    }) {
                        HStack(spacing: 12) {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 18))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(width: 24, height: 24)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Phone")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                Text(phone)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "chevron.right")
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .font(.system(size: 14))
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
    
    private var roleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section title
            Text("ROLE INFORMATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.bottom, 4)
            
            // Role info card
            HStack(spacing: 12) {
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 18))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 24, height: 24)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Employee Type")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(role)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
    
    // MARK: - Helper Computed Properties
    
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
    
    private func loadProfileImage() {
        // Already have an image
        if profileImage != nil {
            return
        }
        
        // User with image data
        if let user = user, let imageData = user.profileImageData, let uiImage = UIImage(data: imageData) {
            self.profileImage = Image(uiImage: uiImage)
            return
        }
        
        // TeamMember with avatar URL
        if let teamMember = teamMember, let avatarURL = teamMember.avatarURL, !avatarURL.isEmpty {
            isLoadingImage = true
            
            // First check cache
            if let cachedImage = ImageCache.shared.get(forKey: avatarURL) {
                self.profileImage = Image(uiImage: cachedImage)
                isLoadingImage = false
                return
            }
            
            // Load from URL
            Task {
                guard let url = URL(string: avatarURL) else {
                    isLoadingImage = false
                    return
                }
                
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    if let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            self.profileImage = Image(uiImage: uiImage)
                            ImageCache.shared.set(uiImage, forKey: avatarURL)
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
}

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