//
//  SecuritySettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

struct SecuritySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var showPINSetup = false
    @State private var newPIN = ""
    @State private var showResetPasswordSheet = false
    @State private var resetEmail = ""
    @State private var passwordResetError: String?
    @State private var passwordResetSuccess = false
    @State private var passwordResetInProgress = false
    @State private var developerModeActivated = false
    
    private var pinManager: SimplePINManager {
        dataController.simplePINManager
    }
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Security",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                ScrollView {
                    VStack(spacing: 0) {
                        // Security section
                        SettingsSectionHeader(title: "APP ACCESS")
                        
                        VStack(spacing: 16) {
                            
                            // PIN toggle
                            HStack {
                                VStack(alignment: .leading){
                                    Text("LOCK IT DOWN")
                                        .font(OPSStyle.Typography.cardTitle)
                                    Text("Require PIN on App Launch")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                }
                                Spacer()
                                
                                Toggle("", isOn: Binding(
                                    get: { pinManager.hasPINEnabled },
                                    set: { enabled in
                                        if enabled {
                                            showPINSetup = true
                                        } else {
                                            pinManager.removePIN()
                                        }
                                    }
                                ))
                                .tint(OPSStyle.Colors.primaryAccent)
                            }
                            .padding(20)
                            .background(Color(OPSStyle.Colors.cardBackgroundDark))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            
                            if pinManager.hasPINEnabled {
                                Button(action: { showPINSetup = true }) {
                                    Text("CHANGE PIN")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                }
                                .padding(.horizontal, 20)
                            }
                        }
                        .padding(16)
                        
                        // Account Security section
                        SettingsSectionHeader(title: "ACCOUNT SECURITY")
                        
                        VStack(spacing: 16) {
                            // Reset Password button
                            SettingsCategoryButton(
                                title: "Reset Password",
                                description: "Change your account password",
                                icon: "lock.shield",
                                action: {
                                    showResetPasswordSheet = true
                                }
                            )
                        }
                        .padding(16)
                    }
                    .padding(.vertical, 24)
                    .padding(.top, 12)
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $showPINSetup) {
            PINSetupSheet(pinManager: pinManager, isPresented: $showPINSetup)
        }
        .sheet(isPresented: $showResetPasswordSheet, onDismiss: {
            resetPasswordFields()
        }) {
            resetPasswordSheet
                .onAppear {
                    if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
                        resetEmail = userEmail
                    }
                }
        }
    }
    
    // Password reset sheet view
    private var resetPasswordSheet: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(.white)
                    .padding(.top, 24)
                
                if !passwordResetSuccess {
                    VStack(spacing: 16) {
                        Text("Enter your email address to receive a password reset link.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 8)
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            TextField("Enter email address", text: $resetEmail)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(.white)
                                .keyboardType(.default)  // Changed to default to allow entering the phrase
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                )
                            
                            // Show developer mode button when secret phrase is entered
                            // Check directly without onChange
                            if resetEmail.lowercased() == "railmetwice" {
                                VStack(spacing: 8) {
                                    if UserDefaults.standard.bool(forKey: "developerModeEnabled") {
                                        // Show if already enabled
                                        HStack {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(OPSStyle.Colors.successStatus)
                                            Text("Developer Mode Already Active")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.successStatus)
                                        }
                                        .padding(.top, 8)
                                    } else {
                                        // Show activation button
                                        Button(action: activateDeveloperMode) {
                                            HStack {
                                                Image(systemName: "hammer.circle.fill")
                                                    .font(.system(size: 20))
                                                Text("Enter Developer Mode")
                                                    .font(OPSStyle.Typography.body)
                                            }
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                                            )
                                        }
                                        .padding(.top, 8)
                                    }
                                }
                                .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .padding(.horizontal, 20)
                        
                        if let error = passwordResetError {
                            Text(error)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                                .padding(.top, 8)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Button(action: {
                                resetPasswordFields()
                                showResetPasswordSheet = false
                            }) {
                                Text("Cancel")
                                    .font(OPSStyle.Typography.button)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(12)
                            }
                            
                            Button(action: {
                                requestPasswordReset()
                            }) {
                                if passwordResetInProgress {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(12)
                                } else {
                                    Text("Send Reset Link")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(.black)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(12)
                                }
                            }
                            .disabled(!isEmailValid || passwordResetInProgress)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                } else {
                    // Success message
                    VStack(spacing: 16) {
                        Image(systemName: developerModeActivated ? "hammer.circle.fill" : "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(developerModeActivated ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.successStatus)
                            .padding(.bottom, 8)
                        
                        Text(developerModeActivated ? "Developer Mode Activated!" : "Reset Link Sent!")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                        
                        Text(developerModeActivated ? "You now have access to debug features." : "Check your email for instructions on how to reset your password.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                        
                        Spacer()
                        
                        Button(action: {
                            showResetPasswordSheet = false
                        }) {
                            Text("Done")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 40)
                    }
                }
            }
            .padding(.vertical, 20)
        }
    }
    
    // Email validation
    private var isEmailValid: Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return !resetEmail.isEmpty && emailPredicate.evaluate(with: resetEmail)
    }
    
    // Request password reset function
    private func requestPasswordReset() {
        passwordResetError = nil
        passwordResetInProgress = true
        
        if resetEmail.isEmpty, let userEmail = dataController.currentUser?.email {
            resetEmail = userEmail
        }
        
        guard isEmailValid else {
            passwordResetError = "Please enter a valid email address"
            passwordResetInProgress = false
            return
        }
        
        
        Task {
            let (success, errorMessage) = await dataController.requestPasswordReset(email: resetEmail)
            
            await MainActor.run {
                passwordResetInProgress = false
                
                if success {
                    passwordResetSuccess = true
                } else {
                    passwordResetError = errorMessage ?? "Failed to send reset link. Please try again."
                }
            }
        }
    }
    
    // Reset password fields
    private func resetPasswordFields() {
        resetEmail = ""
        passwordResetError = nil
        passwordResetSuccess = false
        passwordResetInProgress = false
        developerModeActivated = false
    }
    
    // Activate developer mode
    private func activateDeveloperMode() {
        
        // Activate developer mode
        UserDefaults.standard.set(true, forKey: "developerModeEnabled")
        UserDefaults.standard.synchronize() // Force sync
        
        developerModeActivated = true
        passwordResetSuccess = true
        
        
        // Auto-dismiss after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            showResetPasswordSheet = false
            
            // Show an alert or notification that developer mode is active
        }
    }
}

