//
//  LoginView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var dataController: DataController
    
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?
    @State private var showError = false
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: OPSStyle.Layout.spacing4) {
                Spacer()
                
                // Logo and app name
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    Image(systemName: "building.2.fill")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Text("OPS")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.bottom, OPSStyle.Layout.spacing5)
                
                // Login form
                VStack(spacing: OPSStyle.Layout.spacing4) {
                    // Username field
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("USERNAME")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        TextField("", text: $username)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding()
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                            )
                            .autocapitalization(.none)
                            .disableAutocorrection(true)
                    }
                    
                    // Password field
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("PASSWORD")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        SecureField("", text: $password)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding()
                            .background(OPSStyle.Colors.cardBackground)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                            )
                    }
                    
                    // For testing purposes
                    VStack {
                        Text("For testing:")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        HStack(spacing: 4) {
                            Text("Username:")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("demo")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            
                            Text("Password:")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.leading, 8)
                            
                            Text("password")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, OPSStyle.Layout.spacing2)
                    
                    // Quick fill button for testers
                    Button("Fill Test Credentials") {
                        username = "demo"
                        password = "password"
                    }
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.bottom, OPSStyle.Layout.spacing3)
                    
                    // Login button
                    Button(action: login) {
                        HStack {
                            if isLoggingIn {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                    .padding(.trailing, 8)
                            }
                            
                            Text(isLoggingIn ? "Signing In..." : "Sign In")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                        .opacity(isLoggingIn ? 0.7 : 1.0)
                    }
                    .disabled(isLoggingIn || username.isEmpty || password.isEmpty)
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
                .padding(.horizontal, 32)
                
                Spacer()
                
                // Version info
                Text("v1.0.0")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                    .padding(.bottom, OPSStyle.Layout.spacing3)
            }
            .dismissKeyboardOnTap() // Use the custom keyboard dismissal modifier
        }
        .alert(isPresented: $showError, content: {
            Alert(
                title: Text("Sign In Failed"),
                message: Text(errorMessage ?? "Please check your credentials and try again."),
                dismissButton: .default(Text("OK"))
            )
        })
    }
    
    private func login() {
        guard !username.isEmpty, !password.isEmpty else { return }
        
        isLoggingIn = true
        errorMessage = nil
        
        Task {
            do {
                let success = await dataController.login(username: username, password: password)
                
                await MainActor.run {
                    isLoggingIn = false
                    
                    if !success {
                        errorMessage = "Invalid username or password. Please try again."
                        showError = true
                    }
                }
            } catch let authError as AuthError {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = authError.localizedDescription
                    showError = true
                }
            } catch let apiError as APIError {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = apiError.localizedDescription
                    showError = true
                }
            } catch {
                await MainActor.run {
                    isLoggingIn = false
                    errorMessage = "Login failed: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}
