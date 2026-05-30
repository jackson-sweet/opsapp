//
//  ForgotPasswordView.swift
//  OPS
//
//  Full-page password reset screen.
//  Presented as a sheet from login screens.
//  Matches LoginScreen visual language.
//

import SwiftUI

struct ForgotPasswordView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let prefilledEmail: String

    @State private var email = ""
    @State private var isLoading = false
    @State private var showSuccess = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Close button
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image("ops.close")
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 16)

                if !showSuccess {
                    inputState
                } else {
                    successState
                }
            }
            .dismissKeyboardOnTap()
        }
        .onAppear {
            if !prefilledEmail.isEmpty {
                email = prefilledEmail
            }
        }
    }

    // MARK: - Input State

    private var inputState: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("RESET PASSWORD")
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Enter your email and we'll send instructions to reset your password.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 24)

            Spacer()
                .frame(height: 40)

            // Email field
            VStack(alignment: .leading, spacing: 8) {
                Text("EMAIL")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                TextField("", text: $email)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocapitalization(.none)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .padding(.horizontal, 40)

            // Error message
            if let error = errorMessage {
                HStack(alignment: .top, spacing: 8) {
                    Image("ops.error")
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .font(OPSStyle.Typography.caption)

                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 12)
            }

            // Send button
            Button(action: sendResetEmail) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .black))
                } else {
                    HStack {
                        Text("SEND RESET LINK")
                            .font(OPSStyle.Typography.bodyBold)

                        Spacer()

                        Image("ops.arrow-right")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    }
                    .padding(.horizontal, 20)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(canSend ? Color.white : OPSStyle.Colors.primaryText.opacity(0.5))
            .foregroundColor(OPSStyle.Colors.invertedText)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .disabled(!canSend)
            .padding(.horizontal, 40)
            .padding(.top, 32)

            Spacer()
        }
    }

    // MARK: - Success State

    private var successState: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 24) {
                Image("ops.success")
                    .font(.system(size: 56))
                    .foregroundColor(OPSStyle.Colors.successStatus)

                VStack(spacing: 12) {
                    Text("CHECK YOUR EMAIL")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("If an account exists for \(email), you'll receive reset instructions shortly.")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)

            Spacer()

            // Done button
            Button {
                dismiss()
            } label: {
                HStack {
                    Text("DONE")
                        .font(OPSStyle.Typography.bodyBold)

                    Spacer()

                    Image("ops.checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                .padding(.horizontal, 20)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white)
            .foregroundColor(OPSStyle.Colors.invertedText)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !email.isEmpty && !isLoading
    }

    private func sendResetEmail() {
        guard !email.isEmpty else { return }

        isLoading = true
        errorMessage = nil

        Task {
            let (success, error) = await dataController.requestPasswordReset(email: email)

            await MainActor.run {
                isLoading = false

                if success {
                    withAnimation(OPSStyle.Animation.smooth) {
                        showSuccess = true
                    }
                } else {
                    errorMessage = error ?? "Failed to send reset email. Please try again."
                }
            }
        }
    }
}

// MARK: - Preview

#Preview("Forgot Password") {
    ForgotPasswordView(prefilledEmail: "user@example.com")
        .environmentObject(DataController())
}
