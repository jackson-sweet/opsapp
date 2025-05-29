//
//  OnboardingFlowPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI
import SwiftData

// MARK: - Main Preview Navigator
struct OnboardingFlowPreview: View {
    @State private var selectedFlow: FlowType = .employee
    @State private var selectedScreen = 0
    @State private var showDeviceFrame = false
    @State private var deviceScale: CGFloat = 0.8
    
    enum FlowType: String, CaseIterable {
        case employee = "Employee Flow (8 Steps)"
        case company = "Company Flow (10 Steps)"
        case original = "Original (11 Steps)"
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header Controls
            VStack(spacing: 16) {
                // Flow selector
                Picker("Flow Type", selection: $selectedFlow) {
                    ForEach(FlowType.allCases, id: \.self) { flow in
                        Text(flow.rawValue).tag(flow)
                    }
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding(.horizontal)
                
                // Screen selector
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(currentScreens.enumerated()), id: \.offset) { index, screen in
                            Button(action: {
                                selectedScreen = index
                            }) {
                                VStack(spacing: 4) {
                                    Text("\(index + 1)")
                                        .font(.caption2)
                                        .foregroundColor(.gray)
                                    Text(screen.name)
                                        .font(.caption)
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(selectedScreen == index ? 
                                              Color.blue : Color.gray.opacity(0.2))
                                )
                                .foregroundColor(selectedScreen == index ? .white : .primary)
                            }
                        }
                    }
                    .padding(.horizontal)
                }
                
