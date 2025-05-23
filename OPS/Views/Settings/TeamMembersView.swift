//
//  TeamMembersView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI
import SwiftData

struct TeamMembersView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.openURL) private var openURL
    
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var teamMembers: [User] = []
    @State private var selectedMember: User? = nil
    
    var filteredMembers: [User] {
        if searchText.isEmpty { return teamMembers }
        
        return teamMembers.filter { member in
            return member.fullName.localizedCaseInsensitiveContains(searchText) ||
                   member.email?.localizedCaseInsensitiveContains(searchText) ?? false ||
                   member.role.rawValue.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Team Members",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    TextField("Search team members", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(.white)
                        .autocorrectionDisabled()
                    
                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(12)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                if isLoading {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(1.5)
                        .padding()
                    Spacer()
                } else if teamMembers.isEmpty {
                    emptyStateView
                } else {
                    // Team members list
                    ScrollView {
                        VStack(spacing: 16) {
                            SettingsSectionHeader(title: "TEAM MEMBERS")
                            
                            if filteredMembers.isEmpty && !searchText.isEmpty {
                                Text("No team members match '\(searchText)'")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .padding(.top, 24)
                                    .frame(maxWidth: .infinity)
                            } else {
                                ForEach(filteredMembers) { member in
                                    memberCard(member)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadTeamMembers()
        }
        .sheet(item: $selectedMember) { member in
            memberDetailSheet(member)
        }
    }
    
    // MARK: - Component Views
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.3.sequence.fill")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, 40)
            
            Text("No Team Members")
                .font(OPSStyle.Typography.title)
                .foregroundColor(.white)
            
            Text("There are no team members in your organization yet.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            
            Spacer()
        }
        .padding()
    }
    
    private func memberCard(_ member: User) -> some View {
        Button(action: {
            selectedMember = member
        }) {
            HStack(spacing: 16) {
                // Member avatar
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.primaryAccent)
                        .frame(width: 50, height: 50)
                    
                    Text(String(member.firstName.prefix(1) + member.lastName.prefix(1)))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                }
                
                // Member details
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(member.firstName) \(member.lastName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    Text(member.role.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    if let email = member.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
                
                // Status indicator
                if member.isActive != false {
                    Circle()
                        .fill(OPSStyle.Colors.successStatus)
                        .frame(width: 10, height: 10)
                }
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(12)
            .padding(.horizontal, 20)
        }
    }
    
    
    private func memberDetailSheet(_ member: User) -> some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header with dismiss button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        selectedMember = nil
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.trailing, 20)
                    .padding(.top, 20)
                }
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Member profile section
                        VStack(alignment: .center, spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.primaryAccent)
                                    .frame(width: 100, height: 100)
                                
                                Text(String(member.firstName.prefix(1) + member.lastName.prefix(1)))
                                    .font(OPSStyle.Typography.title)
                                    .foregroundColor(.white)
                            }
                            .padding(.bottom, 8)
                            
                            Text("\(member.firstName) \(member.lastName)")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text(member.role.displayName)
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 12)
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(12)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        
                        // Contact actions
                        VStack(spacing: 16) {
                            // Email button
                            if let email = member.email, !email.isEmpty {
                                Button(action: {
                                    if let url = URL(string: "mailto:\(email)") {
                                        openURL(url)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "envelope")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.black)
                                        
                                        Text("Send Email")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.black)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(12)
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Phone button
                            if let phone = member.phone, !phone.isEmpty {
                                Button(action: {
                                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                    if let url = URL(string: "tel:\(cleaned)") {
                                        openURL(url)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "phone")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                        
                                        Text("Call")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 20)
                                
                                // Text button
                                Button(action: {
                                    let cleaned = phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
                                    if let url = URL(string: "sms:\(cleaned)") {
                                        openURL(url)
                                    }
                                }) {
                                    HStack {
                                        Image(systemName: "message")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                        
                                        Text("Send Text")
                                            .font(OPSStyle.Typography.bodyBold)
                                            .foregroundColor(.white)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        
                        // Member details
                        VStack(alignment: .leading, spacing: 16) {
                            Text("CONTACT DETAILS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.leading, 20)
                            
                            VStack(spacing: 16) {
                                // Email
                                HStack {
                                    Image(systemName: "envelope")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Email")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        
                                        Text(member.email ?? "Not provided")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(member.email?.isEmpty ?? true ? OPSStyle.Colors.secondaryText : .white)
                                    }
                                    
                                    Spacer()
                                }
                                
                                // Phone
                                HStack {
                                    Image(systemName: "phone")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                        .frame(width: 24)
                                    
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Phone")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        
                                        Text(member.phone ?? "Not provided")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(member.phone?.isEmpty ?? true ? OPSStyle.Colors.secondaryText : .white)
                                    }
                                    
                                    Spacer()
                                }
                            }
                            .padding()
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(12)
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 32)
                    }
                    .padding(.top, 16)
                }
            }
        }
    }
    
    // MARK: - Data Loading
    
    private func loadTeamMembers() {
        isLoading = true
        
        Task {
            // Load team members from data controller
            if let companyId = dataController.currentUser?.companyId {
                let members = dataController.getTeamMembers(companyId: companyId)
                
                await MainActor.run {
                    self.teamMembers = members
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.teamMembers = []
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    TeamMembersView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}