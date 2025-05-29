import SwiftUI
import MapKit

struct CompanyAddressView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of US
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
    )
    @State private var selectedLocation: CLLocationCoordinate2D?
    var isInConsolidatedFlow: Bool = false
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return 4 // Company flow position - after basic info
    }
    
    private var totalSteps: Int {
        if onboardingViewModel.selectedUserType == .employee {
            return 8 // Employee flow has 8 total steps
        } else {
            return 10 // Company flow has 10 total steps
        }
    }
    
    var body: some View {
        ZStack {
            // Background color
            Color.black.edgesIgnoringSafeArea(.all)
            
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
                        
                        if selectedLocation != nil {
                            Map(coordinateRegion: .constant(region), annotationItems: [MapPin(coordinate: selectedLocation!)]) { pin in
                                MapMarker(coordinate: pin.coordinate, tint: Color("AccentPrimary"))
                            }
                            .frame(height: 200)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .disabled(true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            
            VStack(spacing: 16) {
                StandardContinueButton(
                    isDisabled: !isAddressValid,
                    onTap: {
                        onboardingViewModel.nextStep()
                    }
                )
                
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
        }
    }
    
    private var isAddressValid: Bool {
        !onboardingViewModel.companyAddress.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

struct MapPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    CompanyAddressView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}