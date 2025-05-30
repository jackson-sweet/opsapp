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
                                        // Company logo
                                        ZStack {
                                            if let logoURL = company.logoURL, 
                                                !logoURL.isEmpty,
                                               let cachedImage = ImageCache.shared.get(forKey: logoURL) {
                                                Image(uiImage: cachedImage)
                                                    .resizable()
                                                    .scaledToFill()
                                                    .frame(width: 60, height: 60)
                                                    .clipShape(Circle())
                                            } else {
                                                // Simple circle outline with icon - black and white
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 2)
                                                    .frame(width: 60, height: 60)
                                                    .background(Color.black)
                                                    .clipShape(Circle())
                                                
                                                Image(systemName: "building.2")
                                                    .font(OPSStyle.Typography.bodyBold)
                                                    .foregroundColor(.white)
                                            }
                                        }
                                        
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
                }
                .tabBarPadding()
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
                print("Loading organization data for company ID: \(companyID)")
                
                // Always attempt to fetch fresh data from API when online
                // This ensures we have the latest company info including address, phone, email
                if dataController.isConnected {
                    // Show refresh indicator
                    await MainActor.run {
                        isRefreshing = true
                    }
                    
                    do {
                        // Force a refresh of company data from the API every time view opens
                        print("OrganizationSettingsView: Fetching latest company data from API...")
                        try await dataController.forceRefreshCompany(id: companyID)
                        print("Successfully refreshed company data from API")
                        
                        // Debug: Log what we got from the API
                        if let refreshedCompany = dataController.getCompany(id: companyID) {
                            print("Company data after refresh:")
                            print("  - Name: \(refreshedCompany.name)")
                            print("  - Address: \(refreshedCompany.address ?? "nil")")
                            print("  - Phone: \(refreshedCompany.phone ?? "nil")")
                            print("  - Email: \(refreshedCompany.email ?? "nil")")
                        }
                        
                        // Sync company team members if we're online
                        if let company = dataController.getCompany(id: companyID) {
                            await dataController.syncManager?.syncCompanyTeamMembers(company)
                            print("Triggered team member sync")
                        }
                    } catch {
                        print("Failed to refresh company data from API: \(error.localizedDescription)")
                        // Continue with local data even if API refresh fails
                        await MainActor.run {
                            isRefreshing = false
                        }
                    }
                } else {
                    print("OrganizationSettingsView: Offline - using cached company data")
                }
                
                // Get company from local database (newly refreshed if the API call succeeded)
                let company = dataController.getCompany(id: companyID)
                let users = dataController.getTeamMembers(companyId: companyID)
                
                print("Loaded company: \(company?.name ?? "nil")")
                print("Company logo URL: \(company?.logoURL ?? "nil")")
                if let company = company {
                    print("Team members count: \(company.teamMembers.count)")
                }
                
                // Load company logo if available
                if let company = company, let logoURL = company.logoURL, !logoURL.isEmpty {
                    print("Attempting to load logo from URL: \(logoURL)")
                    
                    // Check if logo is already cached
                    if ImageCache.shared.get(forKey: logoURL) == nil {
                        // Not cached, load from URL
                        print("Logo not cached, loading from URL...")
                        if await loadImage(from: logoURL) != nil {
                            print("OrganizationSettingsView: Successfully loaded company logo")
                            // Image is now cached by the loadImage function
                        } else {
                            print("OrganizationSettingsView: Failed to load company logo")
                        }
                    } else {
                        print("Using cached logo image")
                    }
                }
                
                await MainActor.run {
                    self.organization = company
                    self.teamMembers = users
                    self.isLoading = false
                    self.isRefreshing = false
                    
                    // Debug info
                    if let org = self.organization {
                        print("Organization set: \(org.name)")
                        print("Address: \(org.address ?? "nil")")
                        print("Phone: \(org.phone ?? "nil")")
                        print("Email: \(org.email ?? "nil")")
                        print("Logo URL: \(org.logoURL ?? "nil")")
                        print("Open Hour: \(org.openHour ?? "nil")")
                        print("Close Hour: \(org.closeHour ?? "nil")")
                        print("Team members count: \(org.teamMembers.count)")
                    } else {
                        print("Organization is nil after loading!")
                    }
                }
            } else {
                print("No company ID found for current user")
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