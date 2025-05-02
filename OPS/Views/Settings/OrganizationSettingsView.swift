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
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    // Header
                    HStack {
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "arrow.left")
                                .font(.system(size: 20))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Text("Organization")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                    }
                    .padding()
                    
                    if isLoading {
                        loadingView
                    } else {
                        // Organization info section
                        organizationSection
                        
                        // Team section
                        teamSection
                    }
                }
                .padding(.bottom, OPSStyle.Layout.spacing4)
            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadOrganizationData()
        }
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.5)
            
            Text("Loading organization data...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    private var organizationSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("ORGANIZATION DETAILS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal)
            
            VStack(spacing: OPSStyle.Layout.spacing3) {
                infoRow(title: "Company Name", value: organization?.name ?? "Not available")
                infoRow(title: "Address", value: organization?.address ?? "Not available")
                infoRow(title: "Phone", value: organization?.phone ?? "Not available")
                infoRow(title: "Email", value: organization?.email ?? "Not available")
                infoRow(title: "Website", value: organization?.website ?? "Not available")
            }
            .padding()
            .background(OPSStyle.Colors.cardBackground.opacity(0.3))
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal)
        }
    }
    
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal)
                .padding(.top, OPSStyle.Layout.spacing3)
            
            if teamMembers.isEmpty {
                Text("No team members found")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(OPSStyle.Colors.cardBackground.opacity(0.3))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal)
            } else {
                ForEach(teamMembers, id: \.id) { member in
                    memberRow(member: member)
                }
            }
        }
    }
    
    private func infoRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    
    private func memberRow(member: User) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // User avatar
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: 40, height: 40)
                .overlay(
                    Text(String(member.fullName.prefix(1)))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(member.role.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Status badge - active/inactive
            if member.isActive ?? true {
                Text("Active")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green)
                    .cornerRadius(12)
            } else {
                Text("Inactive")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray)
                    .cornerRadius(12)
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackground.opacity(0.3))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
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

#Preview {
    OrganizationSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
