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
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: 44, height: 44)
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
                                
                                Image(systemName: "building.2.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                            
                            // Company name
                            Text(organization?.name ?? "Company Name")
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
                InfoItem(title: "Company Name", value: organization?.name ?? "Not available", icon: "building.2"),
                InfoItem(title: "Address", value: organization?.address ?? "Not available", icon: "location")
            ])
            
            // Contact info card
            infoCard(items: [
                InfoItem(title: "Phone", value: organization?.phone ?? "Not available", icon: "phone"),
                InfoItem(title: "Email", value: organization?.email ?? "Not available", icon: "envelope"),
                InfoItem(title: "Website", value: organization?.website ?? "Not available", icon: "globe")
            ])
        }
        .padding(.horizontal, 20)
    }
    
    private var teamSection: some View {
        VStack(spacing: 12) {
            if teamMembers.isEmpty {
                emptyTeamView
            } else {
                ForEach(teamMembers, id: \.id) { member in
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
            if member.isActive ?? true {
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
                let company = dataController.getCompany(id: companyID)
                let users = dataController.getTeamMembers(companyId: companyID)
                
                await MainActor.run {
                    self.organization = company
                    self.teamMembers = users
                    self.isLoading = false
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
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

#Preview {
    OrganizationSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
