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
    @State private var showFullContact = false // For animating contact display
    
    // Constants for styling
    private let avatarSize: CGFloat = 80
    private let contactIconSize: CGFloat = 36
    
    var body: some View {
        NavigationStack {
            ZStack {
                // Background
                OPSStyle.Colors.background
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 12) {
                        // Profile header with avatar - larger and more prominent
                        profileHeader
                            .padding(.top, 24)
                        
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
                    .padding(.top, 8)
                }
                
                ToolbarItem(placement: .principal) {
                    Text(isClient ? "CLIENT" : "TEAM MEMBER")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                        .padding(.top, 12)
                }
            }
            .onAppear {
                // Animate contact info appearing
                withAnimation(.easeInOut.delay(0.3)) {
                    showFullContact = true
                }
            }
        }
    }
    
    // MARK: - Profile Header
    
    private var profileHeader: some View {
        HStack(spacing: 36) {
            // Profile image - using unified UserAvatar component
            Group {
                if let user = user {
                    UserAvatar(user: user, size: avatarSize)
                } else if let teamMember = teamMember {
                    UserAvatar(teamMember: teamMember, size: avatarSize)
                } else {
                    UserAvatar(firstName: "", lastName: "", size: avatarSize)
                }
            }
            .overlay(
                Circle()
                    .stroke(OPSStyle.Colors.primaryText, lineWidth: 3)
            )
            
            // Name and role on one row
            VStack(alignment: .leading, spacing: 8) {
                Text(fullName.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(role)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 32)
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
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Call")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
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
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Message")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
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
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        
                        Text("Email")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    .frame(width: 70, height: 70)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
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
            print("🔍 TeamMemberDetailView: Getting phone from User object")
            print("   - User: \(user.fullName)")
            print("   - Phone: \(user.phone ?? "nil")")
            return user.phone
        } else if let teamMember = teamMember {
            print("🔍 TeamMemberDetailView: Getting phone from TeamMember object")
            print("   - TeamMember: \(teamMember.fullName)")
            print("   - Phone: \(teamMember.phone ?? "nil")")
            return teamMember.phone
        } else {
            print("🔍 TeamMemberDetailView: No user or teamMember provided")
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
