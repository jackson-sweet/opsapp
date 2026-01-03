//
//  SeatManagementView.swift
//  OPS
//
//  Manage team member seats for subscription plans
//

import SwiftUI

struct SeatManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    
    @State private var seatedUserIds: Set<String> = []
    @State private var allTeamMembers: [User] = []
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var hasChanges = false
    @State private var showPlanSelection = false
    @State private var showInfo = false
    
    private var company: Company? {
        dataController.getCurrentUserCompany()
    }
    
    private var maxSeats: Int {
        company?.maxSeats ?? 3
    }
    
    private var availableSeats: Int {
        maxSeats - seatedUserIds.count
    }
    
    private var currentPlan: SubscriptionPlan? {
        guard let planString = company?.subscriptionPlan else { return nil }
        return SubscriptionPlan(rawValue: planString)
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()
                
                if isLoading {
                    loadingView
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Seat usage header
                            seatUsageCard
                            
                            // Expandable info section
                            expandableInfoSection
                            
                            // Get More Seats button
                            if maxSeats < 30 { // Don't show if already on highest plan
                                getMoreSeatsButton
                            }
                            
                            // Team members list
                            teamMembersList
                            
                            // Upgrade prompt if needed
                            if availableSeats <= 0 {
                                upgradePrompt
                            }
                        }
                        .padding()
                    }
                }
            }
            .standardSheetToolbar(
                title: "Manage Seats",
                actionText: "Save",
                isActionEnabled: hasChanges,
                isSaving: isSaving,
                showProgressOnSave: false,
                onCancel: { dismiss() },
                onAction: saveChanges
            )
        }
        .onAppear {
            loadTeamMembers()
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
        }
    }
    
    // MARK: - Expandable Info Section
    
    private var expandableInfoSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInfo.toggle()
                }
            }) {
                HStack {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    
                    Text("HOW SEAT MANAGEMENT WORKS")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Spacer()
                    
                    Image(systemName: showInfo ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal)
            }
            
            if showInfo {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 6) {
                            Text("•")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("Only employees with seats can access OPS")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        HStack(spacing: 6) {
                            Text("•")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("Seats can be reassigned at any time")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        HStack(spacing: 6) {
                            Text("•")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("Account holders cannot remove their own seat")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        
                        HStack(spacing: 6) {
                            Text("•")
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("Changes save immediately when you tap Save")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    .padding(.horizontal)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    
    // MARK: - Get More Seats Button
    
    private var getMoreSeatsButton: some View {
        Button(action: {
            showPlanSelection = true
        }) {
            HStack(spacing: 6) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 14))
                
                Text("GET MORE SEATS")
                    .font(OPSStyle.Typography.captionBold)
            }
            .foregroundColor(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .padding(.horizontal)
    }
    
    // MARK: - Seat Usage Card
    
    private var seatUsageCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Minimalist header - no card background
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(seatedUserIds.count)/\(maxSeats) SEATS ACTIVE")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if let plan = currentPlan {
                        Text("\(plan.displayName) Plan")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
            }
            
            // Simple progress line instead of circular indicator
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background track
                    Rectangle()
                        .fill(OPSStyle.Colors.subtleBackground)
                        .frame(height: 2)
                    
                    // Progress fill
                    Rectangle()
                        .fill(availableSeats > 0 ? OPSStyle.Colors.primaryText : OPSStyle.Colors.warningStatus)
                        .frame(width: geometry.size.width * (CGFloat(seatedUserIds.count) / CGFloat(maxSeats)), height: 2)
                }
            }
            .frame(height: 2)
            
            // Status message
            if availableSeats <= 0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                    
                    Text("SEAT LIMIT REACHED")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            } else {
                Text("\(availableSeats) \(availableSeats == 1 ? "seat" : "seats") available")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Team Members List
    
    private var teamMembersList: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Minimal section header
            Text("TEAM MEMBERS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 24)
            
            // Minimalist team member list - no individual cards
            VStack(spacing: 0) {
                ForEach(allTeamMembers) { user in
                    TeamMemberRow(
                        user: user,
                        isSeated: seatedUserIds.contains(user.id),
                        isCurrentUser: user.id == dataController.currentUser?.id,
                        canToggle: availableSeats > 0 || seatedUserIds.contains(user.id),
                        onToggle: {
                            toggleSeat(for: user)
                        }
                    )
                    
                    // Divider between rows
                    if user.id != allTeamMembers.last?.id {
                        Divider()
                            .background(OPSStyle.Colors.subtleBackground)
                            .padding(.horizontal, 24)
                    }
                }
            }
        }
    }
    
    // MARK: - Upgrade Prompt
    
    private var upgradePrompt: some View {
        VStack(spacing: 16) {
            // Warning message - no background
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                
                Text("Seat limit reached. Upgrade to add more team members.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Minimal upgrade button
            Button(action: {
                showPlanSelection = true
            }) {
                Text("UPGRADE PLAN")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .padding(.horizontal, 24)
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                .scaleEffect(0.8)
            
            Text("LOADING...")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
    }
    
    // MARK: - Methods
    
    private func loadTeamMembers() {
        print("[SEAT_MGMT] 📥 loadTeamMembers called")

        guard let company = company else {
            print("[SEAT_MGMT] ❌ No company found")
            isLoading = false
            return
        }

        print("[SEAT_MGMT] Company: \(company.name)")
        print("[SEAT_MGMT] Raw seatedEmployeeIds from company: '\(company.seatedEmployeeIds)'")

        // Parse seated employee IDs
        let seatedIds = company.seatedEmployeeIds
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        print("[SEAT_MGMT] Parsed \(seatedIds.count) seated IDs: \(seatedIds)")

        seatedUserIds = Set(seatedIds)

        // Load all team members
        allTeamMembers = dataController.getTeamMembers(companyId: company.id)
            .sorted { user1, user2 in
                // Sort by: current user first, then admins, then alphabetical
                if user1.id == dataController.currentUser?.id { return true }
                if user2.id == dataController.currentUser?.id { return false }
                if user1.role == .admin && user2.role != .admin { return true }
                if user1.role != .admin && user2.role == .admin { return false }
                return user1.firstName < user2.firstName
            }

        print("[SEAT_MGMT] Loaded \(allTeamMembers.count) team members:")
        for member in allTeamMembers {
            let isSeated = seatedUserIds.contains(member.id)
            print("[SEAT_MGMT]   - \(member.firstName) \(member.lastName) (ID: \(member.id)) - \(isSeated ? "SEATED" : "not seated")")
        }

        isLoading = false
    }
    
    private func toggleSeat(for user: User) {
        print("[SEAT_MGMT] toggleSeat called for user: \(user.firstName) \(user.lastName) (ID: \(user.id))")
        print("[SEAT_MGMT] Current seatedUserIds BEFORE toggle: \(seatedUserIds)")

        // Don't allow toggling off the account holder
        if user.id == dataController.currentUser?.id {
            print("[SEAT_MGMT] ⚠️ Cannot toggle current user (account holder)")
            return
        }

        if seatedUserIds.contains(user.id) {
            seatedUserIds.remove(user.id)
            print("[SEAT_MGMT] ➖ Removed user from seats")
        } else if availableSeats > 0 {
            seatedUserIds.insert(user.id)
            print("[SEAT_MGMT] ➕ Added user to seats")
        } else {
            print("[SEAT_MGMT] ⚠️ No available seats to add user")
        }

        print("[SEAT_MGMT] Current seatedUserIds AFTER toggle: \(seatedUserIds)")
        hasChanges = true
    }
    
    private func saveChanges() {
        guard let company = company else {
            print("[SEAT_MGMT] ❌ saveChanges: No company found")
            return
        }

        print("[SEAT_MGMT] 💾 saveChanges called")
        print("[SEAT_MGMT] seatedUserIds at save start: \(seatedUserIds)")

        isSaving = true

        // Always include the account holder (current user) in the seated list
        if let currentUserId = dataController.currentUser?.id {
            seatedUserIds.insert(currentUserId)
            print("[SEAT_MGMT] Added current user to seats: \(currentUserId)")
        }

        // Convert Set to Array for API call
        let seatedIdsArray = Array(seatedUserIds)
        let seatedIdsString = seatedIdsArray.joined(separator: ",")

        print("[SEAT_MGMT] 📤 Sending \(seatedIdsArray.count) seated user IDs to API:")
        for (index, id) in seatedIdsArray.enumerated() {
            let user = allTeamMembers.first { $0.id == id }
            print("[SEAT_MGMT]   \(index + 1). \(user?.firstName ?? "Unknown") \(user?.lastName ?? "") - \(id)")
        }
        
        // Call API to update seats
        Task {
            do {
                // Call the API to update seated employees
                let updatedCompany = try await dataController.apiService.updateCompanySeatedEmployees(
                    companyId: company.id,
                    seatedEmployeeIds: seatedIdsArray
                )
                
                // Update local data with the response
                await MainActor.run {
                    company.seatedEmployeeIds = seatedIdsString
                    
                    // Save local changes
                    try? dataController.modelContext?.save()
                    
                    isSaving = false
                    hasChanges = false
                }
                
                // Update subscription manager's seated employees
                await subscriptionManager.checkSubscriptionStatus()
                
                // Dismiss after everything is done
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = "Failed to update seats: \(error.localizedDescription)"
                    showError = true
                }
            }
        }
    }
}

// MARK: - Team Member Row

struct TeamMemberRow: View {
    let user: User
    let isSeated: Bool
    let isCurrentUser: Bool
    let canToggle: Bool
    let onToggle: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // No avatar - minimalist approach
            
            // User info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("\(user.firstName) \(user.lastName)")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if isCurrentUser {
                        Text("YOU")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.warningStatus.opacity(0.2))
                            .cornerRadius(4)
                    }
                    
                    if user.isCompanyAdmin {
                        Text("ADMIN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.warningStatus)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.warningStatus.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                
                // Email and role in smaller, grayed text
                VStack(alignment: .leading, spacing: 2) {
                    if let email = user.email {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    
                    Text(user.roleDisplay.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            Spacer()
            
            // Seat toggle - smaller and simpler
            Button(action: onToggle) {
                Image(systemName: isSeated ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundColor(
                        isCurrentUser ? OPSStyle.Colors.tertiaryText.opacity(0.3) :
                        isSeated ? OPSStyle.Colors.primaryText :
                        canToggle ? OPSStyle.Colors.tertiaryText :
                        OPSStyle.Colors.tertiaryText.opacity(0.3)
                    )
            }
            .disabled(isCurrentUser || (!canToggle && !isSeated))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 24)
        // No background card - just plain rows
    }
}

// MARK: - Preview

struct SeatManagementView_Previews: PreviewProvider {
    static var previews: some View {
        SeatManagementView()
            .environmentObject(DataController())
            .environmentObject(SubscriptionManager.shared)
            .preferredColorScheme(.dark)
    }
}