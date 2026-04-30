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

    // Bug e33aa336 — settings search deep-link anchors and spotlight.
    private enum AnchorID {
        static let appAccess = "app_access"
        static let accountSecurity = "account_security"
    }

    @State private var highlightedSection: String? = nil

    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Security",
                    onBackTapped: {
                        dismiss()
                    }
                )

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {
                        // App Access section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("APP ACCESS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                // PIN toggle
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("LOCK IT DOWN")
                                            .font(OPSStyle.Typography.cardTitle)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                        Text("Require PIN on App Launch")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
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
                                .padding(16)
                                .wizardTarget("enable_pin", style: .row)

                                if pinManager.hasPINEnabled {
                                    Divider()
                                        .background(OPSStyle.Colors.cardBorder)

                                    Button(action: { showPINSetup = true }) {
                                        Text("CHANGE PIN")
                                            .font(OPSStyle.Typography.captionBold)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                    .padding(.vertical, 14)
                                    .padding(.horizontal, 16)
                                }
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .padding(.horizontal, 20)
                        .id(AnchorID.appAccess)
                        .deepLinkSpotlight(highlightedSection == AnchorID.appAccess)

                        // Account Security section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("ACCOUNT SECURITY")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                SettingsCategoryButton(
                                    title: "Reset Password",
                                    description: "Change your account password",
                                    icon: "lock.shield",
                                    action: {
                                        showResetPasswordSheet = true
                                    }
                                )
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }
                        .padding(.horizontal, 20)
                        .id(AnchorID.accountSecurity)
                        .deepLinkSpotlight(highlightedSection == AnchorID.accountSecurity)
                    }
                    .padding(.vertical, 24)
                    .padding(.top, 12)
                }
                .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.security)) { notification in
                    guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
                    let anchor: String?
                    switch section {
                    case "app_access":       anchor = AnchorID.appAccess
                    case "account_security": anchor = AnchorID.accountSecurity
                    default: anchor = nil
                    }
                    guard let anchor else { return }

                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                    withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                        highlightedSection = anchor
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.4)) {
                                highlightedSection = nil
                            }
                        }
                    }
                }
                }
            }
        }
        .trackScreen("Settings.Security")
        .navigationBarBackButtonHidden(true)
        .onDisappear {
            NotificationCenter.default.post(
                name: Notification.Name("WizardScreenDismissed"),
                object: nil,
                userInfo: ["screen": "SecuritySettings"]
            )
        }
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
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Text("Reset Password")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
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
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .keyboardType(.default)  // Changed to default to allow entering the phrase
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                                )

                            // Show developer mode button when secret phrase is entered
                            // Check directly without onChange
                            if resetEmail.lowercased() == "railmetwice" {
                                VStack(spacing: 8) {
                                    if UserDefaults.standard.bool(forKey: "developerModeEnabled") {
                                        // Show if already enabled
                                        HStack {
                                            Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
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
                                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                Text("Enter Developer Mode")
                                                    .font(OPSStyle.Typography.body)
                                            }
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            .frame(maxWidth: .infinity)
                                            .padding(.vertical, 12)
                                            .background(
                                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
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
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(OPSStyle.Colors.cardBackgroundDark)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }

                            Button(action: {
                                requestPasswordReset()
                            }) {
                                if passwordResetInProgress {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.invertedText))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                } else {
                                    Text("Send Reset Link")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
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
                        Image(systemName: developerModeActivated ? "hammer.circle.fill" : OPSStyle.Icons.checkmarkCircleFill)
                            .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                            .foregroundColor(developerModeActivated ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.successStatus)
                            .padding(.bottom, 8)

                        Text(developerModeActivated ? "Developer Mode Activated!" : "Reset Link Sent!")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

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
                                .foregroundColor(OPSStyle.Colors.invertedText)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(OPSStyle.Colors.primaryAccent)
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
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
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 24) {
                    if !showConfirmation {
                        // Enter new PIN
                        Text("ENTER NEW 4-DIGIT PIN")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        SecureField("", text: $enteredPIN)
                            .keyboardType(.numberPad)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(width: 200)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
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
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        SecureField("", text: $confirmedPIN)
                            .keyboardType(.numberPad)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .multilineTextAlignment(.center)
                            .padding()
                            .frame(width: 200)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
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
                                    NotificationCenter.default.post(name: Notification.Name("WizardPINEnabled"), object: nil)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") {
                        isPresented = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }
}

#Preview {
    SecuritySettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}
