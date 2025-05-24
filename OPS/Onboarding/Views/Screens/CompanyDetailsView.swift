import SwiftUI

struct CompanyDetailsView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var selectedIndustry: Industry?
    @State private var selectedSize: CompanySize?
    @State private var selectedAge: CompanyAge?
    @State private var showingIndustryPicker = false
    @State private var searchText = ""
    
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
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Company Details",
                subtitle: "Step 4 of 6",
                showBackButton: true,
                onBack: {
                    onboardingViewModel.previousStep()
                }
            )
            
            ScrollView {
                VStack(spacing: 32) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Tell us about your business")
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(Color("TextPrimary"))
                        
                        Text("This helps us match you with relevant projects and opportunities.")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(Color("TextSecondary"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(spacing: 24) {
                        // Industry Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Primary Industry")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            Button(action: {
                                showingIndustryPicker = true
                            }) {
                                HStack {
                                    Text(selectedIndustry?.displayName ?? "Select your industry")
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(selectedIndustry != nil ? Color("TextPrimary") : Color("TextSecondary"))
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 14, weight: .medium))
                                        .foregroundColor(Color("TextSecondary"))
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("StatusInactive"), lineWidth: 1)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(Color("CardBackground"))
                                        )
                                )
                            }
                        }
                        
                        // Company Size Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Company Size")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            VStack(spacing: 8) {
                                ForEach(CompanySize.allCases, id: \.self) { size in
                                    Button(action: {
                                        selectedSize = size
                                    }) {
                                        HStack {
                                            Text(size.displayName)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(Color("TextPrimary"))
                                            
                                            Spacer()
                                            
                                            if selectedSize == size {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(Color("AccentPrimary"))
                                            } else {
                                                Circle()
                                                    .stroke(Color("StatusInactive"), lineWidth: 1)
                                                    .frame(width: 20, height: 20)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedSize == size ? Color("AccentPrimary").opacity(0.1) : Color("CardBackground"))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(selectedSize == size ? Color("AccentPrimary") : Color("StatusInactive"), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                        
                        // Company Age Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("How long has your company been in business?")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(Color("TextPrimary"))
                            
                            VStack(spacing: 8) {
                                ForEach(CompanyAge.allCases, id: \.self) { age in
                                    Button(action: {
                                        selectedAge = age
                                    }) {
                                        HStack {
                                            Text(age.displayName)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(Color("TextPrimary"))
                                            
                                            Spacer()
                                            
                                            if selectedAge == age {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.system(size: 20))
                                                    .foregroundColor(Color("AccentPrimary"))
                                            } else {
                                                Circle()
                                                    .stroke(Color("StatusInactive"), lineWidth: 1)
                                                    .frame(width: 20, height: 20)
                                            }
                                        }
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .background(
                                            RoundedRectangle(cornerRadius: 8)
                                                .fill(selectedAge == age ? Color("AccentPrimary").opacity(0.1) : Color("CardBackground"))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8)
                                                        .stroke(selectedAge == age ? Color("AccentPrimary") : Color("StatusInactive"), lineWidth: 1)
                                                )
                                        )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 120)
            }
            
            VStack(spacing: 16) {
                Button(action: {
                    onboardingViewModel.companyIndustry = selectedIndustry
                    onboardingViewModel.companySize = selectedSize
                    onboardingViewModel.companyAge = selectedAge
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
        .sheet(isPresented: $showingIndustryPicker) {
            IndustryPickerView(selectedIndustry: $selectedIndustry, searchText: $searchText, filteredIndustries: filteredIndustries)
        }
        .onAppear {
            selectedIndustry = onboardingViewModel.companyIndustry
            selectedSize = onboardingViewModel.companySize
            selectedAge = onboardingViewModel.companyAge
        }
    }
    
    private var isFormValid: Bool {
        selectedIndustry != nil && selectedSize != nil && selectedAge != nil
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
                        .foregroundColor(Color("TextSecondary"))
                    
                    TextField("Search industries...", text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(Color("TextPrimary"))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color("CardBackground"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color("StatusInactive"), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // Industry List
                List(filteredIndustries, id: \.self) { industry in
                    Button(action: {
                        selectedIndustry = industry
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        HStack {
                            Text(industry.displayName)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(Color("TextPrimary"))
                            
                            Spacer()
                            
                            if selectedIndustry == industry {
                                Image(systemName: "checkmark")
                                    .foregroundColor(Color("AccentPrimary"))
                                    .font(.system(size: 16, weight: .semibold))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(PlainButtonStyle())
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
    CompanyDetailsView()
        .environmentObject(OnboardingViewModel())
}