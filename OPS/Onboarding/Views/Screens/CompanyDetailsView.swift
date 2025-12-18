import SwiftUI

struct CompanyDetailsView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var selectedIndustry: Industry?
    @State private var selectedSize: CompanySize?
    @State private var selectedAge: CompanyAge?
    @State private var showingIndustryPicker = false
    @State private var searchText = ""
    @State private var currentPhase: CompanyDetailsPhase = .industry
    
    enum CompanyDetailsPhase: Int, CaseIterable {
        case industry = 0
        case size = 1
        case age = 2
    }
    
    // Calculate the current step number based on user type
    private var currentStepNumber: Int {
        return onboardingViewModel.currentStep.stepNumber(for: onboardingViewModel.selectedUserType) ?? 6
    }
    
    private var totalSteps: Int {
        guard let userType = onboardingViewModel.selectedUserType else { return 12 }
        return OnboardingStep.totalSteps(for: userType)
    }
    
    var filteredIndustries: [Industry] {
        if searchText.isEmpty {
            return Industry.allCases
        } else {
            return Industry.allCases.filter { industry in
                industry.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
    
    var body: some View {
        ZStack {
            // Background color - conditional theming
            (onboardingViewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Navigation header
                HStack {
                    Button(action: {
                        if currentPhase == .industry {
                            onboardingViewModel.moveToPreviousStep()
                        } else {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPhase = CompanyDetailsPhase(rawValue: currentPhase.rawValue - 1) ?? .industry
                            }
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                                .font(OPSStyle.Typography.button)
                            Text("Back")
                                .font(OPSStyle.Typography.button)
                        }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        onboardingViewModel.logoutAndReturnToLogin()
                    }) {
                        Text("Cancel")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                // Step indicator bars
                HStack(spacing: 4) {
                    ForEach(0..<totalSteps, id: \.self) { step in
                        Rectangle()
                            .fill(step < currentStepNumber ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText.opacity(0.3))
                            .frame(height: 2)
                    }
                }
                .padding(.bottom, 16)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                
                // Content area with phases - top-justified
                VStack(spacing: 0) {
                    VStack(spacing: 24) {
                        // Phase content
                        Group {
                        switch currentPhase {
                        case .industry:
                            IndustryPhaseView(
                                selectedIndustry: $selectedIndustry,
                                showingIndustryPicker: $showingIndustryPicker,
                                onContinue: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentPhase = .size
                                    }
                                }
                            )
                        case .size:
                            SizePhaseView(
                                selectedSize: $selectedSize,
                                onContinue: {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        currentPhase = .age
                                    }
                                }
                            )
                        case .age:
                            AgePhaseView(
                                selectedAge: $selectedAge,
                                onContinue: {
                                    onboardingViewModel.companyIndustry = selectedIndustry
                                    onboardingViewModel.companySize = selectedSize
                                    onboardingViewModel.companyAge = selectedAge

                                    // Show loading screen and create company
                                    onboardingViewModel.isShowingCompanyCreationLoading = true

                                    Task {
                                        do {
                                            try await onboardingViewModel.createCompany()
                                            // Don't move to next step here - loading view will handle it
                                        } catch {
                                            await MainActor.run {
                                                // Hide loading on error
                                                onboardingViewModel.isShowingCompanyCreationLoading = false
                                                // Error is already set in viewModel
                                            }
                                        }
                                    }
                                }
                            )
                        }
                        }
                        .transition(.opacity)
                    }

                    Spacer()
                }
                .padding(40)
            }
            .sheet(isPresented: $showingIndustryPicker) {
                IndustryPickerView(selectedIndustry: $selectedIndustry, searchText: $searchText, filteredIndustries: filteredIndustries)
            }
            .onAppear {
                selectedIndustry = onboardingViewModel.companyIndustry
                selectedSize = onboardingViewModel.companySize
                selectedAge = onboardingViewModel.companyAge
            }
        }
        .dismissKeyboardOnTap()
    }
}

// MARK: - Phase Views

