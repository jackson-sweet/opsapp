//
//  SubscriptionManager.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Central manager for subscription state, access control, and billing

import SwiftUI
import SwiftData
import Combine

/// Manages all subscription-related functionality including status checks,
/// access control, seat management, and notification scheduling
class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()
    
    // MARK: - Published Properties
    
    /// Current subscription status for the user's company
    @Published var subscriptionStatus: SubscriptionStatus = .trial
    
    /// Current subscription plan
    @Published var subscriptionPlan: SubscriptionPlan = .trial
    
    /// Whether the user should be locked out of the app
    @Published var shouldShowLockout: Bool = false
    
    /// Whether to show grace period warning banner
    @Published var shouldShowGracePeriodBanner: Bool = false
    
    /// Whether the user is seated (has access)
    @Published var userHasSeat: Bool = true
    
    /// Whether the current user is an admin
    @Published var isUserAdmin: Bool = false
    
    /// Whether the current user is the plan holder
    @Published var isUserPlanHolder: Bool = false
    
    /// Days remaining in trial (nil if not in trial)
    @Published var trialDaysRemaining: Int?
    
    /// Days remaining in grace period (nil if not in grace)
    @Published var graceDaysRemaining: Int?
    
    /// Company's current seated employees
    @Published var seatedEmployees: [User] = []
    
    /// Maximum seats for current plan
    @Published var maxSeats: Int = 10
    
    /// Whether company has priority support
    @Published var hasPrioritySupport: Bool = false
    
    // MARK: - Private Properties
    
    private var cancellables = Set<AnyCancellable>()
    private weak var dataController: DataController?
    private let notificationManager = NotificationManager.shared
    
    // MARK: - Initialization
    
    private init() {
        setupSubscribers()
    }
    
    /// Set the DataController reference (call from app initialization)
    func setDataController(_ controller: DataController) {
        self.dataController = controller
    }
    
    // MARK: - Setup
    
    private func setupSubscribers() {
        // Listen for app becoming active to check subscription
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                Task {
                    await self?.checkSubscriptionStatus()
                }
            }
            .store(in: &cancellables)
        
        // Listen for successful sync to update subscription
        NotificationCenter.default.publisher(for: .companySynced)
            .sink { [weak self] _ in
                Task {
                    await self?.checkSubscriptionStatus()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Public Methods
    
    /// Force a fresh sync of company data from the API
    @MainActor
    func forceRefresh() async {
        // SyncManager needs to be triggered from a view that has access to it
        // For now, just re-check the current subscription status
        await checkSubscriptionStatus()
    }
    
    /// Check subscription status and update UI state
    @MainActor
    func checkSubscriptionStatus() async {
        print("[SUBSCRIPTION] Checking subscription status...")
        
        guard let dataController = dataController else {
            print("[SUBSCRIPTION] Error: DataController not set")
            return
        }
        
        guard let userId = dataController.currentUser?.id else {
            print("[SUBSCRIPTION] Error: No current user")
            return
        }
        
        guard let company = dataController.getCurrentUserCompany() else {
            print("[SUBSCRIPTION] Error: No company found for user")
            return
        }
        
        
        // Log ALL subscription-related fields from company
        
        // Update subscription status from company
        if let status = company.subscriptionStatusEnum {
            subscriptionStatus = status
        } else {
            print("[SUBSCRIPTION] Warning: No valid subscription status enum found")
        }
        
        if let plan = company.subscriptionPlanEnum {
            subscriptionPlan = plan
        } else {
            print("[SUBSCRIPTION] Warning: No valid subscription plan enum found")
        }
        
        let seatedCount = company.getSeatedEmployeeIds().count
        print("[SUBSCRIPTION] Current state - Status: \(subscriptionStatus.rawValue), Plan: \(subscriptionPlan.rawValue), Seats: \(seatedCount)/\(company.maxSeats)")
        
        // Update seat information
        maxSeats = company.maxSeats
        hasPrioritySupport = company.hasPrioritySupport
        
        // Check if user is admin
        let adminIds = company.getAdminIds()
        isUserAdmin = adminIds.contains(userId)
        print("[SUBSCRIPTION] User admin check: \(isUserAdmin) (user: \(userId), admins: \(adminIds.count))")
        
        // Check if user is plan holder
        if let user = dataController.currentUser {
            isUserPlanHolder = user.isPlanHolder(for: company)
        }
        
        // Check if user has a seat
        let seatedEmployeeIds = company.getSeatedEmployeeIds()
        userHasSeat = seatedEmployeeIds.contains(userId)
        
        // Update trial/grace days
        trialDaysRemaining = company.daysRemainingInTrial
        graceDaysRemaining = company.daysRemainingInGracePeriod
        
        // Determine if should show lockout
        let previousLockoutState = shouldShowLockout
        shouldShowLockout = shouldLockoutUser()
        if previousLockoutState != shouldShowLockout {
        }
        
        // Determine if should show grace period banner
        shouldShowGracePeriodBanner = company.shouldShowGracePeriodWarning
        
        // Schedule notifications if needed
        await scheduleSubscriptionNotifications()
        
        // Load seated employees
        await loadSeatedEmployees()
        
    }
    
    /// Determine if user should be locked out
    /// Implements comprehensive 5-layer validation to prevent unauthorized access
    private func shouldLockoutUser() -> Bool {

        // LAYER 1: Check for nil/invalid company data
        guard let company = dataController?.getCurrentUserCompany() else {
            print("[AUTH] ❌ LAYER 1 FAILED: No company found for user")
            return true
        }

        // LAYER 2: Check for nil subscription status
        guard let companySubscriptionStatus = company.subscriptionStatusEnum else {
            print("[AUTH] ❌ LAYER 2 FAILED: Company has nil subscription status")
            return true
        }

        // LAYER 3: Check for invalid maxSeats (must be > 0)
        guard company.maxSeats > 0 else {
            print("[AUTH] ❌ LAYER 3 FAILED: Company has invalid maxSeats: \(company.maxSeats)")
            return true
        }

        // LAYER 4: Check if seated employees exceed maxSeats
        let seatedCount = company.getSeatedEmployeeIds().count
        if seatedCount > company.maxSeats {
            print("[AUTH] ❌ LAYER 4 FAILED: Seated employees (\(seatedCount)) exceed maxSeats (\(company.maxSeats))")
            return true
        }

        // LAYER 5: Check subscription status and validate trial date if needed
        switch companySubscriptionStatus {
        case .expired, .cancelled:
            print("[AUTH] ❌ Access denied - subscription \(companySubscriptionStatus.rawValue)")
            return true

        case .trial:
            // For trial status, validate trial end date exists
            if trialDaysRemaining == nil {
                print("[AUTH] ❌ LAYER 5 FAILED: Trial status but no trial end date")
                return true
            }

            // Check if trial has expired
            if let daysRemaining = trialDaysRemaining, daysRemaining <= 0 {
                print("[AUTH] ❌ Access denied - trial expired")
                return true
            } else {
                print("[AUTH] ✅ Access granted - trial active (\(trialDaysRemaining ?? 0) days left)")
            }

        case .active, .grace:
            // Check if user has a seat
            if !userHasSeat {
                // Show whether user is admin when denying access for no seat
                if isUserAdmin {
                    print("[AUTH] ❌ Access denied - admin user has no seat")
                } else {
                    print("[AUTH] ❌ Access denied - no seat available")
                }
                return true
            } else {
                print("[AUTH] ✅ Access granted - \(companySubscriptionStatus.rawValue) subscription with seat")
            }
        }

        print("[AUTH] ✅ All 5 validation layers passed")
        return false
    }
    
    /// Load seated employees from IDs
    @MainActor
    private func loadSeatedEmployees() async {
        guard let company = dataController?.getCurrentUserCompany() else { return }
        
        let seatedIds = company.getSeatedEmployeeIds()
        var employees: [User] = []
        
        for userId in seatedIds {
            if let user = dataController?.getUser(id: userId) {
                employees.append(user)
            }
        }
        
        seatedEmployees = employees
    }
    
    // MARK: - Seat Management
    
    /// Add a user to seated employees
    @MainActor
    func addSeat(for userId: String) async throws {
        guard let dataController = dataController,
              let company = dataController.getCurrentUserCompany() else {
            throw SubscriptionError.noCompany
        }
        
        guard isUserAdmin else {
            throw SubscriptionError.notAuthorized
        }
        
        guard company.hasAvailableSeats() else {
            throw SubscriptionError.noAvailableSeats
        }
        
        print("[SUBSCRIPTION] Adding seat for user: \(userId)")
        
        // Get current seated employee IDs and add the new one
        var currentSeatedIds = company.getSeatedEmployeeIds()
        if !currentSeatedIds.contains(userId) {
            currentSeatedIds.append(userId)
        }
        
        // Call API to update seated employees on Bubble
        do {
            print("[SUBSCRIPTION] Calling API to update seated employees on Bubble")
            let updatedCompanyDTO = try await dataController.apiService.updateCompanySeatedEmployees(
                companyId: company.id,
                seatedEmployeeIds: currentSeatedIds
            )
            
            print("[SUBSCRIPTION] API call successful, updating local company")
            
            // Update local company with the response from Bubble
            company.setSeatedEmployeeIds(
                updatedCompanyDTO.seatedEmployees?.compactMap { $0.stringValue } ?? []
            )
            
            // Save local changes
            try dataController.modelContext?.save()
            
            print("[SUBSCRIPTION] Seat added successfully for user: \(userId)")
            
            // Trigger a full sync to ensure everything is up to date
            NotificationCenter.default.post(name: .companySynced, object: nil)
            
        } catch {
            print("❌ Failed to update seated employees on Bubble: \(error)")
            throw SubscriptionError.syncFailed
        }
        
        // Refresh state
        await checkSubscriptionStatus()
    }
    
    /// Remove a user from seated employees
    @MainActor
    func removeSeat(for userId: String) async throws {
        guard let dataController = dataController,
              let company = dataController.getCurrentUserCompany() else {
            throw SubscriptionError.noCompany
        }
        
        guard isUserAdmin else {
            throw SubscriptionError.notAuthorized
        }
        
        // Prevent admin from removing their own seat
        guard userId != dataController.currentUser?.id else {
            throw SubscriptionError.cannotRemoveOwnSeat
        }
        
        print("[SUBSCRIPTION] Removing seat for user: \(userId)")
        
        // Get current seated employee IDs and remove the specified one
        var currentSeatedIds = company.getSeatedEmployeeIds()
        currentSeatedIds.removeAll { $0 == userId }
        
        // Call API to update seated employees on Bubble
        do {
            print("[SUBSCRIPTION] Calling API to update seated employees on Bubble")
            let updatedCompanyDTO = try await dataController.apiService.updateCompanySeatedEmployees(
                companyId: company.id,
                seatedEmployeeIds: currentSeatedIds
            )
            
            print("[SUBSCRIPTION] API call successful, updating local company")
            
            // Update local company with the response from Bubble
            company.setSeatedEmployeeIds(
                updatedCompanyDTO.seatedEmployees?.compactMap { $0.stringValue } ?? []
            )
            
            // Save local changes
            try dataController.modelContext?.save()
            
            print("[SUBSCRIPTION] Seat removed successfully for user: \(userId)")
            
            // Trigger a full sync to ensure everything is up to date
            NotificationCenter.default.post(name: .companySynced, object: nil)
            
        } catch {
            print("❌ Failed to update seated employees on Bubble: \(error)")
            throw SubscriptionError.syncFailed
        }
        
        // Refresh state
        await checkSubscriptionStatus()
    }
    
    /// Get the newest seated employee (for auto-removal)
    func getNewestSeatedEmployee() -> User? {
        // Return the last user in the seated employees array
        // (assuming they're ordered by join date)
        return seatedEmployees.last { user in
            // Don't auto-remove admins
            if let adminIds = dataController?.getCurrentUserCompany()?.getAdminIds() {
                return !adminIds.contains(user.id)
            }
            return false
        }
    }
    
    // MARK: - Notification Scheduling
    
    /// Schedule notifications for trial expiry and grace periods
    @MainActor
    private func scheduleSubscriptionNotifications() async {
        // Cancel existing subscription notifications
        await cancelExistingSubscriptionNotifications()
        
        // Schedule trial notifications
        if subscriptionStatus == .trial, let daysRemaining = trialDaysRemaining {
            await scheduleTrialNotifications(daysRemaining: daysRemaining)
        }
        
        // Schedule grace period notifications
        if subscriptionStatus == .grace, let daysRemaining = graceDaysRemaining {
            await scheduleGracePeriodNotifications(daysRemaining: daysRemaining)
        }
    }
    
    private func cancelExistingSubscriptionNotifications() async {
        let center = UNUserNotificationCenter.current()
        let requests = await center.pendingNotificationRequests()
        
        let subscriptionNotificationIds = requests.filter { request in
            request.content.categoryIdentifier == "SUBSCRIPTION_NOTIFICATION" ||
            request.content.categoryIdentifier == "TRIAL_NOTIFICATION" ||
            request.content.categoryIdentifier == "GRACE_PERIOD_NOTIFICATION"
        }.map { $0.identifier }
        
        if !subscriptionNotificationIds.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: subscriptionNotificationIds)
        }
    }
    
    private func scheduleTrialNotifications(daysRemaining: Int) async {
        // Schedule notifications for days 7, 3, and 1
        let notificationDays = [7, 3, 1]
        
        for day in notificationDays {
            if daysRemaining >= day {
                scheduleTrialExpiryNotification(daysBeforeExpiry: day)
            }
        }
    }
    
    private func scheduleGracePeriodNotifications(daysRemaining: Int) async {
        // Schedule daily notifications during grace period
        for day in 1...daysRemaining {
            scheduleGracePeriodNotification(daysRemaining: daysRemaining - day + 1)
        }
    }
    
    private func scheduleTrialExpiryNotification(daysBeforeExpiry: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Trial Ending Soon"
        
        if daysBeforeExpiry == 1 {
            content.body = "Your OPS trial expires tomorrow. Choose a plan to keep your team connected."
        } else {
            content.body = "Your OPS trial expires in \(daysBeforeExpiry) days. Choose a plan to continue."
        }
        
        content.sound = .default
        content.categoryIdentifier = "TRIAL_NOTIFICATION"
        
        // Schedule for 9 AM on the appropriate day
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        if let targetDate = Calendar.current.date(byAdding: .day, value: -daysBeforeExpiry + 1, to: Date()) {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.year = components.year
            dateComponents.month = components.month
            dateComponents.day = components.day
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "trial-expiry-\(daysBeforeExpiry)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    private func scheduleGracePeriodNotification(daysRemaining: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Action Required"
        
        if daysRemaining == 1 {
            content.body = "Last day of grace period. Update payment to maintain access."
        } else {
            content.body = "Grace period: \(daysRemaining) days remaining. Update payment to avoid service interruption."
        }
        
        content.sound = .default
        content.categoryIdentifier = "GRACE_PERIOD_NOTIFICATION"
        
        // Schedule for 9 AM each day
        var dateComponents = DateComponents()
        dateComponents.hour = 9
        dateComponents.minute = 0
        
        if let targetDate = Calendar.current.date(byAdding: .day, value: 7 - daysRemaining, to: Date()) {
            let components = Calendar.current.dateComponents([.year, .month, .day], from: targetDate)
            dateComponents.year = components.year
            dateComponents.month = components.month
            dateComponents.day = components.day
        }
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: false)
        let request = UNNotificationRequest(
            identifier: "grace-period-\(daysRemaining)",
            content: content,
            trigger: trigger
        )
        
        UNUserNotificationCenter.current().add(request)
    }
    
    // MARK: - Subscription Display
    
    /// Get formatted subscription status text for display
    func getSubscriptionStatusText() -> String {
        switch subscriptionStatus {
        case .trial:
            if let days = trialDaysRemaining {
                return "Trial - \(days) days left"
            }
            return "Trial"
        case .active:
            return "\(subscriptionPlan.displayName) Plan - Active"
        case .grace:
            if let days = graceDaysRemaining {
                return "Grace Period - \(days) days left"
            }
            return "Grace Period"
        case .expired:
            return "Subscription Expired"
        case .cancelled:
            return "Subscription Cancelled"
        }
    }
    
    /// Get badge text for priority support
    func getPrioritySupportBadge() -> String? {
        return hasPrioritySupport ? "Priority Support" : nil
    }
}

// MARK: - Error Types

enum SubscriptionError: LocalizedError {
    case noCompany
    case notAuthorized
    case noAvailableSeats
    case cannotRemoveOwnSeat
    case syncFailed
    
    var errorDescription: String? {
        switch self {
        case .noCompany:
            return "No company found"
        case .notAuthorized:
            return "You are not authorized to perform this action"
        case .noAvailableSeats:
            return "No available seats. Please upgrade your plan."
        case .cannotRemoveOwnSeat:
            return "You cannot remove your own seat"
        case .syncFailed:
            return "Failed to sync with server"
        }
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let companySynced = Notification.Name("companySynced")
    static let subscriptionStatusChanged = Notification.Name("subscriptionStatusChanged")
    static let criticalError = Notification.Name("criticalError")
    static let forceLogout = Notification.Name("forceLogout")
}

