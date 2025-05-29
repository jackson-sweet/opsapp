import SwiftUI

struct TeamInvitesView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var inviteEmails: [String] = [""]
    @State private var emailErrors: [String?] = [nil]
    @State private var isLoading = false
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return 8 // Company flow position - after company code
    }
    
    private var totalSteps: Int {
        if onboardingViewModel.selectedUserType == .employee {
            return 8 // Employee flow has 8 total steps
        } else {
            return 10 // Company flow has 10 total steps
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation header with step indicator
            HStack {
                Button(action: {
                    onboardingViewModel.previousStep()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.caption)
                        Text("Back")
                            .font(OPSStyle.Typography.body)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                Spacer()
                
                Button(action: {
                    onboardingViewModel.logoutAndReturnToLogin()
                }) {
                    Text("Sign Out")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 8)
            .padding(.horizontal, 24)
            
            // Step indicator bars
            HStack(spacing: 4) {
                ForEach(0..<totalSteps) { step in
                    Rectangle()
                        .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.4))
                        .frame(height: 4)
                }
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 24)
            
            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("READY TO BUILD YOUR TEAM?")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(Color("TextPrimary"))
                        
                        Text("Invite team members to join your company. They'll receive an email with instructions to download the app and join your organization.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 16) {
                        ForEach(inviteEmails.indices, id: \.self) { index in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Team Member \(index + 1)")
                                        .font(OPSStyle.Typography.bodyBold)
                                        .foregroundColor(Color("TextPrimary"))
                                    
                                    Spacer()
                                    
                                    if inviteEmails.count > 1 {
                                        Button(action: {
                                            removeEmail(at: index)
                                        }) {
                                            Image(systemName: "minus.circle.fill")
                                                .foregroundColor(Color("StatusError"))
                                                .font(OPSStyle.Typography.subtitle)
                                        }
                                    }
                                }
                                
                                UnderlineTextField(
                                    placeholder: "team.member@example.com",
                                    text: Binding(
                                        get: { inviteEmails[index] },
                                        set: { inviteEmails[index] = $0; validateEmail(at: index) }
                                    ),
                                    keyboardType: .emailAddress,
                                    viewModel: onboardingViewModel
                                )
                                
                                if let error = emailErrors[index] {
                                    Text(error)
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(Color("StatusError"))
                                }
                            }
                        }
                        
                        if inviteEmails.count < 10 {
                            Button(action: addEmailField) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(Color("AccentPrimary"))
                                    
                                    Text("Add another team member")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(Color("AccentPrimary"))
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "info.circle")
                                .foregroundColor(Color("AccentPrimary"))
                            
                            Text("What happens next?")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("• Team members will receive an email invitation")
                            Text("• They'll download the OPS app and create their account")
                            Text("• Once they join, they'll appear in your team dashboard")
                            Text("• You can always invite more members later from settings")
                        }
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(Color("TextSecondary"))
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("AccentPrimary").opacity(0.1))
                    )
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 140)
            }
            
            VStack(spacing: 16) {
                if isLoading {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        
                        Text("Sending invitations...")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color("AccentPrimary"))
                    )
                } else {
                    StandardContinueButton(
                        onTap: sendInvitations
                    )
                }
                
                Button(action: {
                    onboardingViewModel.nextStep()
                }) {
                    Text("Skip for now")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(Color("TextSecondary"))
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .background(
                Rectangle()
                    .fill(Color("Background"))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
            )
        }
        .background(Color("Background"))
        .onAppear {
            if inviteEmails.isEmpty {
                inviteEmails = [""]
                emailErrors = [nil]
            }
        }
    }
    
    private var hasValidEmails: Bool {
        let validEmails = inviteEmails.enumerated().compactMap { index, email in
            return !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && emailErrors[index] == nil ? email : nil
        }
        return !validEmails.isEmpty
    }
    
    private func addEmailField() {
        inviteEmails.append("")
        emailErrors.append(nil)
    }
    
    private func removeEmail(at index: Int) {
        guard inviteEmails.count > 1 else { return }
        inviteEmails.remove(at: index)
        emailErrors.remove(at: index)
    }
    
    private func validateEmail(at index: Int) {
        guard index < emailErrors.count else { return }
        
        let email = inviteEmails[index].trimmingCharacters(in: .whitespacesAndNewlines)
        
        if email.isEmpty {
            emailErrors[index] = nil
        } else if !isValidEmail(email) {
            emailErrors[index] = "Please enter a valid email address"
        } else {
            emailErrors[index] = nil
        }
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func sendInvitations() {
        guard hasValidEmails else {
            onboardingViewModel.nextStep()
            return
        }
        
        let validEmails = inviteEmails.enumerated().compactMap { index, email in
            let trimmedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmedEmail.isEmpty && emailErrors[index] == nil ? trimmedEmail : nil
        }
        
        guard !validEmails.isEmpty else {
            onboardingViewModel.nextStep()
            return
        }
        
        isLoading = true
        
        onboardingViewModel.teamInviteEmails = validEmails
        
        Task {
            do {
                try await onboardingViewModel.sendTeamInvitations()
                await MainActor.run {
                    isLoading = false
                    onboardingViewModel.nextStep()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    // Handle error - could show alert or continue anyway
                    onboardingViewModel.nextStep()
                }
            }
        }
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    TeamInvitesView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}