struct IndustryPhaseView: View {
    @Binding var selectedIndustry: Industry?
    @Binding var showingIndustryPicker: Bool
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("WHAT'S YOUR")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("INDUSTRY?")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.bottom, 12)
                
                Text("Helps us prioritize what to build next.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // Industry Selection
            VStack(alignment: .leading, spacing: 8) {
                Button(action: {
                    showingIndustryPicker = true
                }) {
                    HStack {
                        Text(selectedIndustry?.displayName ?? "Select your industry")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(selectedIndustry != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                        
                        Spacer()
                        
                        Image(systemName: "chevron.down")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(OPSStyle.Colors.cardBackground)
                            )
                    )
                }
            }
        }
        
        Spacer()
        
        // Continue button
        VStack {
            Button(action: onContinue) {
                Text("CONTINUE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedIndustry != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(selectedIndustry == nil)
        }
        }
    }

struct SizePhaseView: View {
    @Binding var selectedSize: CompanySize?
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW BIG")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("IS YOUR CREW?")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.bottom, 12)
                
                Text("Helps us understand your crew size.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // Size Selection
            VStack(spacing: 12) {
                ForEach(CompanySize.allCases, id: \.self) { size in
                    Button(action: {
                        selectedSize = size
                    }) {
                        HStack {
                            Text(size.displayName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Spacer()
                            
                            if selectedSize == size {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(OPSStyle.Typography.subtitle)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            } else {
                                Circle()
                                    .stroke(OPSStyle.Colors.secondaryText.opacity(0.3), lineWidth: 1)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(selectedSize == size ? OPSStyle.Colors.primaryAccent.opacity(0.1) : OPSStyle.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(selectedSize == size ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        
        Spacer()
        
        // Continue button
        VStack {
            Button(action: onContinue) {
                Text("CONTINUE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedSize != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .disabled(selectedSize == nil)
        }
    }
}

struct AgePhaseView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @Binding var selectedAge: CompanyAge?
    let onContinue: () -> Void
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(alignment: .leading, spacing: 8) {
                Text("HOW LONG HAVE")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("YOU BEEN RUNNING?")
                    .font(OPSStyle.Typography.largeTitle.weight(.bold))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.bottom, 12)
                
                Text("Tells us about your experience.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineSpacing(4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 30)
            
            // Age Selection
            VStack(spacing: 12) {
                ForEach(CompanyAge.allCases, id: \.self) { age in
                    Button(action: {
                        selectedAge = age
                    }) {
                        HStack {
                            Text(age.displayName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                            
                            Spacer()
                            
                            if selectedAge == age {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(OPSStyle.Typography.subtitle)
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                            } else {
                                Circle()
                                    .stroke(OPSStyle.Colors.secondaryText.opacity(0.3), lineWidth: 1)
                                    .frame(width: 20, height: 20)
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.vertical, 16)
                        .background(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(selectedAge == age ? OPSStyle.Colors.primaryAccent.opacity(0.1) : OPSStyle.Colors.cardBackground)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(selectedAge == age ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // Error message
            if !onboardingViewModel.errorMessage.isEmpty {
                Text(onboardingViewModel.errorMessage)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(Color("StatusError"))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
        }
        
        Spacer()
        
        // Continue button
        VStack {
            Button(action: onContinue) {
                if onboardingViewModel.isLoading {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .black))
                            .scaleEffect(0.8)
                        Text("Creating company...")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(.black)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                } else {
                    Text("CONTINUE")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(selectedAge != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            .disabled(selectedAge == nil || onboardingViewModel.isLoading)
        }
        }
    }

struct IndustryPickerView: View {
    @Binding var selectedIndustry: Industry?
    @Binding var searchText: String
    let filteredIndustries: [Industry]
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    TextField("Search industries...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackground)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        )
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, 16)
                
                // Industry List
                List(filteredIndustries, id: \.self) { industry in
                    HStack {
                        Text(industry.displayName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Spacer()
                        
                        if selectedIndustry == industry {
                            Image(systemName: "checkmark")
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .font(OPSStyle.Typography.bodyBold)
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedIndustry = industry
                        presentationMode.wrappedValue.dismiss()
                    }
                }
                .listStyle(PlainListStyle())
            }
            .navigationTitle("Select Industry")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(trailing: Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            })
        }
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    CompanyDetailsView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}
