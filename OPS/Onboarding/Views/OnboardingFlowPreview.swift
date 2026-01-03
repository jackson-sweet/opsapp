//
//  OnboardingFlowPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-11-17.
//

import SwiftUI

// MARK: - Complete Onboarding Flow Preview
/// Shows all screens in sequence based on selected user type and flow
struct OnboardingFlowPreview: View {
    @State private var currentFlowType: FlowType = .employeeConsolidated
    @State private var scale: CGFloat = 0.5
    
    enum FlowType: String, CaseIterable {
        case employeeConsolidated = "Employee"
        case companyConsolidated = "Company Owner"
        
        var displayName: String { rawValue }
    }
    
    // Create mock view models for each flow type
    private var mockViewModel: OnboardingViewModel {
        let vm = OnboardingViewModel()
        // Configure the view model based on flow type
        switch currentFlowType {
        case .employeeConsolidated:
            vm.selectedUserType = .employee
        case .companyConsolidated:
            vm.selectedUserType = .company
        }
        vm.email = "user@example.com"
        vm.password = "password123"
        vm.firstName = "John"
        vm.lastName = "Doe"
        vm.phoneNumber = "5551234567"
        vm.companyName = "Demo Company, Inc."
        vm.companyCode = "DEMO123"
        return vm
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Controls
                VStack(spacing: 16) {
                    // Flow type selector
                    Picker("Flow Type", selection: $currentFlowType) {
                        ForEach(FlowType.allCases, id: \.self) { flow in
                            Text(flow.displayName).tag(flow)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)
                    
                    // Scale control
                    HStack {
                        Text("Scale:")
                        Slider(value: $scale, in: 0.3...1.0, step: 0.1)
                        Text("\(Int(scale * 100))%")
                            .frame(width: 50)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
                .background(Color.gray.opacity(0.1))
                
                // Flow display
                ScrollView {
                    VStack(spacing: 24) {
                        ForEach(Array(currentScreens.enumerated()), id: \.0) { index, screen in
                            VStack(spacing: 8) {
                                // Step indicator
                                HStack {
                                    Text("Step \(index + 1)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(screen.name)
                                        .font(.headline)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                
                                // Screen preview
                                DeviceFrame(scale: scale) {
                                    screen.view
                                        .environmentObject(DataController())
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Onboarding Flow Preview")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    // Current screens based on selected flow
    private var currentScreens: [(name: String, view: AnyView)] {
        switch currentFlowType {
        case .employeeConsolidated:
            return employeeConsolidatedFlowScreens
        case .companyConsolidated:
            return companyFlowScreens
        }
    }
    
    // Employee consolidated flow screens (7 steps)
    var employeeConsolidatedFlowScreens: [(name: String, view: AnyView)] {
        [
            ("Welcome", AnyView(WelcomeView(viewModel: mockViewModel))),
            ("User Type", AnyView(UserTypeSelectionView().environmentObject(mockViewModel))),
            ("Account Setup", AnyView(EmailView(viewModel: mockViewModel))),
            ("Organization Join", AnyView(OrganizationJoinView(viewModel: mockViewModel))),
            ("User Details", AnyView(UserInfoView(viewModel: mockViewModel))),
            ("Company Code", AnyView(CompanyCodeInputView(viewModel: mockViewModel))),
            ("Permissions", AnyView(PermissionsView(viewModel: mockViewModel))),
            ("Field Setup", AnyView(FieldSetupView(viewModel: mockViewModel))),
            ("Complete", AnyView(CompletionView(onComplete: {})))
        ]
    }

    // Company flow screens (10 steps total)
    var companyFlowScreens: [(name: String, view: AnyView)] {
        [
            ("Welcome", AnyView(WelcomeView(viewModel: mockViewModel))),
            ("User Type", AnyView(UserTypeSelectionView().environmentObject(mockViewModel))),
            ("Account Setup", AnyView(EmailView(viewModel: mockViewModel))),
            ("User Details", AnyView(UserInfoView(viewModel: mockViewModel))),
            ("Basic Info", AnyView(CompanyBasicInfoView().environmentObject(mockViewModel))),
            ("Address", AnyView(CompanyAddressView().environmentObject(mockViewModel))),
            ("Contact", AnyView(CompanyContactView().environmentObject(mockViewModel))),
            ("Details", AnyView(CompanyDetailsView().environmentObject(mockViewModel))),
            ("Company Code", AnyView(CompanyCodeDisplayView(viewModel: mockViewModel))),
            ("Team Invites", AnyView(TeamInvitesView().environmentObject(mockViewModel))),
            ("Permissions", AnyView(PermissionsView(viewModel: mockViewModel))),
            ("Field Setup", AnyView(FieldSetupView(viewModel: mockViewModel))),
            ("Complete", AnyView(CompletionView(onComplete: {})))
        ]
    }
}

// MARK: - Device Frame Component
struct DeviceFrame<Content: View>: View {
    let scale: CGFloat
    let content: Content
    
    init(scale: CGFloat = 0.5, @ViewBuilder content: () -> Content) {
        self.scale = scale
        self.content = content()
    }
    
    var body: some View {
        let deviceWidth: CGFloat = 390
        let deviceHeight: CGFloat = 844
        
        ZStack {
            // Device bezel
            RoundedRectangle(cornerRadius: 40 * scale)
                .fill(Color.black)
                .frame(width: deviceWidth * scale, height: deviceHeight * scale)
                .overlay(
                    RoundedRectangle(cornerRadius: 40 * scale)
                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                )
            
            // Screen area
            RoundedRectangle(cornerRadius: 35 * scale)
                .fill(Color.black)
                .frame(width: (deviceWidth - 20) * scale, height: (deviceHeight - 20) * scale)
                .overlay(
                    content
                        .frame(width: (deviceWidth - 20) * scale, height: (deviceHeight - 20) * scale)
                        .clipped()
                        .scaleEffect(scale)
                        .frame(width: (deviceWidth - 20) * scale, height: (deviceHeight - 20) * scale)
                )
        }
        .shadow(radius: 10)
    }
}

// MARK: - Individual Screen Preview
/// Preview wrapper for individual screens
struct OnboardingScreenPreview<Content: View>: View {
    let title: String
    let content: Content
    @State private var scale: CGFloat = 0.7
    
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Title and controls
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack {
                    Text("Scale:")
                    Slider(value: $scale, in: 0.3...1.0, step: 0.1)
                    Text("\(Int(scale * 100))%")
                        .frame(width: 50)
                }
                .frame(maxWidth: 400)
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // Preview
            ScrollView {
                DeviceFrame(scale: scale) {
                    content
                        .environmentObject(DataController())
                }
                .padding()
            }
        }
    }
}

// MARK: - State Testing Preview
/// Interactive preview for testing state management
struct OnboardingStateTestingPreview: View {
    @StateObject private var viewModel = OnboardingViewModel()
    @StateObject private var dataController = DataController()
    @State private var selectedUserType: UserType = .employee
    
    var body: some View {
        VStack {
            // State controls
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // User type selector
                    HStack {
                        Text("User Type:")
                        Picker("User Type", selection: $selectedUserType) {
                            Text("Employee").tag(UserType.employee)
                            Text("Company Owner").tag(UserType.company)
                        }
                        .pickerStyle(SegmentedPickerStyle())
                        .onChange(of: selectedUserType) { newValue in
                            viewModel.selectedUserType = newValue
                        }
                    }
                    
                    // Current step display
                    HStack {
                        Text("Current Step:")
                        Text(String(describing: viewModel.currentStep))
                            .fontWeight(.semibold)
                    }
                    
                    // Test data
                    Group {
                        TextField("Email", text: $viewModel.email)
                        TextField("First Name", text: $viewModel.firstName)
                        TextField("Last Name", text: $viewModel.lastName)
                        TextField("Phone", text: $viewModel.phoneNumber)
                        TextField("Company Name", text: $viewModel.companyName)
                        TextField("Company Code", text: $viewModel.companyCode)
                    }
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    
                    // Navigation controls
                    HStack {
                        Button("Previous") { viewModel.moveToPreviousStep() }
                        Button("Next") { viewModel.moveToNextStep() }
                        Button("Reset") {
                            viewModel.currentStep = .welcome
                            viewModel.selectedUserType = nil
                        }
                    }
                    
                    // Step selector
                    Picker("Jump to Step", selection: $viewModel.currentStep) {
                        Text("Welcome").tag(OnboardingStep.welcome)
                        Text("User Type").tag(OnboardingStep.userTypeSelection)
                        Text("Account Setup").tag(OnboardingStep.accountSetup)
                        Text("User Details").tag(OnboardingStep.userDetails)
                        Text("Company Code").tag(OnboardingStep.companyCode)
                        Text("Permissions").tag(OnboardingStep.permissions)
                        Text("Field Setup").tag(OnboardingStep.fieldSetup)
                        Text("Complete").tag(OnboardingStep.completion)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            
            // Preview current state
            EmailView(viewModel: viewModel)
                .preferredColorScheme(.dark)
        }
    }
}

#Preview("State Testing") {
    OnboardingStateTestingPreview()
}

#Preview("Complete Flow") {
    OnboardingFlowPreview()
        .preferredColorScheme(.dark)
}

#Preview("Welcome Screen") {
    OnboardingScreenPreview("Welcome Screen") {
        WelcomeView(viewModel: OnboardingViewModel())
            .preferredColorScheme(.dark)
    }
}

#Preview("User Type Selection") {
    OnboardingScreenPreview("User Type Selection") {
        UserTypeSelectionView()
            .environmentObject(OnboardingViewModel())
            .preferredColorScheme(.dark)
    }
}