//
//  OrganizationSettingsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-02.
//

import Foundation
import SwiftData
import SwiftUI

struct OrganizationSettingsView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var organization: Company?
    @State private var teamMembers: [User] = []
    @State private var isLoading = true
    @State private var isRefreshing = false
    @State private var showSeatManagement = false
    @State private var showPlanSelection = false
    @State private var showColorPicker = false
    @State private var selectedColor: Color = Color(hex: "#9CA3AF") ?? .gray
    @State private var isUpdatingColor = false
    
    // Computed property to check if current user is a company admin
    private var isCompanyAdmin: Bool {
        // Check using the new isCompanyAdmin property OR platform admin role
        return dataController.currentUser?.isCompanyAdmin == true || dataController.currentUser?.role == .admin
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
            .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header area - fixed, not part of scroll view
                SettingsHeader(
                    title: "Organization",
                    onBackTapped: {
                        dismiss()
                    }
                )
                .padding(.bottom, 8)
                .overlay(
                    // Refresh indicator in top right
                    Group {
                        if isRefreshing {
                            HStack {
                                Spacer()
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                    .scaleEffect(0.8)
                                Text("Updating...")
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                            .padding(.trailing, 20)
                        }
                    },
                    alignment: .trailing
                )
                
                // Scrollable content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                    
                        if isLoading {
                            loadingView
                        } else {
                            // Company header - no card background, matches ProfileSettingsView style
                            if let company = organization {
                                VStack(alignment: .leading, spacing: 16) {
                                    HStack(alignment: .top, spacing: 16) {
                                        // Company logo uploader (only editable for admins)
                                        if isCompanyAdmin {
                                            ProfileImageUploader(
                                                config: ImageUploaderConfig(
                                                    currentImageURL: company.logoURL,
                                                    currentImageData: company.logoData,
                                                    placeholderText: String(company.name.prefix(1)),
                                                    size: 80,
                                                    shape: .roundedSquare(cornerRadius: 12),
                                                    allowDelete: true,
                                                    backgroundColor: OPSStyle.Colors.primaryAccent,
                                                    uploadButtonText: "UPLOAD LOGO"
                                                ),
                                                onUpload: { image in
                                                    try await dataController.uploadCompanyLogo(image, for: company)
                                                },
                                                onDelete: {
                                                    try await dataController.deleteCompanyLogo(for: company)
                                                }
                                            )
                                        } else {
                                            // Read-only logo for non-admins
                                            CompanyAvatar(company: company, size: 80)
                                        }

                                        VStack(alignment: .leading, spacing: 6) {
                                            // Company name
                                            Text(company.name)
                                                .font(OPSStyle.Typography.bodyBold)
                                                .foregroundColor(.white)

                                            // Company description - always show
                                            Text((company.companyDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?
                                                 company.companyDescription! : "NO DESCRIPTION")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor((company.companyDescription?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?
                                                                OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                                                .lineLimit(2)

                                            // Company address - always show
                                            Text((company.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?
                                                 company.address! : "NO ADDRESS")
                                                .font(OPSStyle.Typography.smallCaption)
                                                .foregroundColor((company.address?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ?
                                                                OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
                                        }

                                        Spacer()
                                    }
                                }
                                .padding(.horizontal, 20)
                            }
                            
                            // Subscription section
                            VStack(spacing: 16) {
                                SettingsSectionHeader(title: "SUBSCRIPTION")
                                
                                subscriptionCard
                            }
                            
                            // Organization details section
                            VStack(spacing: 24) {
                                SettingsSectionHeader(title: "CONTACT INFORMATION")
                                
                                // Business hours - always show
                                infoField(
                                    title: "Business Hours",
                                    value: (organization?.openHour != nil && organization?.closeHour != nil) ? 
                                           organization!.hoursDisplay : "NO BUSINESS HOURS",
                                    icon: "clock",
                                    isMissing: organization?.openHour == nil || organization?.closeHour == nil
                                )
                                
                                // Phone - always show
                                infoField(
                                    title: "Phone",
                                    value: (organization?.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.phone! : "NO PHONE NUMBER",
                                    icon: "phone",
                                    isMissing: organization?.phone?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                                
                                // Email - always show
                                infoField(
                                    title: "Email",
                                    value: (organization?.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.email! : "NO EMAIL ADDRESS",
                                    icon: "envelope",
                                    isMissing: organization?.email?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                                
                                // Website - always show
                                infoField(
                                    title: "Website",
                                    value: (organization?.website?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? 
                                           organization!.website! : "NO WEBSITE",
                                    icon: "globe",
                                    isMissing: organization?.website?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
                                )
                            }

                            // Project settings section (admin only)
                            if isCompanyAdmin {
                                VStack(spacing: 16) {
                                    SettingsSectionHeader(title: "PROJECT SETTINGS")

                                    defaultProjectColorPicker
                                }
                            }

                            // Team section
                            VStack(spacing: 16) {
                                SettingsSectionHeader(title: "TEAM MEMBERS")
                                
                                if let company = organization {
                                    // Use the new compact team view with sheets for details
                                    OrganizationTeamView(company: company)
                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                        .padding(.horizontal, 20)
                                } else if teamMembers.isEmpty {
                                    emptyTeamView
                                        .padding(.horizontal, 20)
                                } else {
                                    // Fallback to old view if we have teamMembers but no company
                                    ForEach(Array(zip(teamMembers.indices, teamMembers)), id: \.0) { index, member in
                                        memberRow(member: member)
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 40)
                    .padding(.top, 12)
                    .tabBarPadding() // Add padding for tab bar
                }

            }
        }
        .navigationBarBackButtonHidden(true)
        .onAppear {
            loadOrganizationData()
        }
        .sheet(isPresented: $showSeatManagement) {
            SeatManagementView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
                .environmentObject(dataController)
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Subscription Card
    
    @ViewBuilder
    private var subscriptionCard: some View {
        if let company = organization {
            VStack(spacing: 0) {
                // Current plan info - make tappable for company admins
                Button(action: {
                    if isCompanyAdmin {
                        showPlanSelection = true
                    }
                }) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        // Status and plan
                        HStack(spacing: 8) {
                            if let status = company.subscriptionStatus,
                               let statusEnum = SubscriptionStatus(rawValue: status) {
                                Circle()
                                    .fill(statusColor(for: statusEnum))
                                    .frame(width: 8, height: 8)
                                
                                Text(statusEnum.displayName.uppercased())
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(statusColor(for: statusEnum))
                            }
                            
                            if let plan = company.subscriptionPlan,
                               let planEnum = SubscriptionPlan(rawValue: plan) {
                                Text("•")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                
                                Text(planEnum.displayName.uppercased())
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                        }
                        
                        // Seat usage
                        let seatedCount = company.seatedEmployeeIds
                            .split(separator: ",")
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            .count
                        
                        HStack(spacing: 4) {
                            Image(systemName: OPSStyle.Icons.personTwoFill)
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("\(seatedCount) of \(company.maxSeats) seats used")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        // Trial or grace period warning
                        if let status = company.subscriptionStatus,
                           let statusEnum = SubscriptionStatus(rawValue: status) {
                            if statusEnum == .trial, let trialEnd = company.trialEndDate {
                                let days = Calendar.current.dateComponents([.day], from: Date(), to: trialEnd).day ?? 0
                                HStack(spacing: 4) {
                                    if days > 0 {
                                        Image(systemName: OPSStyle.Icons.info)
                                            .font(.system(size: 12))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                                        Text("Trial ends in \(days) day\(days == 1 ? "" : "s")")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    } else {
                                        Image(systemName: OPSStyle.Icons.alert)
                                            .font(.system(size: 12))
                                            .foregroundColor(OPSStyle.Colors.errorStatus)

                                        Text("Trial expired")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }
                            } else if statusEnum == .grace, let days = company.daysRemainingInGracePeriod {
                                HStack(spacing: 4) {
                                    if days > 0 {
                                        Image(systemName: OPSStyle.Icons.alert)
                                            .font(.system(size: 12))
                                            .foregroundColor(OPSStyle.Colors.warningStatus)

                                        Text("Grace period ends in \(days) day\(days == 1 ? "" : "s")")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.warningStatus)
                                    } else {
                                        Image(systemName: OPSStyle.Icons.alert)
                                            .font(.system(size: 12))
                                            .foregroundColor(OPSStyle.Colors.errorStatus)

                                        Text("Grace period expired")
                                            .font(OPSStyle.Typography.smallCaption)
                                            .foregroundColor(OPSStyle.Colors.errorStatus)
                                    }
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Action chevron (only for company admins)
                    if isCompanyAdmin {
                        Image(systemName: OPSStyle.Icons.chevronRight)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                }
                .contentShape(Rectangle()) // Ensure entire area is tappable
                .buttonStyle(PlainButtonStyle()) // Make button work properly
                .disabled(!isCompanyAdmin) // Disable for non-company-admins
                .padding()
                
                // Only show divider and action buttons for company admins
                if isCompanyAdmin {
                    Divider()
                        .background(OPSStyle.Colors.cardBackgroundDark)
                    
                    // Action buttons
                    HStack(spacing: 0) {
                        // Manage seats button
                        Button(action: {
                            showSeatManagement = true
                        }) {
                            HStack {
                                Image(systemName: OPSStyle.Icons.personTwo)
                                    .font(OPSStyle.Typography.caption)
                                
                                Text("Manage Seats")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle()) // Add plain button style to ensure tappability
                        
                        Divider()
                            .frame(width: 1)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                        
                        // Change plan button
                        Button(action: {
                            showPlanSelection = true
                        }) {
                            HStack {
                                Image(systemName: "arrow.up.circle")
                                    .font(OPSStyle.Typography.caption)
                                
                                Text("Change Plan")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(PlainButtonStyle()) // Add plain button style to ensure tappability
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal, 20)
        }
    }
    
    private func statusColor(for status: SubscriptionStatus) -> Color {
        switch status {
        case .trial:
            return OPSStyle.Colors.primaryAccent
        case .active:
            return OPSStyle.Colors.successStatus
        case .grace:
            return OPSStyle.Colors.warningStatus
        case .expired, .cancelled:
            return OPSStyle.Colors.errorStatus
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                .scaleEffect(1.8)
            
            Text("Loading organization data...")
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
        }
        .frame(maxWidth: .infinity, maxHeight: 200)
        .padding()
    }
    
    // Individual info field - matches ProfileSettingsView style
    private func infoField(title: String, value: String, icon: String, isMissing: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isMissing ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                    .frame(width: 24)
                
                Text(value)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(isMissing ? OPSStyle.Colors.tertiaryText : .white)
                
                Spacer()
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(12)
        }
        .padding(.horizontal, 20)
    }
    
    private var emptyTeamView: some View {
        VStack(spacing: 16) {
            Image(systemName: OPSStyle.Icons.crew)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            Text("No team members found")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(.white)
            
            Text("Team members will appear here when added to your organization")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func memberRow(member: User) -> some View {
        HStack(spacing: 16) {
            // User avatar
            ZStack {
                Circle()
                    .fill(OPSStyle.Colors.primaryAccent)
                    .frame(width: 48, height: 48)
                
                Text(String(member.fullName.prefix(1)))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(member.fullName)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                
                Text(member.role.displayName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            // Status badge - active/inactive
            if member.isActive != false { // Show as active unless explicitly set to false
                Text("Active")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.successStatus)
                    .cornerRadius(12)
            } else {
                Text("Inactive")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.inactiveStatus)
                    .cornerRadius(12)
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private func loadOrganizationData() {
        isLoading = true
        
        Task {
            // Fetch organization data
            if let companyID = dataController.currentUser?.companyId {
                
                // Always attempt to fetch fresh data from API when online
                // This ensures we have the latest company info including address, phone, email
                if dataController.isConnected {
                    // Show refresh indicator
                    await MainActor.run {
                        isRefreshing = true
                    }
                    
                    do {
                        // Force a refresh of company data from the API every time view opens
                        try await dataController.forceRefreshCompany(id: companyID)
                        
                        // Debug: Log what we got from the API
                        if let refreshedCompany = dataController.getCompany(id: companyID) {
                        }
                        
                        // Sync company team members if we're online
                        if let company = dataController.getCompany(id: companyID) {
                            await dataController.syncManager?.syncCompanyTeamMembers(company)
                        }
                        
                        // Also force sync projects when opening organization settings
                        // This ensures projects are loaded if they weren't during login
                        try? await dataController.syncManager?.manualFullSync()
                    } catch {
                        // Continue with local data even if API refresh fails
                        await MainActor.run {
                            isRefreshing = false
                        }
                    }
                } else {
                }
                
                // Get company from local database (newly refreshed if the API call succeeded)
                let company = dataController.getCompany(id: companyID)
                let users = dataController.getTeamMembers(companyId: companyID)
                
                if let company = company {
                }
                
                // Load company logo if available
                if let company = company, let logoURL = company.logoURL, !logoURL.isEmpty {
                    
                    // Check if logo is already cached
                    if ImageCache.shared.get(forKey: logoURL) == nil {
                        // Not cached, load from URL
                        if await loadImage(from: logoURL) != nil {
                            // Image is now cached by the loadImage function
                        } else {
                        }
                    } else {
                    }
                }
                
                await MainActor.run {
                    self.organization = company
                    self.teamMembers = users
                    self.isLoading = false
                    self.isRefreshing = false
                    
                    // Debug info
                    if let org = self.organization {
                    } else {
                    }
                }
            } else {
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
    
    private func loadImage(from urlString: String) async -> UIImage? {
        // Check if it's a local URL
        if urlString.starts(with: "local://") {
            if let imageBase64 = UserDefaults.standard.string(forKey: urlString),
               let imageData = Data(base64Encoded: imageBase64),
               let image = UIImage(data: imageData) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
            return nil
        }
        
        // Handle remote URL
        var imageURL = urlString
        
        // Fix for URLs starting with //
        if imageURL.starts(with: "//") {
            imageURL = "https:" + imageURL
        }
        
        guard let url = URL(string: imageURL) else { return nil }
        
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let image = UIImage(data: data) {
                // Cache the loaded image
                ImageCache.shared.set(image, forKey: urlString)
                return image
            }
        } catch {
        }
        
        return nil
    }

    // MARK: - Default Project Color Picker

    @ViewBuilder
    private var defaultProjectColorPicker: some View {
        Button(action: {
            showColorPicker = true
        }) {
            HStack(spacing: 12) {
                // Color preview circle
                Circle()
                    .fill(Color(hex: organization?.defaultProjectColor ?? "#9CA3AF") ?? .gray)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .strokeBorder(OPSStyle.Colors.inputFieldBorder, lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Default Project Color")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(organization?.defaultProjectColor ?? "#9CA3AF")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }

                Spacer()

                if isUpdatingColor {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(16)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isUpdatingColor)
        .padding(.horizontal, 20)
        .sheet(isPresented: $showColorPicker) {
            colorPickerSheet
        }
    }

    @ViewBuilder
    private var colorPickerSheet: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    // Color preview
                    VStack(spacing: 12) {
                        Text("Preview")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Circle()
                            .fill(selectedColor)
                            .frame(width: 80, height: 80)
                            .overlay(
                                Circle()
                                    .strokeBorder(OPSStyle.Colors.inputFieldBorder, lineWidth: 2)
                            )

                        Text(selectedColor.toHex() ?? "#9CA3AF")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.top, 24)

                    // Color picker
                    ColorPicker("Select Color", selection: $selectedColor, supportsOpacity: false)
                        .labelsHidden()
                        .padding(.horizontal, 20)

                    Spacer()

                    // Save button
                    Button(action: {
                        Task {
                            await updateDefaultProjectColor()
                        }
                    }) {
                        if isUpdatingColor {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Text("Update Project Color")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                    .disabled(isUpdatingColor)
                }
            }
            .navigationTitle("Default Project Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showColorPicker = false
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(isUpdatingColor)
                }
            }
        }
        .onAppear {
            // Initialize color picker with current color
            if let hexColor = organization?.defaultProjectColor,
               let color = Color(hex: hexColor) {
                selectedColor = color
            }
        }
    }

    // MARK: - Update Default Project Color

    @MainActor
    private func updateDefaultProjectColor() async {
        guard let company = organization else { return }

        isUpdatingColor = true

        let newColorHex = selectedColor.toHex() ?? "#9CA3AF"

        do {
            // Update company's defaultProjectColor
            company.defaultProjectColor = newColorHex

            // Save to database
            try dataController.modelContext?.save()

            // Update all project calendar events to use new color
            try await updateAllProjectEventColors(to: newColorHex)

            // Sync to API
            if dataController.isConnected {
                try await dataController.updateCompanyDefaultProjectColor(
                    companyId: company.id,
                    color: newColorHex
                )
            }

            // Close sheet
            showColorPicker = false

            print("[COLOR_UPDATE] ✅ Successfully updated default project color to \(newColorHex)")

        } catch {
            print("[COLOR_UPDATE] ❌ Failed to update color: \(error)")
        }

        isUpdatingColor = false
    }

    // Task-only scheduling migration: Project-level calendar events no longer exist
    // All calendar events are now task-based and get their color from the task's task type
    // This function is no longer needed but kept as a no-op to avoid breaking existing call sites
    private func updateAllProjectEventColors(to newColor: String) async throws {
        print("[COLOR_UPDATE] ℹ️ Task-only scheduling migration: Project event color updates no longer needed")
        print("[COLOR_UPDATE] ℹ️ All calendar events now inherit colors from their task types")
    }
}

// Helper struct for organization info items
struct InfoItem {
    let title: String
    let value: String
    let icon: String
}

#Preview {
    OrganizationSettingsView()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
