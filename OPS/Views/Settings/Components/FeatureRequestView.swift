//
//  FeatureRequestView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI
import Combine
import UIKit

struct FeatureRequestView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var featureTitle = ""
    @State private var featureDescription = ""
    @State private var isSubmitting = false
    @State private var requestError: String? = nil
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header with back button
                SettingsHeader(
                    title: "Request a Feature",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Explanation
                        Text("Got an idea for OPS? Tell us what to build.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, OPSStyle.Layout.spacing4)
                            .padding(.top, OPSStyle.Layout.spacing3_5)
                        
                        // Form
                        VStack(spacing: OPSStyle.Layout.spacing3_5) {
                            // Feature title
                            // Use a standard styled text field since FormField might be causing issues
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("FEATURE TITLE")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                TextField("E.g. Team Chat, Calendar Export", text: $featureTitle)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .padding()
                                    .background(OPSStyle.Colors.surfaceInput)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                    )
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            
                            // Feature description
                            // Use a standard styled text editor since FormTextEditor might be causing issues
                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("DESCRIPTION")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ZStack(alignment: .topLeading) {
                                    TextEditor(text: $featureDescription)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                        .scrollContentBackground(.hidden)
                                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                                        .padding(.vertical, OPSStyle.Layout.spacing2)
                                        .frame(minHeight: 150)

                                    if featureDescription.isEmpty {
                                        Text("Please describe the feature you'd like to see and how it would help you...")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                                            .padding(.vertical, OPSStyle.Layout.spacing3)
                                            .allowsHitTesting(false)
                                    }
                                }
                                .background(OPSStyle.Colors.surfaceInput)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            
                            // Submit button
                            Button(action: submitFeatureRequest) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(OPSStyle.Colors.invertedText)
                                    } else {
                                        Text("SUBMIT REQUEST")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, OPSStyle.Layout.spacing3)
                                .background(
                                    (featureTitle.isEmpty || featureDescription.isEmpty || isSubmitting)
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.5)
                                    : OPSStyle.Colors.primaryAccent
                                )
                                .foregroundColor(OPSStyle.Colors.invertedText)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .disabled(featureTitle.isEmpty || featureDescription.isEmpty || isSubmitting)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .errorToast($requestError, label: Feedback.Err.requestFailed)
    }
    
    private func submitFeatureRequest() {
        guard !featureTitle.isEmpty, !featureDescription.isEmpty else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Use the API service to submit the feature request
                try await submitFeatureRequestToAPI()

                await MainActor.run {
                    isSubmitting = false
                    ToastCenter.shared.present(Feedback.Settings.requestSubmitted)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSubmitting = false
                    requestError = error.localizedDescription
                }
            }
        }
    }
    
    private func submitFeatureRequestToAPI() async throws {
        guard let user = dataController.currentUser else {
            throw NSError(domain: "FeatureRequestView", code: 1,
                         userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }

        let userId = user.id
        let companyId = user.companyId ?? ""
        let userEmail = user.email ?? ""
        let userName = user.fullName

        try await SupabaseService.shared.client
            .rpc("submit_feature_request", params: [
                "p_user_id": userId,
                "p_company_id": companyId,
                "p_type": "feature",
                "p_title": featureTitle,
                "p_description": featureDescription,
                "p_platform": "iOS mobile",
                "p_user_email": userEmail,
                "p_user_name": userName,
                "p_app_version": AppConfiguration.AppInfo.version
            ])
            .execute()
    }
}

// Placeholder extension no longer needed as we're using standardized components


#Preview {
    FeatureRequestView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
