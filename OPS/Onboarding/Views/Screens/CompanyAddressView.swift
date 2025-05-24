import SwiftUI
import MapKit

struct CompanyAddressView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), // Center of US
        span: MKCoordinateSpan(latitudeDelta: 50, longitudeDelta: 60)
    )
    @State private var selectedLocation: CLLocationCoordinate2D?
    
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Company Address",
                subtitle: "Step 2 of 6",
                showBackButton: true,
                onBack: {
                    onboardingViewModel.previousStep()
                }
            )
            
            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Where is your company located?")
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
                            .cornerRadius(12)
                            .disabled(true)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            
            VStack(spacing: 16) {
                Button(action: {
                    onboardingViewModel.nextStep()
                }) {
                    HStack {
                        Text("Continue")
                            .font(OPSStyle.Typography.bodyBold)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isAddressValid ? Color("AccentPrimary") : Color("StatusInactive"))
                    )
                }
                .disabled(!isAddressValid)
                
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
    CompanyAddressView()
        .environmentObject(OnboardingViewModel())
}