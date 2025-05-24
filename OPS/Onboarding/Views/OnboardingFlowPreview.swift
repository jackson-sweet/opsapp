//
//  OnboardingFlowPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI
import SwiftData

// MARK: - Preview showing all onboarding steps
struct OnboardingFlowPreview: View {
    // Step selection
    @State private var selectedScreen: OnboardingStep = .welcome
    
    // Show device frame
    @State private var showDeviceFrame = true
    
    // Preview scale
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        VStack(spacing: 0) {
            // Controls section
            VStack(spacing: 10) {
                HStack {
                    Text("Select Step to Preview")
                    .font(.headline)
                    .padding(.horizontal)
                    
                    // Device frame toggle
                    Toggle("Show Device Frame", isOn: $showDeviceFrame)
                        .padding(.horizontal)
                }
                .padding(.top, 10)
                
                // Scale slider
                HStack {
                    Text("Scale:")
                    Slider(value: $scale, in: 0.5...1.0)
                    Text("\(Int(scale * 100))%")
                        .frame(width: 50, alignment: .trailing)
                }
                .padding(.horizontal)
                
                // Step selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        // Steps
                        ForEach(OnboardingStep.allCases, id: \.self) { step in
                            Button(action: {
                                selectedScreen = step
                            }) {
                                Text(step.title)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(selectedScreen == step ? 
                                        OPSStyle.Colors.primaryAccent : 
                                        Color.white.opacity(0.1))
                                    .foregroundColor(.white)
                                    .cornerRadius(4)
                            }
                        }
                    }
                    .padding()
                }
                .background(Color.black.opacity(0.5))
            }
            .background(Color.gray.opacity(0.2))
            .foregroundColor(.white)
            
            // Screen preview with device frame
            ZStack {
                // Device frame if enabled
                if showDeviceFrame {
                    // iPhone mock frame
                    RoundedRectangle(cornerRadius: 38)
                        .stroke(Color.gray, lineWidth: 10)
                        .background(RoundedRectangle(cornerRadius: 38).fill(Color.black))
                        .overlay(
                            // Notch
                            RoundedRectangle(cornerRadius: 10)
                                .frame(width: 120, height: 32)
                                .foregroundColor(Color.gray)
                                .position(x: UIScreen.main.bounds.width / 2, y: 16)
                        )
                        .shadow(radius: 30)
                        .scaleEffect(scale)
                }
                
                // Screen content
                let viewModel = createViewModel(for: selectedScreen)
                
                // Flow screens
                Group {
                    switch selectedScreen {
                    case .welcome:
                        WelcomeView(viewModel: viewModel)
                    case .userTypeSelection:
                        UserTypeSelectionView()
                            .environmentObject(viewModel)
                    case .accountSetup:
                        EmailView(viewModel: viewModel, isInConsolidatedFlow: true)
                    case .organizationJoin:
                        OrganizationJoinView(viewModel: viewModel, isInConsolidatedFlow: true)
                    case .userDetails:
                        UserInfoView(viewModel: viewModel, isInConsolidatedFlow: true)
                    case .companyCode:
                        CompanyCodeView(viewModel: viewModel)
                    case .companyBasicInfo:
                        CompanyBasicInfoView()
                            .environmentObject(viewModel)
                    case .companyAddress:
                        CompanyAddressView()
                            .environmentObject(viewModel)
                    case .companyContact:
                        CompanyContactView()
                            .environmentObject(viewModel)
                    case .companyDetails:
                        CompanyDetailsView()
                            .environmentObject(viewModel)
                    case .teamInvites:
                        TeamInvitesView()
                            .environmentObject(viewModel)
                    case .welcomeGuide:
                        WelcomeGuideView()
                            .environmentObject(viewModel)
                    case .permissions:
                        PermissionsView(viewModel: viewModel, isInConsolidatedFlow: true)
                    case .fieldSetup:
                        FieldSetupView(viewModel: viewModel)
                            .environmentObject(DataController())
                    case .completion:
                        CompletionView {
                            // Reset to first screen when complete
                            selectedScreen = .welcome
                        }
                    }
                }
                .scaleEffect(scale)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(showDeviceFrame ? Color.gray.opacity(0.3) : Color.black)
        }
        .background(Color.black)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environmentObject(DataController())
        .environment(\.colorScheme, .dark)
    }
    
    /// Creates a view model with appropriate data based on the current step
    private func createViewModel(for step: OnboardingStep) -> OnboardingViewModel {
        let viewModel = OnboardingViewModel()
        viewModel.currentStep = step
        
        // Add sample data based on how far we are in the flow
        if step.rawValue >= OnboardingStep.accountSetup.rawValue {
            viewModel.email = "user@example.com"
            viewModel.password = "password123"
            viewModel.confirmPassword = "password123"
        }
        
        if step.rawValue >= OnboardingStep.organizationJoin.rawValue {
            viewModel.isSignedUp = true
            viewModel.userId = "user123"
        }
        
        if step.rawValue >= OnboardingStep.userDetails.rawValue {
            viewModel.firstName = "John"
            viewModel.lastName = "Doe"
            viewModel.phoneNumber = "5551234567"
            viewModel.isSignedUp = true
        }
        
        if step.rawValue >= OnboardingStep.companyCode.rawValue {
            viewModel.companyCode = "DEMO123"
        }
        
        if step.rawValue >= OnboardingStep.permissions.rawValue {
            viewModel.companyName = "Demo Company, Inc."
            viewModel.isCompanyJoined = true
            viewModel.isLocationPermissionGranted = true
            viewModel.isNotificationsPermissionGranted = true
        }
        
        if step.rawValue >= OnboardingStep.fieldSetup.rawValue {
            // Field setup data
        }
        
        return viewModel
    }
}

// OnboardingStep is already CaseIterable in OnboardingModels.swift

#Preview("Onboarding Flow") {
    OnboardingFlowPreview()
}