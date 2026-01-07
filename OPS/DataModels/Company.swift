//
//  Company.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData
import CoreLocation

/// Company model - matches your Bubble Company structure exactly
@Model
final class Company {
    var id: String
    var name: String
    var logoURL: String?
    var logoData: Data?
    
    // Additional fields to match your Bubble structure
    var externalId: String?
    var companyDescription: String?
    var address: String?
    var phone: String?
    var email: String?
    var website: String?
    var latitude: Double?
    var longitude: Double?
    var openHour: String?
    var closeHour: String?
    
    // Company details
    var industryString: String = ""  // Store as comma-separated string
    var companySize: String?
    var companyAge: String?
    var referralMethod: String?
    
    // Array storage
    var projectIdsString: String = ""
    var teamIdsString: String = ""
    var adminIdsString: String = ""

    // Account holder (company owner)
    var accountHolderId: String?
    
    // Relationship to team members
    @Relationship(deleteRule: .cascade)
    var teamMembers: [TeamMember] = []
    
    // Relationship to task types
    @Relationship(deleteRule: .cascade)
    var taskTypes: [TaskType] = []

    // Relationship to inventory units
    @Relationship(deleteRule: .cascade)
    var inventoryUnits: [InventoryUnit] = []
    
    // Default color for project-level calendar events (hex)
    var defaultProjectColor: String = "#9CA3AF"  // Light grey default
    
    // Flag to track if team members have been synced
    var teamMembersSynced: Bool = false
    
    // Subscription fields
    var subscriptionStatus: String? // "trial", "active", "grace", "expired", "cancelled"
    var subscriptionPlan: String? // "trial", "starter", "team", "business"
    var subscriptionEnd: Date?
    var subscriptionPeriod: String? // "Monthly", "Annual"
    var maxSeats: Int = 10
    var seatedEmployeeIds: String = "" // Comma-separated list of user IDs
    var seatGraceStartDate: Date?
    
    // Multiple subscription IDs (for handling multiple plans)
    var subscriptionIdsJson: String? // JSON array of subscription objects [{subscriptionId: "", plan: ""}]
    
    // Trial management
    var trialStartDate: Date?
    var trialEndDate: Date?
    
    // Add-ons
    var hasPrioritySupport: Bool = false
    var dataSetupPurchased: Bool = false
    var dataSetupCompleted: Bool = false
    var dataSetupScheduledDate: Date?
    
    // Stripe integration
    var stripeCustomerId: String?
    
    // Offline/sync tracking
    var lastSyncedAt: Date?
    var needsSync: Bool = false

    // Soft delete support
    var deletedAt: Date?

    init(id: String, name: String) {
        self.id = id
        self.name = name
        self.projectIdsString = ""
        self.teamIdsString = ""
        self.teamMembers = []
    }
    
    // Array accessor methods
    func getProjectIds() -> [String] {
        return projectIdsString.isEmpty ? [] : projectIdsString.components(separatedBy: ",")
    }
    
    func setProjectIds(_ ids: [String]) {
        projectIdsString = ids.joined(separator: ",")
    }
    
    func getTeamIds() -> [String] {
        return teamIdsString.isEmpty ? [] : teamIdsString.components(separatedBy: ",")
    }
    
    func setTeamIds(_ ids: [String]) {
        teamIdsString = ids.joined(separator: ",")
    }
    
    func getAdminIds() -> [String] {
        return adminIdsString.isEmpty ? [] : adminIdsString.components(separatedBy: ",")
    }
    
    func setAdminIds(_ ids: [String]) {
        adminIdsString = ids.joined(separator: ",")
    }
    
    func getIndustries() -> [String] {
        return industryString.isEmpty ? [] : industryString.components(separatedBy: ",")
    }
    
    func setIndustries(_ industries: [String]) {
        industryString = industries.joined(separator: ",")
    }
    
    // Seated employee management
    func getSeatedEmployeeIds() -> [String] {
        return seatedEmployeeIds.isEmpty ? [] : seatedEmployeeIds.components(separatedBy: ",")
    }
    
    func setSeatedEmployeeIds(_ ids: [String]) {
        seatedEmployeeIds = ids.joined(separator: ",")
    }
    
    func addSeatedEmployee(_ userId: String) {
        var currentIds = getSeatedEmployeeIds()
        if !currentIds.contains(userId) {
            currentIds.append(userId)
            setSeatedEmployeeIds(currentIds)
        }
    }
    
    func removeSeatedEmployee(_ userId: String) {
        var currentIds = getSeatedEmployeeIds()
        currentIds.removeAll { $0 == userId }
        setSeatedEmployeeIds(currentIds)
    }
    
    func hasAvailableSeats() -> Bool {
        return getSeatedEmployeeIds().count < maxSeats
    }
    
    // Subscription status helpers
    var subscriptionStatusEnum: SubscriptionStatus? {
        guard let status = subscriptionStatus else { return nil }
        return SubscriptionStatus(rawValue: status)
    }
    
    var subscriptionPlanEnum: SubscriptionPlan? {
        guard let plan = subscriptionPlan else { return nil }
        return SubscriptionPlan(rawValue: plan)
    }
    
    var isSubscriptionActive: Bool {
        return subscriptionStatusEnum?.allowsAccess ?? false
    }
    
    var shouldShowGracePeriodWarning: Bool {
        return subscriptionStatusEnum?.showsWarning ?? false
    }
    
    var daysRemainingInTrial: Int? {
        guard let endDate = trialEndDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
        return max(0, days)
    }
    
    var daysRemainingInGracePeriod: Int? {
        // Since Bubble handles grace period expiration with recurring workflows,
        // we'll show a static grace period message when status is "grace"
        guard subscriptionStatusEnum == .grace else { return nil }
        
        // If we have a seat grace start date, calculate from that
        if let graceStart = seatGraceStartDate {
            let graceDays = 7
            let endDate = Calendar.current.date(byAdding: .day, value: graceDays, to: graceStart) ?? graceStart
            let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0
            return max(0, days)
        }
        
        // Otherwise, show a default message
        return 7 // Default grace period length
    }
    
    // Computed property for location
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude = latitude,
              let longitude = longitude else {
            return nil
        }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
    
    // Computed property for hours
    var hoursDisplay: String {
        if let open = openHour, let close = closeHour {
            return "\(open) - \(close)"
        }
        return "Hours not set"
    }
}
