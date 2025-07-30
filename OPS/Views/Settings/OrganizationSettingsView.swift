//
//  OrganizationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation
import SwiftData
import SwiftUI

struct OrganizationSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var organization: Company?
    @State private var teamMembers: [User] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header area - fixed, not part of scroll view
                SettingsHeader(
                    title: "Organization",
                    onBackTapped: {
                        dismiss()
                    }
                )
                .padding(.bottom, 8)
                .overlay(
                    // Refresh indicator in top right
                    Group {
                        if isRefreshing {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                    .scaleEffect(0.8)
                                Text("Updating...")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.trailing, 20)
                        }
                    },
                    alignment: .trailing
                )
                
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    
                        if isLoading {
                            loadingView
                        } else {
                            // Company header - no card background, matches ProfileSettingsView style
                            if let company = organization {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(alignment: .top, spacing: 16) {
                                        // Company logo - using unified CompanyAvatar component
                                        CompanyAvatar(company: company, size: 60)
                                        
                                        VStack(alignment: .leading, spacing: 6) {
                                            // Company name
                                            Text(company.name)
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(.white)
                                            
                                            // Company description - always show
                                            Text((company.companyDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                                 company.companyDescription! : "NO DESCRIPTION")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor((company.companyDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                                                OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                                                .lineLimit(2)
                                            
                                            // Company address - always show
                                            Text((company.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                                 company.address! : "NO ADDRESS")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor((company.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                                                OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                                        }
                                        
                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Organization details section
                            VStack(spacing: 24) {
                                SettingsSectionHeader(title: "CONTACT INFORMATION")
                                
                                // Business hours - always show
                                infoField(
                                    title: "Business Hours",
                                    value: (organization?.openHour != nil && organization?.closeHour != nil) ? 
                                           organization!.hoursDisplay : "NO BUSINESS HOURS",
                                    icon: "clock",
                                    isMissing: organization?.openHour == nil || organization?.closeHour == nil
                                )
                                
                                // Phone - always show
                                infoField(
                                    title: "Phone",
                                    value: (organization?.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.phone! : "NO PHONE NUMBER",
                                    icon: "phone",
                                    isMissing: organization?.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                                
                                // Email - always show
                                infoField(
                                    title: "Email",
                                    value: (organization?.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.email! : "NO EMAIL ADDRESS",
                                    icon: "envelope",
                                    isMissing: organization?.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                                
                                // Website - always show
                                infoField(
                                    title: "Website",
                                    value: (organization?.website?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.website! : "NO WEBSITE",
                                    icon: "globe",
                                    isMissing: organization?.website?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                            }
                            
                            // Team section
                            VStack(spacing: 16) {
                                SettingsSectionHeader(title: "TEAM MEMBERS")
                                
                                if let company = organization {
                                    // Use the new compact team view with sheets for details
                                    OrganizationTeamView(company: company)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .padding(.horizontal, 20)
                                } else if teamMembers.isEmpty {
                                    emptyTeamView
                                        .padding(.horizontal, 20)
                                } else {
                                    // Fallback to old view if we have teamMembers but no company
                                    ForEach(Array(zip(teamMembers.indices, teamMembers)), id: \.0) { index, member in
                                        memberRow(member: member)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 12)
                    .tabBarPadding() // Add padding for tab bar
                }

            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadOrganizationData()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.8)
            
            Text("Loading organization data...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .padding()
    }
    
    // Individual info field - matches ProfileSettingsView style
    private func infoField(title: String, value: String, icon: String, isMissing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isMissing ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                    .frame(width: 24)
                
                Text(value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isMissing ? OPSStyle.Colors.tertiaryText : .white)
                
                Spacer()
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyTeamView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Text("No team members found")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(.white)
            
            Text("Team members will appear here when added to your organization")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func memberRow(member: User) -> some View {
        HStack(spacing: 16) {
            // User avatar
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 48, height: 48)
                
                Text(String(member.fullName.prefix(1)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(member.role.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Status badge - active/inactive
            if member.isActive != false { // Show as active unless explicitly set to false
                Text("Active")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.successStatus)
                    .cornerRadius(12)
            } else {
                Text("Inactive")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.inactiveStatus)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func loadOrganizationData() {
        isLoading = true
        
        Task {
            // Fetch organization data
            if let companyID = dataController.currentUser?.companyId {
                
                // Always attempt to fetch fresh data from API when online
                // This ensures we have the latest company info including address, phone, email
                if dataController.isConnected {
                    // Show refresh indicator
                    await MainActor.run {
                        isRefreshing = true
                    }
                    
                    do {
                        // Force a refresh of company data from the API every time view opens
                        try await dataController.forceRefreshCompany(id: companyID)
                        
                        // Debug: Log what we got from the API
                        if let refreshedCompany = dataController.getCompany(id: companyID) {
                        }
                        
                        // Sync company team members if we're online
                        if let company = dataController.getCompany(id: companyID) {
                            await dataController.syncManager?.syncCompanyTeamMembers(company)
                        }
                        
                        // Also force sync projects when opening organization settings
                        // This ensures projects are loaded if they weren't during login
                        await dataController.syncManager?.forceSyncProjects()
                    } catch {
                        print("Failed to refresh company data from API: \(error.localizedDescription)")
                        // Continue with local data even if API refresh fails
                        await MainActor.run {
                            isRefreshing = false
                        }
                    }
                } else {
                }
                
                // Get company from local database (newly refreshed if the API call succeeded)
                let company = dataController.getCompany(id: companyID)
                let users = dataController.getTeamMembers(companyId: companyID)
                
                if let company = company {
                }
                
                // Load company logo if available
                if let company = company, let logoURL = company.logoURL, !logoURL.isEmpty {
                    
                    // Check if logo is already cached
                    if ImageCache.shared.get(forKey: logoURL) == nil {
                        // Not cached, load from URL
                        if await loadImage(from: logoURL) != nil {
                            // Image is now cached by the loadImage function
                        } else {
                            print("OrganizationSettingsView: Failed to load company logo")
                        }
                    } else {
                    }
                }
                
                await MainActor.run {
                    self.organization = company
                    self.teamMembers = users
                    self.isLoading = false
                    self.isRefreshing = false
                    
                    // Debug info
                    if let org = self.organization {
                    } else {
                    }
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadImage(from urlString: String) async -> UIImage? {
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            if let imageBase64 = UserDefaults.standard.string(forKey: urlString),
               let imageData = Data(base64Encoded: imageBase64),
               let image = UIImage(data: imageData) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
            return nil
        }
        
        // Handle remote URL
        var imageURL = urlString
        
        // Fix for URLs starting with //
        if imageURL.starts(with: "//") {
            imageURL = "https:" + imageURL
        }
        
        guard let url = URL(string: imageURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
        } catch {
            print("Failed to load image: \(error.localizedDescription)")
        }
        
        return nil
    }
}

// Helper struct for organization info items
struct InfoItem {
    let title: String
    let value: String
    let icon: String
}

#Preview {
    OrganizationSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
