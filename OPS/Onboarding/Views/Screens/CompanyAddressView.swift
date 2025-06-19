import SwiftUI
import MapKit

struct CompanyAddressView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of US
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
    )
    @State private var selectedLocation: CLLocationCoordinate2D?
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return onboardingViewModel.currentStep.stepNumber(for: onboardingViewModel.selectedUserType) ?? 4
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
                    ForEach(0..<totalSteps) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.4))
                            .frame(height: 4)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, 24)
            
            // Main content area - top-justified
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("WHERE IS YOUR COMPANY LOCATED?")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(Color("TextPrimary"))
                        
                        Text("This helps us connect you with local projects and team members.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 16) {
                        AddressAutocompleteField(
                            address: $onboardingViewModel.companyAddress,
                            placeholder: "Enter company address",
                            onAddressSelected: { address, coordinate in
                                selectedLocation = coordinate
                                if let coordinate = coordinate {
                                    region = MKCoordinateRegion(
                                        center: coordinate,
                                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                                    )
                                }
                            }
                        )
                        
                        if let selectedLocation = selectedLocation {
                            Map(initialPosition: .region(region)) {
                                Marker("", coordinate: selectedLocation)
                                    .tint(Color(OPSStyle.Colors.background))
                            }
                            .frame(height: 200)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .disabled(true)
                        }
                    }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40) // Add consistent top padding
                }
                
                Spacer()
            }
            
            // Bottom button section
            VStack(spacing: 16) {
                StandardContinueButton(
                    isDisabled: !isAddressValid,
                    onTap: {
                        onboardingViewModel.moveToNextStep()
                    }
                )
                
                Button(action: {
                    onboardingViewModel.moveToNextStep()
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
        }
    }
    
    private var isAddressValid: Bool {
        !onboardingViewModel.companyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    CompanyAddressView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}
