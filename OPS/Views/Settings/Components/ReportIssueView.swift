//
//  ReportIssueView.swift
//  OPS
//
//  View for reporting bugs and issues
//

import SwiftUI
import Combine
import UIKit

struct ReportIssueView: View {
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var issueTitle = ""
    @State private var issueDescription = ""
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
                    title: "Report an Issue",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Explanation
                        Text("Experiencing an issue? Let us know so we can fix it.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .padding(.top, 20)
                        
                        // Form
                        VStack(spacing: 20) {
                            // Issue title
                            VStack(alignment: .leading, spacing: 8) {
                                Text("ISSUE TITLE")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                TextField("E.g. App crashes when uploading photos", text: $issueTitle)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                            }
                            .padding(.horizontal, 20)
                            
                            // Issue description
                            VStack(alignment: .leading, spacing: 8) {
                                Text("DESCRIPTION")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                
                                ZStack(alignment: .topLeading) {
                                    ZStack {
                                        OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        
                                        TextEditor(text: $issueDescription)
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(.white)
                                            .background(Color.clear)
                                            .cornerRadius(12)
                                    }
                                    .frame(height: 150)
                                    .padding(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                    )
                                    
                                    
                                    if issueDescription.isEmpty {
                                        Text("Please describe the issue you're experiencing, including steps to reproduce if possible...")
                                            .font(OPSStyle.Typography.body)
                                            .foregroundColor(OPSStyle.Colors.tertiaryText.opacity(0.6))
                                            .padding(.horizontal, 16)
                                            .padding(.vertical, 16)
                                            .allowsHitTesting(false)
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            
                            // Submit button
                            Button(action: submitIssueReport) {
                                HStack {
                                    if isSubmitting {
                                        ProgressView()
                                            .tint(.black)
                                    } else {
                                        Text("SUBMIT REPORT")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    (issueTitle.isEmpty || issueDescription.isEmpty || isSubmitting)
                                    ? OPSStyle.Colors.primaryAccent.opacity(0.5)
                                    : OPSStyle.Colors.primaryAccent
                                )
                                .foregroundColor(.black)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .disabled(issueTitle.isEmpty || issueDescription.isEmpty || isSubmitting)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                        }
                        
                        Spacer()
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .alert("Report Submitted", isPresented: $showSuccessAlert) {
            Button("OK") {
                dismiss()
            }
        } message: {
            Text("Thank you for reporting this issue! We'll investigate and work on a fix.")
        }
        .alert("Error", isPresented: $showErrorAlert) {
            Button("Try Again") { }
        } message: {
            Text(errorMessage ?? "An error occurred while submitting your report. Please try again.")
        }
    }
    
    private func submitIssueReport() {
        guard !issueTitle.isEmpty, !issueDescription.isEmpty else { return }
        
        isSubmitting = true
        
        Task {
            do {
                // Use the API service to submit the issue report
                try await submitIssueReportToAPI()
                
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
    
    private func submitIssueReportToAPI() async throws {
        // Get the current user ID
        guard let userId = dataController.currentUser?.id else {
            throw NSError(domain: "ReportIssueView", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Create parameters - using same endpoint but with isBug = true
        let parameters: [String: Any] = [
            "feature_title": issueTitle,
            "feature_description": issueDescription,
            "user": userId,
            "platform": "iOS mobile",
            "isBug": true // This is a bug report, not a feature request
        ]
        
        // Create JSON body
        let jsonData = try JSONSerialization.data(withJSONObject: parameters)
        
        // Create URL - using same endpoint as feature requests
        let endpoint = "api/1.1/wf/request_feature"
        var request = URLRequest(url: AppConfiguration.bubbleBaseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.httpBody = jsonData
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Execute request
        let (_, response) = try await URLSession.shared.data(for: request)
        
        // Check response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NSError(domain: "ReportIssueView", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Invalid response"])
        }
        
        // Check status code
        guard (200...299).contains(httpResponse.statusCode) else {
            throw NSError(domain: "ReportIssueView", code: 3,
                         userInfo: [NSLocalizedDescriptionKey: "Request failed with status code \(httpResponse.statusCode)"])
        }
    }
}

#Preview {
    ReportIssueView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
