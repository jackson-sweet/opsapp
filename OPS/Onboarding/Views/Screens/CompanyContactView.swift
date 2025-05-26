import SwiftUI

struct CompanyContactView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var email = ""
    @State private var phoneNumber = ""
    @State private var emailError: String?
    @State private var phoneError: String?
    
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Contact Information",
                subtitle: "Step 3 of 6",
                showBackButton: true,
                onBack: {
                    onboardingViewModel.previousStep()
                }
            )
            
            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("How can customers reach you?")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(Color("TextPrimary"))
                        
                        Text("This information will be visible to clients and team members for project coordination.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Email Address")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            FormTextField(
                                title: "",
                                text: $email,
                                placeholder: "company@example.com",
                                keyboardType: .emailAddress
                            )
                            .onChange(of: email) { _ in
                                validateEmail()
                            }
                            
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
                            
                            FormTextField(
                                title: "",
                                text: $phoneNumber,
                                placeholder: "(555) 123-4567",
                                keyboardType: .phonePad
                            )
                            .onChange(of: phoneNumber) { newValue in
                                phoneNumber = formatPhoneNumber(newValue)
                                validatePhone()
                            }
                            
                            if let phoneError = phoneError {
                                Text(phoneError)
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(Color("StatusError"))
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            
            VStack(spacing: 16) {
                Button(action: {
                    if validateForm() {
                        onboardingViewModel.companyEmail = email
                        onboardingViewModel.companyPhone = phoneNumber
                        onboardingViewModel.nextStep()
                    }
                }) {
                    HStack {
                        Text("Continue")
                            .font(OPSStyle.Typography.bodyBold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isFormValid ? Color("AccentPrimary") : Color("StatusInactive"))
                    )
                }
                .disabled(!isFormValid)
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
    CompanyContactView()
        .environmentObject(OnboardingViewModel())
}