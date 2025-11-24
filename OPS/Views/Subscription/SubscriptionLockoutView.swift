//
//  SubscriptionLockoutView.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Full-screen lockout view shown when subscription is expired or user lacks seat

import SwiftUI

struct SubscriptionLockoutView: View {
    @EnvironmentObject private var subscriptionManager: SubscriptionManager
    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    
    @State private var showPlanSelection = false
    @State private var isLoggingOut = false
    @State private var isProcessingSeat = false
    @State private var seatActionError: String?
    @State private var showSeatManagement = false
    @State private var selectedEmployeeToRemove: User?
    @State private var showRemoveConfirmation = false
    @State private var selectedEmployeeToAdd: User?
    @State private var showAddConfirmation = false
    @State private var hasJustSeatedSelf = false
    @State private var isRefreshing = false
    @State private var refreshProgress: Double = 0.0
    @State private var refreshComplete = false
    @State private var refreshError = false
    @State private var refreshResultNegative = false
    @State private var animationTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            // Pure black background
            OPSStyle.Colors.background
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                headerView
                    .padding(.top, 60)
                
                if showSeatManagement && subscriptionManager.isUserAdmin {
                    // Seat management state
                    inlineSeatManagementView
                        .padding(.top, 32)
                    
                    Spacer()
                } else {
                    // Default state
                    Spacer()
                    
                    // Content based on user type
                    if subscriptionManager.isUserAdmin {
                        adminContent
                    } else {
                        nonAdminContent
                    }
                    
                    Spacer()
                }
                
