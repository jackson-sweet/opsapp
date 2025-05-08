//
//  CompanyCodeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import SwiftUI
import Combine
import SwiftData
import Foundation

struct CompanyCodeView: View {
    @ObservedObject var viewModel: OnboardingViewModel
    
    // Determine if we're in V2 flow
    private var isInV2Flow: Bool {
        return AppConfiguration.UX.useConsolidatedOnboardingFlow
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Navigation with back button for V2 flow
                if isInV2Flow {
                    HStack {
                        Button(action: {
                            viewModel.moveToPreviousStepV2()
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .medium))
                                Text("Back")
                                    .font(.system(size: 16, weight: .medium))
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        
                        Spacer()
                        
                        Text("Step 3 of 6")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color.gray)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 8)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    
                    // Step indicator bars
                    HStack(spacing: 4) {
                        ForEach(0..<6) { step in
                            Rectangle()
                                .fill(step <= 2 ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.4))
                                .frame(height: 4)
                        }
                    }
                    .padding(.bottom, 16)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                
                VStack(spacing: 24) {
                    // Header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter company")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("code.")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.bottom, 12)
                        
                        Text("Your company code connects your account to your organization.")
                            .font(.system(size: 16))
                            .foregroundColor(Color.gray)
                            .lineSpacing(4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 10)
                    
                    // Company code input
                    VStack(alignment: .leading, spacing: 8) {
                        InputFieldLabel(label: "COMPANY CODE")
                        
                        //DO NOT FORCE CAPITALIZATION
                        TextField("Enter code", text: $viewModel.companyCode)
                            .font(.system(size: 16))
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                            .onboardingTextFieldStyle()
                            .transition(.opacity)
                            .animation(.easeInOut, value: viewModel.companyCode)
                    }
                    
                    // Code explanation with icon
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.white.opacity(0.7))
                            .font(.system(size: 14))
                        
                        Text("Obtain your company code from your manager, in your organization's settings.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.6))
                    }
                    .padding(.top, 8)
                    
                    // Error message
                    ErrorMessageView(message: viewModel.errorMessage)
                    
                    Spacer()
                    
                    // Buttons
                    OnboardingNavigationButtons(
                        primaryText: "Continue",
                        secondaryText: "Need Help?",
                        isLoading: viewModel.isLoading,
                        onPrimaryTapped: {
                            print("CompanyCodeView: Continue button tapped with code: \(viewModel.companyCode)")
                            
                            // Set loading state
                            viewModel.isLoading = true
                            viewModel.errorMessage = ""
                            
                            // Call the API to join company with all user info
                            Task {
                                // Since we updated joinCompany() to handle errors internally,
                                // we don't need try/catch here anymore
                                let success = await viewModel.joinCompany()
                                
                                await MainActor.run {
                                    viewModel.isLoading = false
                                    
                                    if success {
                                        print("Company join successful! Company: \(viewModel.companyName)")
                                        // Store the fact that the user has successfully joined a company
                                        UserDefaults.standard.set(true, forKey: "has_joined_company")
                                        
                                        // Create company record in SwiftData for immediate access
                                        let companyIdValue = UserDefaults.standard.string(forKey: "company_id") ?? ""
                                        let companyNameValue = UserDefaults.standard.string(forKey: "Company Name") ?? "Your Company"
                                        
                                        if !companyIdValue.isEmpty,
                                           let dataController = viewModel.dataController,
                                           let modelContext = dataController.modelContext {
                                            
                                            print("Creating FetchDescriptor for company with ID: \(companyIdValue)")
                                            // Check if company already exists
                                            let descriptor = FetchDescriptor<Company>(
                                                predicate: #Predicate<Company> { $0.id == companyIdValue }
                                            )
                                            print("FetchDescriptor created successfully")
                                            if let companies = try? modelContext.fetch(descriptor), companies.isEmpty {
                                                // Create new company record
                                                let company = Company(id: companyIdValue, name: companyNameValue)
                                                
                                                // Add any additional info from API if available
                                                if viewModel.companyName.isEmpty == false {
                                                    company.name = viewModel.companyName
                                                }
                                                
                                                modelContext.insert(company)
                                                try? modelContext.save()
                                                print("Company data created in database: \(company.name)")
                                            }
                                        }
                                        
                                        // Continue to next step based on flow
                                        if isInV2Flow {
                                            viewModel.moveToNextStepV2()
                                        } else {
                                            viewModel.moveToNextStep()
                                        }
                                    } else {
                                        // Error message is already set by the joinCompany method
                                        print("Company join failed: \(viewModel.errorMessage)")
                                        
                                        // Make sure error message is user-friendly
                                        if viewModel.errorMessage.isEmpty {
                                            viewModel.errorMessage = "Invalid company code. Please check and try again."
                                        }
                                        
                                        // Ensure user cannot skip company joining
                                        UserDefaults.standard.set(false, forKey: "has_joined_company")
                                    }
                                }
                            }
                        },
                        onSecondaryTapped: {
                            print("CompanyCodeView: Can't skip company code button tapped")
                            
                            // Show alert that company code is required
                            viewModel.errorMessage = "A valid company code is required to use the OPS app. Please contact your organization administrator for your code."
                            
                            // Ensure user cannot skip company joining
                            UserDefaults.standard.set(false, forKey: "has_joined_company")
                        }
                    )
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 30)
                
                // Loading overlay
                if viewModel.isLoading {
                    LoadingView(message: "Verifying...")
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Company Code Screen") {
    let viewModel = OnboardingViewModel()
    viewModel.email = "user@example.com"
    viewModel.password = "password123"
    viewModel.firstName = "John"
    viewModel.lastName = "Doe"
    viewModel.phoneNumber = "5551234567"
    viewModel.companyCode = "DEMO123"
    
    return CompanyCodeView(viewModel: viewModel)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
}