struct PINSetupSheet: View {
    let pinManager: SimplePINManager
    @Binding var isPresented: Bool
    @State private var enteredPIN = ""
    @State private var confirmedPIN = ""
    @State private var showConfirmation = false
    @State private var errorMessage = ""
    
    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 24) {
                    if !showConfirmation {
                        // Enter new PIN
                        Text("ENTER NEW 4-DIGIT PIN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        SecureField("", text: $enteredPIN)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                            .onChange(of: enteredPIN) { _, newValue in
                                if newValue.count > 4 {
                                    enteredPIN = String(newValue.prefix(4))
                                }
                            }
                        
                        Button("NEXT") {
                            if enteredPIN.count == 4 {
                                showConfirmation = true
                                errorMessage = ""
                            } else {
                                errorMessage = "PIN must be 4 digits"
                            }
                        }
                        .font(OPSStyle.Typography.body)
                        .buttonStyle(OPSButtonStyle.Primary())
                        .disabled(enteredPIN.count != 4)
                    } else {
                        // Confirm PIN
                        Text("CONFIRM PIN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(.white)
                        
                        SecureField("", text: $confirmedPIN)
                            .keyboardType(.numberPad)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 200)
                            .onChange(of: confirmedPIN) { _, newValue in
                                if newValue.count > 4 {
                                    confirmedPIN = String(newValue.prefix(4))
                                }
                            }
                        
                        HStack(spacing: 16) {
                            Button("BACK") {
                                showConfirmation = false
                                confirmedPIN = ""
                                errorMessage = ""
                            }
                            .buttonStyle(OPSButtonStyle.Secondary())
                            .font(OPSStyle.Typography.body)
                            
                            Button("SAVE") {
                                if confirmedPIN == enteredPIN {
                                    pinManager.setPIN(enteredPIN)
                                    isPresented = false
                                } else {
                                    errorMessage = "PINs don't match"
                                    confirmedPIN = ""
                                }
                            }
                            .buttonStyle(OPSButtonStyle.Primary())
                            .font(OPSStyle.Typography.body)
                            .disabled(confirmedPIN.count != 4)
                        }
                    }
                    
                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                    }
                }
                .padding()
            }
            .navigationBarItems(
                trailing: Button("Cancel") {
                    isPresented = false
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            )
        }
    }
}

#Preview {
    SecuritySettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}
