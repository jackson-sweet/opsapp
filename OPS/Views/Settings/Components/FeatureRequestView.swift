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
    @State private var showSuccessAlert = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header with back button
                SettingsHeader(
                    title: "Request a Feature",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Explanation
                        Text("Have an idea for improving OPS? Let us know what feature you'd like to see!")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Feature title
                            // Use a standard styled text field since FormField might be causing issues
                            VStack(alignment: .leading, spacing: 8) {
                                Text("FEATURE TITLE")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                TextField("E.g. Team Chat, Calendar Export", text: $featureTitle)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                            }
                            .padding(.horizontal, 20)
                            
                            // Feature description
                            // Use a standard styled text editor since FormTextEditor might be causing issues
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DESCRIPTION")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ZStack(alignment: .topLeading) {
                                    // iOS 16 compatibility handling 
                                    ZStack {
                                        OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                            .cornerRadius(12)
                                        
                                        TextEditor(text: $featureDescription)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                            .background(Color.clear)
                                            .cornerRadius(12)
                                    }
                                    .frame(height: 150)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                    
                                    if featureDescription.isEmpty {
                                        Text("Please describe the feature you'd like to see and how it would help you...")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Submit button
                            Button(action: submitFeatureRequest) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("SUBMIT REQUEST")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    (featureTitle.isEmpty || featureDescription.isEmpty || isSubmitting)
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.5)
                                    : OPSStyle.Colors.primaryAccent
                                )
                                .foregroundColor(.black)
                                .cornerRadius(10)
                            }
                            .disabled(featureTitle.isEmpty || featureDescription.isEmpty || isSubmitting)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Request Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for your suggestion! We'll review your feature request.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("Try Again") { }
        } message: {
            Text(errorMessage ?? "An error occurred while submitting your request. Please try again.")
        }
    }
    
    private func submitFeatureRequest() {
        guard !featureTitle.isEmpty, !featureDescription.isEmpty else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Use the API service to submit the feature request
                try await submitFeatureRequestToAPI()
                
                // Handle success
                await MainActor.run {
                    isSubmitting = false
                    showSuccessAlert = true
                }
            } catch {
                // Handle error
                await MainActor.run {
                    isSubmitting = false
                    errorMessage = error.localizedDescription
                    showErrorAlert = true
                }
            }
        }
    }
    
    private func submitFeatureRequestToAPI() async throws {
        // Get the current user ID
        guard let userId = dataController.currentUser?.id else {
            throw NSError(domain: "FeatureRequestView", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Create parameters
        let parameters: [String: Any] = [
            "feature_title": featureTitle,
            "feature_description": featureDescription,
            "user": userId,
            "platform": "iOS mobile"
        ]
        
        // Create JSON body
        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        
        // Create URL
        let endpoint = "api/1.1/wf/request_feature"
        var request = URLRequest(url: AppConfiguration.bubbleBaseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Execute request
        let (_, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "FeatureRequestView", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Check status code
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "FeatureRequestView", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Request failed with status code \(httpResponse.statusCode)"])
        }
    }
}

// Placeholder extension no longer needed as we're using standardized components


#Preview {
    FeatureRequestView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}