                // Footer buttons (always visible)
                footerButtons
                    .padding(.bottom, 50)
            }
        }
        .sheet(isPresented: $showPlanSelection) {
            PlanSelectionView()
                .environmentObject(subscriptionManager)
                .environmentObject(dataController)
                .interactiveDismissDisabled(true) // Prevent swipe-to-dismiss during payment
        }
        // Removed onAppear auto-show - user must click button to see seat management
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACCESS RESTRICTED")
                    .font(OPSStyle.Typography.bodyBold)  // Smaller font
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(headerSubtitle)
                    .font(OPSStyle.Typography.caption)  // Smaller font
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            Image(systemName: "lock.fill")
                .font(.system(size: 20))  // Smaller icon
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.horizontal, 24)
    }
    
    private var headerSubtitle: String {
        if subscriptionManager.isUserAdmin {
            if !subscriptionManager.userHasSeat && subscriptionManager.subscriptionStatus == .active {
                return "Admin Seat Required"
            }
            switch subscriptionManager.subscriptionStatus {
            case .trial:
                return "Trial Expired"
            case .expired:
                return "Subscription Expired"
            case .cancelled:
                return "Subscription Cancelled"
            default:
                return "No Available Seats"
            }
        } else {
            return "Contact Administrator"
        }
    }
    
    // MARK: - Admin Content
    
    private var adminContent: some View {
        VStack(spacing: 32) {  // More spacing
            // Lockout reason
            Text(adminLockoutMessage)
                .font(OPSStyle.Typography.body)  // Changed to body size
                .foregroundColor(OPSStyle.Colors.primaryText)  // Changed to primaryText
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Primary CTA - different for unseated admins
            if !subscriptionManager.userHasSeat && subscriptionManager.subscriptionStatus == .active {
                VStack(spacing: 24) {  // More spacing
                    // Button to show seat management
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showSeatManagement = true
                        }
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.2.badge.gearshape")
                                .font(.system(size: 14))
                            Text("MANAGE TEAM SEATS")
                                .font(OPSStyle.Typography.captionBold)  // Smaller, tactical font
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)  // Slightly smaller padding
                        .background(Color.white)  // White background for primary button
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .padding(.horizontal, 24)
                    
                    // Show current seat usage
                    if subscriptionManager.maxSeats > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: OPSStyle.Icons.crew)
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("\(subscriptionManager.seatedEmployees.count) OF \(subscriptionManager.maxSeats) SEATS USED")
                                .font(OPSStyle.Typography.smallCaption)  // Smaller font
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                    
                    // Secondary option to upgrade
                    Button(action: {
                        showPlanSelection = true
                    }) {
                        Text("Upgrade for More Seats")
                            .font(OPSStyle.Typography.caption)  // Smaller font
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            } else {
                // Regular admin lockout - show plan selection
                VStack(spacing: 12) {
                    Button(action: {
                        showPlanSelection = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: "creditcard")
                                .font(.system(size: 14))
                            Text(primaryButtonText.uppercased())
                                .font(OPSStyle.Typography.captionBold)  // Smaller, tactical font
                        }
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)  // Slightly smaller padding
                        .background(Color.white)  // White background for primary button
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }

                    // Refresh subscription button
                    Button(action: {
                        Task {
                            await refreshSubscription()
                        }
                    }) {
                        HStack(spacing: 8) {
                            if isRefreshing {
                                TacticalLoadingBar(
                                    progress: refreshProgress,
                                    barCount: 8,
                                    barWidth: 2,
                                    barHeight: 6,
                                    spacing: 4,
                                    emptyColor: OPSStyle.Colors.inputFieldBorder,
                                    fillColor: refreshError || refreshResultNegative ? OPSStyle.Colors.errorStatus : (refreshComplete ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText)
                                )
                            } else {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 14))
                            }
                            Text(refreshError ? "NETWORK ERROR" : "CHECK STATUS")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor((refreshError || refreshResultNegative) ? OPSStyle.Colors.errorStatus : (refreshComplete ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke((refreshError || refreshResultNegative) ? OPSStyle.Colors.errorStatus : (refreshComplete ? OPSStyle.Colors.successStatus : OPSStyle.Colors.tertiaryText), lineWidth: 1)
                        )
                        .opacity(refreshComplete && !refreshResultNegative ? 0 : 1)
                    }
                    .disabled(isRefreshing)
                    .animation(.easeOut(duration: 0.3), value: refreshComplete)
                    .animation(.easeOut(duration: 0.3), value: refreshError)
                    .animation(.easeOut(duration: 0.3), value: refreshResultNegative)
                }
                .padding(.horizontal, 24)
            }
        }
    }
    
    private var adminLockoutMessage: String {
        if !subscriptionManager.userHasSeat && subscriptionManager.subscriptionStatus == .active {
            return "As an administrator, you need a seat to access OPS. Manage your team's seats or upgrade your plan."
        }
        
        switch subscriptionManager.subscriptionStatus {
        case .trial:
            return "Your 30-day trial has ended. Choose a plan to continue using OPS."
        case .expired:
            return "Your subscription has expired. Resubscribe to restore access."
        case .cancelled:
            return "Your subscription has been cancelled. Choose a new plan to restore access."
        default:
            return "All seats in your company's plan are occupied. Upgrade to add more seats."
        }
    }
    
    // MARK: - Non-Admin Content
    
    private var nonAdminContent: some View {
        VStack(spacing: 32) {  // More spacing
            // Simple message
            Text(nonAdminLockoutMessage)
                .font(OPSStyle.Typography.body)  // Changed to body size
                .foregroundColor(OPSStyle.Colors.primaryText)  // Changed to primaryText
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            
            // Admin contact - NO CARD BACKGROUND
            if let company = dataController.getCurrentUserCompany(),
               let adminIds = company.getAdminIds().first,
               let admin = dataController.getUser(id: adminIds) {
                
                VStack(spacing: 24) {  // More spacing
                    // Admin info - floating, no background, no avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(admin.firstName) \(admin.lastName)")
                            .font(OPSStyle.Typography.caption)  // Smaller font
                            .foregroundColor(OPSStyle.Colors.primaryText)
                        
                        Text("ADMINISTRATOR")
                            .font(OPSStyle.Typography.smallCaption)  // Smaller font
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .padding(.horizontal, 40)  // Align with message text
                    
                    // Contact buttons
                    HStack(spacing: 12) {
                        if let phone = admin.phone {
                            Button(action: {
                                if let url = URL(string: "tel://\(phone)") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "phone.fill")
                                        .font(.system(size: 12))
                                    Text("CALL")
                                        .font(OPSStyle.Typography.captionBold)  // Smaller, tactical font
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)  // Smaller padding
                                .background(Color.white)  // White background for primary button
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }
                        
                        if let email = admin.email {
                            Button(action: {
                                if let url = URL(string: "mailto:\(email)?subject=OPS%20App%20Access") {
                                    UIApplication.shared.open(url)
                                }
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "envelope.fill")
                                        .font(.system(size: 12))
                                    Text("EMAIL")
                                        .font(OPSStyle.Typography.captionBold)  // Smaller, tactical font
                                }
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)  // Smaller padding
                                .background(Color.white)  // White background for primary button
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                }
            }
        }
    }
    
    private var nonAdminLockoutMessage: String {
        if !subscriptionManager.userHasSeat {
            return "You don't have a seat in your company's OPS subscription. Contact your administrator to request access."
        } else {
            return "Your company's OPS subscription needs attention. Please contact your administrator."
        }
    }
    
    // MARK: - Helper Views
    
    private var primaryButtonText: String {
        switch subscriptionManager.subscriptionStatus {
        case .trial:
            return "Choose a Plan"
        case .expired, .cancelled:
            return "Resubscribe"
        default:
            return "Upgrade Plan"
        }
    }
    
    // MARK: - Inline Seat Management
    
    @ViewBuilder
    private var employeeListsContent: some View {
        if let company = dataController.getCurrentUserCompany(),
           let allEmployees = dataController.getAllCompanyEmployees(companyId: company.id) {
            
            let seatedUsers = allEmployees.filter { employee in
                subscriptionManager.seatedEmployees.contains { $0.id == employee.id }
            }.sorted { "\($0.firstName) \($0.lastName)" < "\($1.firstName) \($1.lastName)" }
            
            let unseatedUsers = allEmployees.filter { employee in
                !subscriptionManager.seatedEmployees.contains { $0.id == employee.id }
            }.sorted { "\($0.firstName) \($0.lastName)" < "\($1.firstName) \($1.lastName)" }
            
            // Check if current user is unseated admin with only 1 seat available
            let isCurrentUserSeated = subscriptionManager.userHasSeat
            let isUserAdmin = subscriptionManager.isUserAdmin
            let availableSeats = subscriptionManager.maxSeats - subscriptionManager.seatedEmployees.count
            let shouldLimitToAdmin = !isCurrentUserSeated && isUserAdmin && availableSeats == 1
            
            // SEATED USERS section
            if !seatedUsers.isEmpty {
                seatedUsersSection(users: seatedUsers, company: company)
            }
            
            // UNSEATED USERS section  
            if !unseatedUsers.isEmpty {
                unseatedUsersSection(users: unseatedUsers, company: company, shouldLimitToAdmin: shouldLimitToAdmin, availableSeats: availableSeats)
            }
        }
    }
    
    @ViewBuilder
    private func seatedUsersSection(users: [User], company: Company) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SEATED USERS (\(users.count))")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, employee in
                    VStack(spacing: 0) {
                        seatedUserRow(for: employee, in: company)
                        
                        if index < users.count - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private func unseatedUsersSection(users: [User], company: Company, shouldLimitToAdmin: Bool, availableSeats: Int) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("UNSEATED USERS (\(users.count))")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.horizontal, 24)
            
            VStack(spacing: 0) {
                ForEach(Array(users.enumerated()), id: \.element.id) { index, employee in
                    let isCurrentUser = employee.id == dataController.currentUser?.id
                    let canAssignSeat = !shouldLimitToAdmin || isCurrentUser || availableSeats > 1
                    
                    VStack(spacing: 0) {
                        unseatedUserRow(for: employee, in: company, canAssignSeat: canAssignSeat)
                        
                        if index < users.count - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                        }
                    }
                }
            }
        }
    }
    
    @ViewBuilder
    private var inlineSeatManagementView: some View {
        VStack(spacing: 32) {  // More spacing
            // Header with back button
            HStack {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showSeatManagement = false
                        seatActionError = nil
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .semibold))
                        Text("BACK")
                            .font(OPSStyle.Typography.captionBold)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                
                Spacer()
                
                Text("\(subscriptionManager.seatedEmployees.count) OF \(subscriptionManager.maxSeats) SEATS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 24)
                
                // Minimalist progress indicator - just a thin line
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background line
                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))  // Very subtle
                            .frame(height: 2)  // Thinner
                        
                        // Progress line
                        Rectangle()
                            .fill(seatUsageColor)
                            .frame(
                                width: geometry.size.width * CGFloat(subscriptionManager.seatedEmployees.count) / CGFloat(max(1, subscriptionManager.maxSeats)),
                                height: 2  // Thinner
                            )
                    }
                }
                .frame(height: 2)
                .padding(.horizontal, 24)
            
            // Error message if any
            if let error = seatActionError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    Text(error.uppercased())
                        .font(OPSStyle.Typography.smallCaption)  // Smaller font
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                }
                .padding(.horizontal, 24)
            }
            
            // Two separate lists for seated and unseated users
            ScrollView {
                VStack(spacing: 32) {
                    employeeListsContent
                    
                    // Show "ENTER OPS" button if admin just seated themselves
                    if hasJustSeatedSelf && subscriptionManager.userHasSeat {
                        VStack(spacing: 16) {
                            Rectangle()
                                .fill(OPSStyle.Colors.tertiaryText.opacity(0.2))
                                .frame(height: 1)
                                .padding(.horizontal, 24)
                            
                            Text("ACCESS GRANTED")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.successStatus)
                            
                            Button(action: {
                                // Dismiss the lockout view to enter the app
                                dismiss()
                            }) {
                                Text("ENTER OPS")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(.black)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Color.white)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                            }
                            .padding(.horizontal, 24)
                            
                            Text("OR CONTINUE MANAGING SEATS")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.bottom, 20)
                    }
                }
            }
        }
        .alert("Remove Seat Access?", isPresented: $showRemoveConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedEmployeeToRemove = nil
            }
            Button("Remove", role: .destructive) {
                if let employee = selectedEmployeeToRemove {
                    toggleSeat(for: employee, shouldAdd: false)
                }
            }
        } message: {
            if let employee = selectedEmployeeToRemove {
                Text("\(employee.firstName) \(employee.lastName) will lose access to OPS until reassigned a seat.")
            }
        }
        .alert("Grant Seat Access?", isPresented: $showAddConfirmation) {
            Button("Cancel", role: .cancel) {
                selectedEmployeeToAdd = nil
            }
            Button("Grant Access") {
                if let employee = selectedEmployeeToAdd {
                    toggleSeat(for: employee, shouldAdd: true)
                }
            }
        } message: {
            if let employee = selectedEmployeeToAdd {
                Text("\(employee.firstName) \(employee.lastName) will gain access to OPS.")
            }
        }
    }
    
    private func seatedUserRow(for employee: User, in company: Company) -> some View {
        let isCurrentUser = employee.id == dataController.currentUser?.id
        let isAdmin = employee.isCompanyAdmin || employee.role == .admin
        
        return HStack(spacing: 12) {
            // User info - no avatars
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    if isCurrentUser {
                        Text("(YOU)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(employee.roleDisplay.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    if isAdmin {
                        Text("• ADMIN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
            
            Spacer()
            
            // Revoke access button
            Button(action: {
                selectedEmployeeToRemove = employee
                showRemoveConfirmation = true
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "person.fill.xmark")
                        .font(.system(size: 10, weight: .semibold))
                    Text("REVOKE")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(OPSStyle.Colors.errorStatus)
                .opacity(isProcessingSeat || (isCurrentUser && !isAdmin) ? 0.3 : 1.0)
            }
            .disabled(isProcessingSeat || (isCurrentUser && !isAdmin))
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
    
    private func unseatedUserRow(for employee: User, in company: Company, canAssignSeat: Bool) -> some View {
        let isCurrentUser = employee.id == dataController.currentUser?.id
        let isAdmin = employee.isCompanyAdmin || employee.role == .admin
        let availableSeats = subscriptionManager.maxSeats - subscriptionManager.seatedEmployees.count
        
        return HStack(spacing: 12) {
            // User info - no avatars
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("\(employee.firstName) \(employee.lastName)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(canAssignSeat ? OPSStyle.Colors.primaryText : OPSStyle.Colors.tertiaryText)
                    
                    if isCurrentUser {
                        Text("(YOU)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                
                HStack(spacing: 6) {
                    Text(employee.roleDisplay.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    if isAdmin {
                        Text("• ADMIN")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(canAssignSeat ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .opacity(canAssignSeat ? 1.0 : 0.3)
            
            Spacer()
            
            // Grant access button
            Button(action: {
                if availableSeats > 0 {
                    selectedEmployeeToAdd = employee
                    showAddConfirmation = true
                } else {
                    seatActionError = "No seats available"
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        seatActionError = nil
                    }
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.circle")
                        .font(.system(size: 10, weight: .semibold))
                    Text("GRANT")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(canAssignSeat && availableSeats > 0 ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                .opacity(canAssignSeat && availableSeats > 0 && !isProcessingSeat ? 1.0 : 0.3)
            }
            .disabled(!canAssignSeat || availableSeats == 0 || isProcessingSeat)
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
    }
    
    private var seatUsageColor: Color {
        let usageRatio = Double(subscriptionManager.seatedEmployees.count) / Double(max(1, subscriptionManager.maxSeats))
        
        if usageRatio >= 1.0 {
            return OPSStyle.Colors.errorStatus
        } else if usageRatio >= 0.7 {
            return OPSStyle.Colors.warningStatus
        } else {
            return OPSStyle.Colors.primaryAccent
        }
    }
    
    private func toggleSeat(for employee: User, shouldAdd: Bool) {
        isProcessingSeat = true
        seatActionError = nil
        
        Task {
            do {
                if shouldAdd {
                    try await subscriptionManager.addSeat(for: employee.id)
                } else {
                    try await subscriptionManager.removeSeat(for: employee.id)
                }
                
                // Trigger sync
                if let syncManager = dataController.syncManager {
                    syncManager.triggerBackgroundSync()
                }
                
                // Wait a moment for sync
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
                // Refresh subscription status
                await subscriptionManager.checkSubscriptionStatus()
                
                await MainActor.run {
                    isProcessingSeat = false
                    selectedEmployeeToRemove = nil
                    selectedEmployeeToAdd = nil
                    
                    // Check if admin just seated themselves
                    if shouldAdd && employee.id == dataController.currentUser?.id {
                        hasJustSeatedSelf = true
                    }
                    
                    // Provide haptic feedback
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    // Don't auto-dismiss - let admin choose when to enter the app
                }
            } catch {
                await MainActor.run {
                    isProcessingSeat = false
                    selectedEmployeeToRemove = nil
                    selectedEmployeeToAdd = nil
                    seatActionError = shouldAdd ? 
                        "Failed to grant seat access" : 
                        "Failed to remove seat access"
                }
            }
        }
    }
    
    // MARK: - Footer Buttons
    
    private var footerButtons: some View {
        VStack(spacing: 20) {  // More spacing
            // Contact support (only show if not showing seat management)
            if !showSeatManagement {
                Button(action: {
                    // Get appropriate support contact
                    let supportContact = dataController.getPrioritySupportContact() ?? 
                                         dataController.getGeneralSupportContact()
                    let email = supportContact?.email ?? "support@opsapp.co"
                    
                    // Open email to support
                    if let url = URL(string: "mailto:\(email)?subject=Subscription%20Help") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("CONTACT SUPPORT")
                        .font(OPSStyle.Typography.smallCaption)  // Smaller font
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            
            // Sign out button - more prominent
            Button(action: {
                isLoggingOut = true
                dataController.logout()
            }) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.backward.square.fill")
                        .font(.system(size: 14))
                    Text("SIGN OUT")
                        .font(OPSStyle.Typography.captionBold)  // Smaller, tactical font
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .disabled(isLoggingOut)
            .opacity(isLoggingOut ? 0.5 : 1.0)
        }
    }

    // MARK: - Refresh Subscription

    @MainActor
    private func refreshSubscription() async {
        guard !isRefreshing else { return }

        // Reset states
        isRefreshing = true
        refreshProgress = 0.0
        refreshComplete = false
        refreshError = false
        refreshResultNegative = false

        print("[LOCKOUT] 🔄 Refreshing subscription status...")

        // Start continuous cycling animation
        startCyclingAnimation()

        // Track start time for minimum display duration
        let startTime = Date()

        // Run sync with timeout
        let syncTask = Task {
            do {
                if let syncManager = dataController.syncManager {
                    try await syncManager.syncCompany()
                    print("[LOCKOUT] ✅ Company data synced successfully")

                    await subscriptionManager.checkSubscriptionStatus()
                    print("[LOCKOUT] ✅ Subscription status re-checked")

                    return true
                }
                return false
            } catch {
                print("[LOCKOUT] ❌ Failed to refresh subscription: \(error)")
                return false
            }
        }

        // Wait for either sync to complete or timeout (10 seconds)
        let timeoutTask = Task {
            try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
            return false
        }

        // Race between sync and timeout
        let success = await withTaskCancellationHandler {
            await syncTask.value
        } onCancel: {
            syncTask.cancel()
        }

        timeoutTask.cancel()

        // Calculate elapsed time
        let elapsed = Date().timeIntervalSince(startTime)
        let minimumDuration: TimeInterval = 3.0

        // Wait for minimum display time if needed
        if elapsed < minimumDuration {
            let remainingTime = minimumDuration - elapsed
            try? await Task.sleep(nanoseconds: UInt64(remainingTime * 1_000_000_000))
        }

        // Stop cycling animation
        stopCyclingAnimation()

        // Show result
        if success {
            // Check subscription status to determine result color
            let status = subscriptionManager.subscriptionStatus
            let isNegativeStatus = status == .expired || status == .cancelled

            if isNegativeStatus {
                // Negative status - fill to 100% with red
                refreshResultNegative = true
                refreshProgress = 1.0
                print("[LOCKOUT] ⚠️ Subscription status is \(status.rawValue) - showing red")

                // Wait to show negative result
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

                // Reset states
                isRefreshing = false
                refreshProgress = 0.0
                refreshResultNegative = false
            } else {
                // Positive status - fill to 100% with green
                refreshComplete = true
                refreshProgress = 1.0
                print("[LOCKOUT] ✅ Subscription status is \(status.rawValue) - showing green")

                // If access is now granted, the lockout view will automatically dismiss
                if !subscriptionManager.shouldShowLockout {
                    print("[LOCKOUT] ✅ Access granted - lockout will dismiss")
                }

                // Wait before fading out
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

                // Reset states
                isRefreshing = false
                refreshProgress = 0.0

                // Wait for fade to complete
                try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                refreshComplete = false
            }
        } else {
            // Network error - fill to 100% with red
            refreshError = true
            refreshProgress = 1.0

            // Wait to show error
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds

            // Reset states
            isRefreshing = false
            refreshProgress = 0.0
            refreshError = false
        }
    }

    @MainActor
    private func startCyclingAnimation() {
        // Cancel any existing animation
        stopCyclingAnimation()

        // Start new cycling animation task
        animationTask = Task {
            while !Task.isCancelled {
                // Cycle from 0 to 100% smoothly
                for i in 0...100 {
                    guard !Task.isCancelled else { break }
                    refreshProgress = Double(i) / 100.0
                    try? await Task.sleep(nanoseconds: 8_000_000) // 8ms per step = ~800ms per cycle
                }
            }
        }
    }

    @MainActor
    private func stopCyclingAnimation() {
        animationTask?.cancel()
        animationTask = nil
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let navigateToSeatManagement = Notification.Name("navigateToSeatManagement")
}

// MARK: - Preview

struct SubscriptionLockoutView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Admin view - trial expired
            SubscriptionLockoutView()
                .environmentObject({
                    let manager = SubscriptionManager.shared
                    manager.isUserAdmin = true
                    manager.subscriptionStatus = .trial
                    return manager
                }())
                .previewDisplayName("Admin - Trial Expired")
            
            // Admin view - no seat with active subscription
            SubscriptionLockoutView()
                .environmentObject({
                    let manager = SubscriptionManager.shared
                    manager.isUserAdmin = true
                    manager.userHasSeat = false
                    manager.subscriptionStatus = .active
                    manager.maxSeats = 5
                    // Note: In real app, seatedEmployees would be populated
                    return manager
                }())
                .previewDisplayName("Admin - No Seat (Active)")
            
            // Non-admin view - no seat
            SubscriptionLockoutView()
                .environmentObject({
                    let manager = SubscriptionManager.shared
                    manager.isUserAdmin = false
                    manager.userHasSeat = false
                    return manager
                }())
                .previewDisplayName("Non-Admin - No Seat")
        }
        .preferredColorScheme(.dark)
    }
}