                // Device controls
                HStack {
                    Toggle("Device Frame", isOn: $showDeviceFrame)
                    
                    Spacer()
                    
                    Text("Scale: \(Int(deviceScale * 100))%")
                    Slider(value: $deviceScale, in: 0.5...1.0)
                        .frame(width: 150)
                }
                .padding(.horizontal)
                .font(.caption)
            }
            .padding(.vertical, 12)
            .background(Color(UIColor.systemGray6))
            
            // Preview Area
            GeometryReader { geometry in
                ZStack {
                    // Background
                    Color.black
                    
                    // Device frame container
                    if showDeviceFrame {
                        DeviceFrame(scale: deviceScale) {
                            currentScreenView
                        }
                    } else {
                        currentScreenView
                            .scaleEffect(deviceScale)
                    }
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .preferredColorScheme(.dark)
    }
    
    // Current screens based on selected flow
    var currentScreens: [(name: String, view: AnyView)] {
        switch selectedFlow {
        case .employee:
            return employeeFlowScreens
        case .company:
            return companyFlowScreens
        case .original:
            return originalFlowScreens
        }
    }
    
    // Current screen view
    @ViewBuilder
    var currentScreenView: some View {
        if selectedScreen < currentScreens.count {
            currentScreens[selectedScreen].view
                .environmentObject(mockViewModel)
                .environmentObject(OnboardingPreviewHelpers.createPreviewDataController())
        }
    }
    
    // Mock view model with sample data
    var mockViewModel: OnboardingViewModel {
        let vm = OnboardingViewModel()
        
        // Set sample data based on current screen
        if selectedScreen > 0 {
            vm.email = "john.doe@example.com"
            vm.selectedUserType = selectedFlow == .company ? .company : .employee
        }
        
        if selectedScreen > 1 {
            vm.password = "password123"
            vm.confirmPassword = "password123"
            vm.isSignedUp = true
            vm.userId = "12345"
        }
        
        if selectedScreen > 2 {
            vm.phoneNumber = "5551234567"
            vm.isPhoneValid = true
        }
        
        if selectedScreen > 3 {
            vm.firstName = "John"
            vm.lastName = "Doe"
            
            if selectedFlow == .company {
                vm.companyName = "OPS Construction Inc"
                vm.companyEmail = "info@opsconstruction.com"
                vm.companyPhone = "5559876543"
            }
        }
        
        if selectedScreen > 4 {
            if selectedFlow != .company {
                vm.companyCode = "OPS123"
                vm.isCompanyJoined = true
                vm.companyName = "Demo Construction Co." // For welcome phase
            } else {
                vm.companyIndustry = .carpentry
                vm.companySize = .sixToTen
                vm.companyAge = .fiveToTen
            }
        }
        
        return vm
    }
    
    // Employee flow screens (8 steps total)
    var employeeFlowScreens: [(name: String, view: AnyView)] {
        [
            ("Welcome", AnyView(WelcomeView(viewModel: mockViewModel))),
            ("User Type", AnyView(UserTypeSelectionView().environmentObject(mockViewModel))),
            ("Account Setup", AnyView(EmailView(viewModel: mockViewModel, isInConsolidatedFlow: true))),
            ("Organization Join", AnyView(OrganizationJoinView(viewModel: mockViewModel, isInConsolidatedFlow: true))),
            ("User Details", AnyView(UserInfoView(viewModel: mockViewModel, isInConsolidatedFlow: false))),
            ("Company Code", AnyView(CompanyCodeInputView(viewModel: mockViewModel))),
            ("Permissions", AnyView(PermissionsView(viewModel: mockViewModel, isInConsolidatedFlow: true))),
            ("Field Setup", AnyView(FieldSetupView(viewModel: mockViewModel))),
            ("Complete", AnyView(CompletionView(onComplete: {}))),
            ("Welcome Guide", AnyView(WelcomeGuideView().environmentObject(mockViewModel)))
        ]
    }
    
    // Original flow screens (11 steps)
    var originalFlowScreens: [(name: String, view: AnyView)] {
        [
            ("Welcome", AnyView(WelcomeView(viewModel: mockViewModel))),
            ("Email", AnyView(EmailView(viewModel: mockViewModel))),
            ("Password", AnyView(PasswordView(viewModel: mockViewModel))),
            ("User Info", AnyView(UserInfoView(viewModel: mockViewModel))),
            ("Phone", AnyView(PhoneNumberView(viewModel: mockViewModel))),
            ("Company Code", AnyView(CompanyCodeInputView(viewModel: mockViewModel))),
            ("Field Setup", AnyView(FieldSetupView(viewModel: mockViewModel))),
            ("Permissions", AnyView(PermissionsView(viewModel: mockViewModel))),
            ("Complete", AnyView(CompletionView(onComplete: {})))
        ]
    }
    
    // Company flow screens (10 steps total)
    var companyFlowScreens: [(name: String, view: AnyView)] {
        [
            ("Welcome", AnyView(WelcomeView(viewModel: mockViewModel))),
            ("User Type", AnyView(UserTypeSelectionView().environmentObject(mockViewModel))),
            ("Account Setup", AnyView(EmailView(viewModel: mockViewModel, isInConsolidatedFlow: true))),
            ("User Details", AnyView(UserInfoView(viewModel: mockViewModel, isInConsolidatedFlow: false))),
            ("Basic Info", AnyView(CompanyBasicInfoView(isInConsolidatedFlow: true).environmentObject(mockViewModel))),
            ("Address", AnyView(CompanyAddressView(isInConsolidatedFlow: true).environmentObject(mockViewModel))),
            ("Contact", AnyView(CompanyContactView().environmentObject(mockViewModel))),
            ("Details", AnyView(CompanyDetailsView().environmentObject(mockViewModel))),
            ("Company Code", AnyView(CompanyCodeDisplayView(viewModel: mockViewModel))),
            ("Team Invites", AnyView(TeamInvitesView().environmentObject(mockViewModel))),
            ("Permissions", AnyView(PermissionsView(viewModel: mockViewModel, isInConsolidatedFlow: true))),
            ("Field Setup", AnyView(FieldSetupView(viewModel: mockViewModel))),
            ("Complete", AnyView(CompletionView(onComplete: {}))),
            ("Welcome Guide", AnyView(WelcomeGuideView().environmentObject(mockViewModel)))
        ]
    }
}

