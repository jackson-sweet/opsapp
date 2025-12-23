//
//  CompanyDetailsScreen.swift
//  OPS
//
//  Company details screen - page 2: industry, size, age.
//  Part of the company creator flow.
//  Uses phased animation system for entrance effects.
//

import SwiftUI

struct CompanyDetailsScreen: View {
    @ObservedObject var manager: OnboardingManager
    @EnvironmentObject var dataController: DataController

    @State private var selectedIndustry: Industry?
    @State private var customIndustry: String = ""
    @State private var selectedSize: CompanySize?
    @State private var selectedAge: CompanyAge?
    @State private var showIndustryPicker = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @FocusState private var isCustomIndustryFocused: Bool

    // Animation coordinator
    @StateObject private var animationCoordinator = OnboardingAnimationCoordinator()

    /// The industry value to send to Bubble (either selected industry or custom text)
    private var industryValue: String {
        if selectedIndustry == .other {
            return customIndustry.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return selectedIndustry?.rawValue ?? ""
    }

    /// Display text for the industry picker button
    private var industryDisplayText: String {
        if let industry = selectedIndustry {
            if industry == .other && !customIndustry.isEmpty {
                return customIndustry
            }
            return industry.displayName
        }
        return "Select your trade"
    }

    private var isFormValid: Bool {
        guard selectedIndustry != nil,
              selectedSize != nil,
              selectedAge != nil else { return false }

        // If "Other" is selected, require custom text
        if selectedIndustry == .other {
            return !customIndustry.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with back and sign out
            OnboardingHeader(
                showBack: true,
                onBack: { manager.goToScreen(.companySetup) },
                onSignOut: { manager.signOut() }
            )
            .padding(.horizontal, 40)
            .padding(.top, 16)

            // Title section with phased typing animation
            PhasedOnboardingHeader(
                title: "ALMOST DONE",
                subtitle: "Quick details to set you up right.",
                coordinator: animationCoordinator
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 16)

            Spacer()
                .frame(height: 32)

            // Content section - fades in upward
            PhasedContent(coordinator: animationCoordinator) {
                VStack(spacing: 0) {
                    // Industry picker
                    VStack(alignment: .leading, spacing: 8) {
                        PhasedLabel("WHAT DO YOU DO?", index: 0, coordinator: animationCoordinator)

                        Button {
                            showIndustryPicker = true
                        } label: {
                            HStack {
                                Text(industryDisplayText)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(selectedIndustry != nil ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)

                                Spacer()

                                Image(systemName: "chevron.down")
                                    .font(.system(size: 14))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 16)
                            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
                            )
                        }

                        // Custom industry text field (shown when "Other" is selected)
                        if selectedIndustry == .other {
                            TextField("Enter your trade", text: $customIndustry)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .focused($isCustomIndustryFocused)
                                .padding(.vertical, 14)
                                .padding(.horizontal, 16)
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                                )
                                .onAppear {
                                    // Auto-focus the text field when "Other" is selected
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                        isCustomIndustryFocused = true
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, 40)

                    // Company Size section
                    PhasedLabel("HOW MANY ON YOUR CREW?", index: 1, coordinator: animationCoordinator)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)

                    // Company Size pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CompanySize.allCases, id: \.self) { size in
                                PillButton(
                                    title: size.rawValue,
                                    isSelected: selectedSize == size
                                ) {
                                    selectedSize = size
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.top, 8)

                    // Company Age section
                    PhasedLabel("HOW LONG IN BUSINESS?", index: 2, isLast: true, coordinator: animationCoordinator)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 40)
                        .padding(.top, 24)

                    // Company Age pills
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(CompanyAge.allCases, id: \.self) { age in
                                PillButton(
                                    title: age.rawValue,
                                    isSelected: selectedAge == age
                                ) {
                                    selectedAge = age
                                }
                            }
                        }
                        .padding(.horizontal, 40)
                    }
                    .padding(.top, 8)

                    // Error message
                    if let error = errorMessage {
                        Text(error)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.errorStatus)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 40)
                            .padding(.top, 16)
                    }
                }
            }

            Spacer()

            // Create button with phased animation
            PhasedPrimaryButton(
                "CREATE COMPANY",
                isEnabled: isFormValid,
                isLoading: isCreating,
                loadingText: "Creating...",
                coordinator: animationCoordinator
            ) {
                createCompany()
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 50)
        }
        .background(OPSStyle.Colors.background)
        .sheet(isPresented: $showIndustryPicker) {
            IndustryPickerSheet(
                selection: $selectedIndustry,
                isPresented: $showIndustryPicker
            )
        }
        .onAppear {
            prefillData()
            animationCoordinator.start()
        }
    }

    // MARK: - Actions

    private func prefillData() {
        let companyData = manager.state.companyData
        if !companyData.industry.isEmpty {
            selectedIndustry = Industry.allCases.first { $0.rawValue == companyData.industry }
        }
        if !companyData.size.isEmpty {
            selectedSize = CompanySize.allCases.first { $0.rawValue == companyData.size }
        }
        if !companyData.age.isEmpty {
            selectedAge = CompanyAge.allCases.first { $0.rawValue == companyData.age }
        }
    }

    private func createCompany() {
        guard isFormValid else { return }

        // Save to state (use industryValue for custom industries)
        manager.state.companyData.industry = industryValue
        manager.state.companyData.size = selectedSize?.rawValue ?? ""
        manager.state.companyData.age = selectedAge?.rawValue ?? ""

        isCreating = true
        errorMessage = nil

        Task {
            do {
                let _ = try await manager.createCompany()
                await MainActor.run {
                    isCreating = false
                    manager.goToScreen(.companyCode)
                }
            } catch {
                await MainActor.run {
                    isCreating = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Industry Picker Sheet

struct IndustryPickerSheet: View {
    @Binding var selection: Industry?
    @Binding var isPresented: Bool
    @State private var searchText = ""

    /// Standard industries (excluding "Other"), filtered by search
    private var filteredIndustries: [Industry] {
        let standardCases = Industry.standardCases
        if searchText.isEmpty {
            return standardCases.sorted { $0.displayName < $1.displayName }
        }
        return standardCases
            .filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
            .sorted { $0.displayName < $1.displayName }
    }

    /// Whether to show the "Other" option (always show unless search has no match and doesn't contain "other")
    private var showOtherOption: Bool {
        searchText.isEmpty || "other".localizedCaseInsensitiveContains(searchText)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    TextField("Search trades...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)

                // Industry list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Standard industries
                        ForEach(filteredIndustries) { industry in
                            IndustryRow(
                                industry: industry,
                                isSelected: selection == industry
                            ) {
                                selection = industry
                                isPresented = false
                            }
                        }

                        // "Other" option at the bottom
                        if showOtherOption {
                            // Separator before "Other"
                            if !filteredIndustries.isEmpty {
                                Rectangle()
                                    .fill(Color.white.opacity(0.05))
                                    .frame(height: 8)
                            }

                            IndustryRow(
                                industry: .other,
                                isSelected: selection == .other,
                                subtitle: "Enter your own trade"
                            ) {
                                selection = .other
                                isPresented = false
                            }
                        }
                    }
                }
            }
            .background(OPSStyle.Colors.background)
            .navigationTitle("SELECT YOUR TRADE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        isPresented = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }
}

/// Row item for industry picker
private struct IndustryRow: View {
    let industry: Industry
    let isSelected: Bool
    var subtitle: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(industry.displayName)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if let subtitle = subtitle {
                        Text(subtitle)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }

        Divider()
            .background(Color.white.opacity(0.1))
    }
}

#Preview {
    let dataController = DataController()
    let manager = OnboardingManager(dataController: dataController)
    manager.selectFlow(.companyCreator)

    return CompanyDetailsScreen(manager: manager)
        .environmentObject(dataController)
}
