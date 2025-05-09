//
//  OrganizationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation
import SwiftData
import SwiftUI
// Import team member components

struct OrganizationSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var organization: Company?
    @State private var teamMembers: [User] = []
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
            .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Header area with back button and title
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundColor(.white)
                        }
                        .frame(width: 44, height: 44)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(12)
                        
                        Spacer()
                        
                        Text("Organization")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                        
                        Spacer()
                        
                        // Empty spacer to balance the header
                        Spacer()
                            .frame(width: 44)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    if isLoading {
                        loadingView
                    } else {
                        // Company logo and name
                        VStack(spacing: 16) {
                            // Company logo/icon
                            ZStack {
                                Circle()
                                    .fill(OPSStyle.Colors.primaryAccent.opacity(0.2))
                                    .frame(width: 80, height: 80)
                                
                                if let organization = organization, 
                                   let logoURL = organization.logoURL, 
                                   !logoURL.isEmpty {
                                    if let cachedImage = ImageCache.shared.get(forKey: logoURL) {
                                        // Show cached company logo
                                        Image(uiImage: cachedImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(Circle())
                                    } else {
                                        // Logo URL exists but image not loaded yet
                                        // Show loading placeholder
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                            .scaleEffect(1.2)
                                            .onAppear {
                                                // Trigger image loading
                                                Task {
                                                    _ = await loadImage(from: logoURL)
                                                }
                                            }
                                    }
                                } else {
                                    // Default icon
                                    Image(systemName: "building.2.fill")
                                        .font(.system(size: 30))
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            // Company name
                            Text(organization?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? organization!.name : "Company Name")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                        .padding(.vertical, 16)
                        
                        // Organization info section
                        sectionHeader("ORGANIZATION DETAILS")
                        organizationSection
                        
                        // Team section
                        sectionHeader("TEAM MEMBERS")
                        teamSection
                    }
                }
                .padding(.bottom, 40)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadOrganizationData()
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .bold))
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 8)
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.8)
            
            Text("Loading organization data...")
                .font(.system(size: 16))
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .padding()
    }
    
    private var organizationSection: some View {
        VStack(spacing: 16) {
            // Company info card
            infoCard(items: [
                InfoItem(title: "Company Name", 
                         value: organization?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.name : "Not available", 
                         icon: "building.2"),
                InfoItem(title: "Description", 
                         value: organization?.companyDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.companyDescription! : "Not available", 
                         icon: "doc.text"),
                InfoItem(title: "Address", 
                         value: organization?.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.address! : "Not available", 
                         icon: "location")
            ])
            
            // Contact info card
            infoCard(items: [
                InfoItem(title: "Business Hours", 
                         value: (organization?.openHour != nil && organization?.closeHour != nil) ? 
                                organization!.hoursDisplay : "Not available", 
                         icon: "clock"),
                InfoItem(title: "Phone", 
                         value: organization?.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.phone! : "Not available", 
                         icon: "phone"),
                InfoItem(title: "Email", 
                         value: organization?.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.email! : "Not available", 
                         icon: "envelope"),
                InfoItem(title: "Website", 
                         value: organization?.website?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? 
                                organization!.website! : "Not available", 
                         icon: "globe")
            ])
        }
        .padding(.horizontal, 20)
    }
    
    private var teamSection: some View {
        VStack(spacing: 12) {
            if let company = organization {
                // Use the new compact team view with sheets for details
                OrganizationTeamView(company: company)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
            } else if teamMembers.isEmpty {
                emptyTeamView
            } else {
                // Fallback to old view if we have teamMembers but no company
                // Use an enumerated array to ensure uniqueness even if duplicate IDs exist
                ForEach(Array(zip(teamMembers.indices, teamMembers)), id: \.0) { index, member in
                    memberRow(member: member)
                }
            }
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyTeamView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.3")
                .font(.system(size: 36))
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.6))
            
            Text("No team members found")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.white)
            
            Text("Team members will appear here when added to your organization")
                .font(.system(size: 14))
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func infoCard(items: [InfoItem]) -> some View {
        VStack(spacing: 20) {
            ForEach(items, id: \.title) { item in
                HStack(spacing: 16) {
                    // Icon
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(width: 36, height: 36)
                        
                        Image(systemName: item.icon)
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.system(size: 14))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(item.value)
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(20)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func memberRow(member: User) -> some View {
        HStack(spacing: 16) {
            // User avatar
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 48, height: 48)
                
                Text(String(member.fullName.prefix(1)))
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                
                Text(member.role.displayName)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Status badge - active/inactive
            if member.isActive != false { // Show as active unless explicitly set to false
                Text("Active")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.successStatus)
                    .cornerRadius(12)
            } else {
                Text("Inactive")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.inactiveStatus)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(12)
    }
    
    private func loadOrganizationData() {
        isLoading = true
        
        Task {
            // Fetch organization data
            if let companyID = dataController.currentUser?.companyId {
                print("Loading organization data for company ID: \(companyID)")
                
                // Attempt to fetch fresh data from API if we're online
                if dataController.isConnected {
                    do {
                        // Try to force a refresh of company data from the API
                        try await dataController.forceRefreshCompany(id: companyID)
                        print("Successfully refreshed company data from API")
                        
                        // Sync company team members if we're online
                        if let company = dataController.getCompany(id: companyID) {
                            await dataController.syncManager?.syncCompanyTeamMembers(company)
                            print("Triggered team member sync")
                        }
                    } catch {
                        print("Failed to refresh company data from API: \(error.localizedDescription)")
                        // Continue with local data even if API refresh fails
                    }
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
                    
                    // Debug info
                    if let org = self.organization {
                        print("Organization set: \(org.name)")
                        print("Address: \(org.address ?? "nil")")
                        print("Email: \(org.email ?? "nil")")
                        print("Logo URL: \(org.logoURL ?? "nil")")
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