// MARK: - Device Frame Component
struct DeviceFrame<Content: View>: View {
    let scale: CGFloat
    let content: Content
    
    init(scale: CGFloat, @ViewBuilder content: () -> Content) {
        self.scale = scale
        self.content = content()
    }
    
    var body: some View {
        ZStack {
            // iPhone frame
            RoundedRectangle(cornerRadius: 40)
                .strokeBorder(Color.gray, lineWidth: 12)
                .background(
                    RoundedRectangle(cornerRadius: 40)
                        .fill(Color.black)
                )
                .overlay(
                    // Dynamic Island
                    Capsule()
                        .frame(width: 120, height: 35)
                        .foregroundColor(Color.black)
                        .offset(y: -UIScreen.main.bounds.height / 2 + 60)
                )
                .frame(width: 390, height: 844)
                .scaleEffect(scale)
            
            // Screen content
            content
                .frame(width: 390, height: 844)
                .clipShape(RoundedRectangle(cornerRadius: 35))
                .scaleEffect(scale)
        }
    }
}

// MARK: - Individual Screen Previews
struct OnboardingScreenPreviews: PreviewProvider {
    static var previews: some View {
        // Main navigator
        OnboardingFlowPreview()
            .previewDisplayName("Flow Navigator")
    }
    
    static func mockViewModelWithUserType() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.selectedUserType = .employee
        return vm
    }
    
    static func mockViewModelWithEmail() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.email = "test@"
        vm.password = "pass"
        return vm
    }
    
    static func mockViewModelWithPhone() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.phoneNumber = "555123"
        return vm
    }
    
    static func mockViewModelWithCode() -> OnboardingViewModel {
        let vm = OnboardingViewModel()
        vm.companyCode = "OPS"
        vm.isLoading = false
        return vm
    }
}

// MARK: - Device Size Testing
struct OnboardingDeviceSizePreview: PreviewProvider {
    static var previews: some View {
        Group {
            // Different device sizes
            ForEach(["iPhone 15 Pro", "iPhone 15 Pro Max", "iPhone SE (3rd generation)"], id: \.self) { device in
                OnboardingPresenter()
                    .environmentObject(OnboardingPreviewHelpers.createPreviewDataController())
                    .environmentObject(OnboardingViewModel())
                    .preferredColorScheme(.dark)
                    .previewDevice(PreviewDevice(rawValue: device))
                    .previewDisplayName(device)
            }
        }
    }
}

// MARK: - Preview Provider
struct OnboardingFlowPreview_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingFlowPreview()
            .preferredColorScheme(.dark)
    }
}

// MARK: - State Testing Preview
struct OnboardingStateTestingPreview: View {
    @StateObject private var viewModel = OnboardingViewModel()
    
    var body: some View {
        VStack {
            // State controls
            VStack(alignment: .leading, spacing: 12) {
                Text("State Testing").font(.headline)
                
                Toggle("Is Signed Up", isOn: $viewModel.isSignedUp)
                Toggle("Is Loading", isOn: $viewModel.isLoading)
                Toggle("Has Error", isOn: .constant(!viewModel.errorMessage.isEmpty))
                
                if !viewModel.errorMessage.isEmpty {
                    Text("Error: \(viewModel.errorMessage)")
                        .font(.caption)
                        .foregroundColor(.red)
                }
                
                HStack {
                    Text("User Type:")
                    Picker("Type", selection: $viewModel.selectedUserType) {
                        Text("None").tag(UserType?.none)
                        Text("Employee").tag(UserType?.some(.employee))
                        Text("Company").tag(UserType?.some(.company))
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // Preview current state
            AccountSetupView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("State Testing") {
    OnboardingStateTestingPreview()
}

#Preview("Main Flow") {
    OnboardingFlowPreview()
}
