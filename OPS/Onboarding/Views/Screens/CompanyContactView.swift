import SwiftUI

struct CompanyContactView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var emailError: String?
    @State private var phoneError: String?
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return onboardingViewModel.currentStep.stepNumber(for: onboardingViewModel.selectedUserType) ?? 5
    }
    
    private var totalSteps: Int {
        guard let userType = onboardingViewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header with step indicator
                HStack {
                    Button(action: {
                        onboardingViewModel.moveToPreviousStep()
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
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
                
                // Main content area - top-justified
                VStack(spacing: 0) {
                    VStack(spacing: 32) {
                        VStack(alignment: .leading, spacing: 16) {
                        Text("HOW CAN CUSTOMERS REACH YOU?")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(Color("TextPrimary"))
                        
                        Text("This information will be visible to clients and team members for project coordination.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // Autofill buttons
                    HStack(spacing: 24) {
                        Button(action: {
                            email = onboardingViewModel.email
                            validateEmail()
                        }) {
                            HStack {
                                Image(systemName: "envelope")
                                    .font(OPSStyle.Typography.caption)
                                Spacer()
                                Text("USE MY EMAIL")
                                    .font(OPSStyle.Typography.cardBody)
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color("AccentPrimary"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color("AccentPrimary"), lineWidth: 1)
                            )
                            
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            phoneNumber = formatPhoneNumber(onboardingViewModel.phoneNumber)
                            validatePhone()
                        }) {
                            HStack {
                                Image(systemName: "phone")
                                    .font(OPSStyle.Typography.caption)
                                Spacer()
                                Text("USE MY PHONE")
                                    .font(OPSStyle.Typography.cardBody)
                                    .lineLimit(1)
                            }
                            .foregroundColor(Color("AccentPrimary"))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color("AccentPrimary"), lineWidth: 1)
                            )

                        }
                    }
                    
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            UnderlineTextField(
                                placeholder: "company@example.com",
                                text: $email,
                                keyboardType: .emailAddress,
                                viewModel: onboardingViewModel,
                                onChange: { _ in
                                    validateEmail()
                                }
                            )
                            
                            if let emailError = emailError {
                                Text(emailError)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(Color("StatusError"))
                            }
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Phone Number")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            UnderlineTextField(
                                placeholder: "(555) 123-4567",
                                text: $phoneNumber,
                                keyboardType: .phonePad,
                                viewModel: onboardingViewModel,
                                onChange: { newValue in
                                    phoneNumber = formatPhoneNumber(newValue)
                                    validatePhone()
                                }
                            )
                            
                            if let phoneError = phoneError {
                                Text(phoneError)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(Color("StatusError"))
                            }
                        }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40) // Add consistent top padding
                    
                    Spacer()
                }
                
                // Bottom button section
                VStack(spacing: 16) {
                StandardContinueButton(
                    isDisabled: !isFormValid,
                    onTap: {
                        if validateForm() {
                            onboardingViewModel.companyEmail = email
                            onboardingViewModel.companyPhone = phoneNumber
                            onboardingViewModel.moveToNextStep()
                        }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 34)
            .background(
                Rectangle()
                    .fill(Color("Background"))
                    .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: -4)
            )
            } // End of main VStack
        }
        .background(Color("Background"))
        .onAppear {
            email = onboardingViewModel.companyEmail
            phoneNumber = onboardingViewModel.companyPhone
        }
    }
    
    private var isFormValid: Bool {
        !email.isEmpty && !phoneNumber.isEmpty && emailError == nil && phoneError == nil
    }
    
    private func validateEmail() {
        emailError = nil
        if !email.isEmpty && !isValidEmail(email) {
            emailError = "Please enter a valid email address"
        }
    }
    
    private func validatePhone() {
        phoneError = nil
        if !phoneNumber.isEmpty && phoneNumber.count < 14 {
            phoneError = "Please enter a complete phone number"
        }
    }
    
    private func validateForm() -> Bool {
        validateEmail()
        validatePhone()
        return emailError == nil && phoneError == nil && !email.isEmpty && !phoneNumber.isEmpty
    }
    
    private func isValidEmail(_ email: String) -> Bool {
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format:"SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: email)
    }
    
    private func formatPhoneNumber(_ number: String) -> String {
        let cleaned = number.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        guard cleaned.count <= 10 else {
            return String(cleaned.prefix(10)).applyPhoneFormat()
        }
        
        return cleaned.applyPhoneFormat()
    }
}

extension String {
    func applyPhoneFormat() -> String {
        let cleaned = self.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
        
        switch cleaned.count {
        case 0...3:
            return cleaned
        case 4...6:
            let area = String(cleaned.prefix(3))
            let middle = String(cleaned.dropFirst(3))
            return "(\(area)) \(middle)"
        case 7...10:
            let area = String(cleaned.prefix(3))
            let middle = String(cleaned.dropFirst(3).prefix(3))
            let last = String(cleaned.dropFirst(6))
            return "(\(area)) \(middle)-\(last)"
        default:
            let area = String(cleaned.prefix(3))
            let middle = String(cleaned.dropFirst(3).prefix(3))
            let last = String(cleaned.dropFirst(6).prefix(4))
            return "(\(area)) \(middle)-\(last)"
        }
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    CompanyContactView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}
