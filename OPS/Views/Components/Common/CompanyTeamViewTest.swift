//
//  CompanyTeamViewTest.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-08.
//

import SwiftUI
import SwiftData

// We're explicitly using the CompanyTeamListView from the Common folder

struct CompanyTeamViewTest: View {
    @EnvironmentObject private var dataController: DataController
    @State private var company: Company?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Simple header
                Text("Team Members")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.top, 24)
                
                // Content
                ScrollView {
                    VStack(spacing: 20) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(1.5)
                                .padding(.top, 50)
                                .foregroundColor(.white)
                        } else if let company = company {
                            // First show company profile
                            VStack(alignment: .leading, spacing: 8) {
                                Text(company.name)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundColor(.white)
                                
                                if let address = company.address, !address.isEmpty {
                                    Text(address)
                                        .font(.system(size: 15))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                
                                if let phone = company.phone, !phone.isEmpty {
                                    Text("📞 \(phone)")
                                        .font(.system(size: 15))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                
                                if let email = company.email, !email.isEmpty {
                                    Text("📧 \(email)")
                                        .font(.system(size: 15))
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(12)
                            .padding(.horizontal)
                            
                            // Then show team members
                            CompanyTeamListView(company: company)
                                .padding(.horizontal)
                            
                            // Refresh button
                            Button {
                                refreshCompanyData()
                            } label: {
                                Label("Refresh Team Data", systemImage: "arrow.clockwise")
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .padding(.top, 16)
                        } else {
                            // Error state
                            VStack(spacing: 16) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: 40))
                                    .foregroundColor(OPSStyle.Colors.warningStatus)
                                
                                Text("No company data available")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                
                                Button("Reload Data") {
                                    loadCompanyData()
                                }
                                .padding()
                                .background(OPSStyle.Colors.primaryText)
                                .foregroundColor(.black)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .padding(.top, 50)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .onAppear {
            loadCompanyData()
        }
    }
    
    private func loadCompanyData() {
        isLoading = true
        
        Task {
            // Load company data
            if let companyId = dataController.currentUser?.companyId {
                self.company = dataController.getCompany(id: companyId)
                
                // Ensure team members are populated
                if let company = self.company, company.teamMembers.isEmpty || !company.teamMembersSynced {
                    await dataController.syncManager?.syncCompanyTeamMembers(company)
                    
                    // Refresh UI with new data
                    await MainActor.run {
                        self.company = dataController.getCompany(id: companyId)
                    }
                }
            }
            
            await MainActor.run {
                isLoading = false
            }
        }
    }
    
    private func refreshCompanyData() {
        Task {
            isLoading = true
            
            if let companyId = dataController.currentUser?.companyId {
                // Try to refresh company data from API
                do {
                    try await dataController.forceRefreshCompany(id: companyId)
                    print("✅ Successfully refreshed company data from API")
                } catch {
                    print("❌ Error refreshing company: \(error.localizedDescription)")
                }
                
                // Get the updated company
                let updatedCompany = dataController.getCompany(id: companyId)
                
                // Sync team members
                if let company = updatedCompany {
                    print("🔄 Starting team member sync with new constraints format...")
                    print("🔄 Company ID: \(company.id)")
                    
                    // Direct sync call for testing
                    await dataController.syncManager?.syncCompanyTeamMembers(company)
                    
                    print("✅ Team member sync completed")
                    print("✅ Team member count: \(company.teamMembers.count)")
                    
                    // Update UI with new data
                    await MainActor.run {
                        self.company = dataController.getCompany(id: companyId)
                        self.isLoading = false
                    }
                } else {
                    print("❌ No company found with ID: \(companyId)")
                    await MainActor.run {
                        self.isLoading = false
                    }
                }
            } else {
                print("❌ No company ID available in current user")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

#Preview {
    CompanyTeamViewTest()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
