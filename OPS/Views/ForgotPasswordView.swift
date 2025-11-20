//
//  ForgotPasswordView.swift
//  OPS
//
//  Created by Assistant on 2025-05-28.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Binding var isPresented: Bool
    @Binding var prefilledEmail: String
    @State private var email: String = ""
    @State private var isLoading = false
    @State private var showSuccessMessage = false
    @State private var errorMessage: String?
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.darkBackground
                .edgesIgnoringSafeArea(.all)
                .onTapGesture {
                    isPresented = false
                }
            
            // Modal content
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("RESET PASSWORD")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                    
                    Spacer()
                    
                    Button(action: {
                        isPresented = false
                    }) {
                        Image(systemName: "xmark")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 20)
                
                if !showSuccessMessage {
                    // Email input section
                    VStack(alignment: .leading, spacing: 20) {
                        Text("Enter your email address to receive password reset instructions.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(.white.opacity(0.8))
                            .padding(.horizontal, 24)
                        
                        // Email input field
                        VStack(spacing: 12) {
                            TextField("Email address", text: $email)
                                .font(OPSStyle.Typography.subtitle)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .foregroundColor(.white)
                                .textFieldStyle(PlainTextFieldStyle())
                            
                            Rectangle()
                                .fill(!email.isEmpty ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inputFieldBorder)
                                .frame(height: 1)
                                .animation(.easeInOut(duration: 0.2), value: email.isEmpty)
                        }
                        .padding(.horizontal, 24)
                        
                        // Error message
                        if let errorMessage = errorMessage {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .font(OPSStyle.Typography.caption)
                                
                                Text(errorMessage)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .multilineTextAlignment(.leading)
                            }
                            .padding(.horizontal, 24)
                        }
                    }
                    
                    Spacer()
                    
                    // Send button
                    Button(action: sendResetEmail) {
                        HStack {
                            if isLoading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Text("SEND RESET EMAIL")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(email.isEmpty || isLoading ? 
                                      OPSStyle.Colors.primaryAccent.opacity(0.5) : 
                                      OPSStyle.Colors.primaryAccent)
                        )
                    }
                    .disabled(email.isEmpty || isLoading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    
                } else {
                    // Success message
                    VStack(spacing: 24) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(OPSStyle.Colors.successStatus)
                        
                        VStack(spacing: 12) {
                            Text("Reset Email Sent")
                                .font(OPSStyle.Typography.title)
                                .foregroundColor(.white)
                            
                            Text("If an account exists with this email address, you will receive password reset instructions shortly.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(.white.opacity(0.8))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }
                    }
                    .padding(.vertical, 40)
                    
                    // Close button
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("CLOSE")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.pageIndicatorInactive, lineWidth: 1)
                            )
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(OPSStyle.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, 40)
        }
        .onAppear {
            // Prefill email if available
            if !prefilledEmail.isEmpty {
                email = prefilledEmail
            }
        }
    }
    
    private func sendResetEmail() {
        guard !email.isEmpty else { return }
        
        isLoading = true
        errorMessage = nil
        
        Task {
            do {
                let authManager = AuthManager()
                _ = try await authManager.requestPasswordReset(email: email)
                
                await MainActor.run {
                    isLoading = false
                    withAnimation {
                        showSuccessMessage = true
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to send reset email. Please try again."
                }
            }
        }
    }
}

// MARK: - Preview
#Preview("Forgot Password") {
    ZStack {
        Color.black
        ForgotPasswordView(
            isPresented: .constant(true),
            prefilledEmail: .constant("user@example.com")
        )
    }
}