//
//  OrganizationDTO.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import Foundation

/// Data Transfer Object for Company from Bubble API
/// Designed to exactly match your Bubble data structure
struct CompanyDTO: Codable {
    // Use Bubble's exact field names in our CodingKeys
    
    // Company properties
    let id: String
    let companyName: String?
    let companyID: String?
    let companyDescription: String?
    let location: BubbleAddress?
    let logo: BubbleImage?
    let projects: [BubbleReference]?
    let teams: [BubbleReference]?
    let openHour: String?
    let closeHour: String?
    let phone: String?
    let officeEmail: String?
    let industry: [String]?
    let companySize: String?
    let companyAge: String?
    let employees: [BubbleReference]?
    let admin: [BubbleReference]?
    let website: String?
    
    // Project collections
    let activeProjects: [BubbleReference]?
    let completedProjects: [BubbleReference]?
    let lateProjects: [BubbleReference]?
    
    // Calendar and Tasks
    let calendarEventsList: [BubbleReference]?
    let defaultProjectColor: String?
    let taskTypes: [BubbleReference]?
    
    // Client management
    let clients: [BubbleReference]?
    let estimates: [BubbleReference]?
    let invoices: [BubbleReference]?
    
    // Financial
    let receivables: Double?
    let billingPeriodEnd: Date?
    
    // QuickBooks integration
    let qbConnected: Bool?
    let qbAccessToken: String?
    let qbAuthBasic: String?
    let qbCode: String?
    let qbCompanyId: String?
    let qbIdToken: String?
    let qbRefreshToken: String?
    
    // Security
    let securityClearances: [BubbleReference]?
    
    // Referral tracking
    let referralMethod: String?
    let referralMethodOther: String?
    
    // User management
    let accountHolder: BubbleReference?
    let registered: Int?
    let visit: Int?
    
    // Website
    let hasWebsite: Bool?
    
    // Subscription fields
    let subscriptionStatus: String?
    let subscriptionPlan: String?
    let subscriptionEnd: Date?
    let subscriptionPeriod: String?
    let maxSeats: Int?
    let seatedEmployees: [BubbleReference]?
    let seatGraceStartDate: Date?
    let seatGraceEndDate: Date?
    let reactivatedSubscription: Bool?
    let subscriptionEndls: [BubbleReference]?
    
    // Trial management
    let trialStartDate: Date?
    let trialEndDate: Date?
    
    // Add-ons
    let hasPrioritySupport: Bool?
    let dataSetupPurchased: Bool?
    let dataSetupCompleted: Bool?
    let dataSetupScheduledDate: Date?
    let prioritySupportPurchaseDate: Date?
    
    // Stripe
    let stripeCustomerId: String?

    // Soft delete support
    let deletedAt: String?


    // Custom coding keys to match Bubble's field names exactly
    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case companyName = "companyName"
        case companyID = "companyId"
        case companyDescription = "companyDescription"
        case location = "location"
        case logo = "logo"
        case projects = "projects"
        case teams = "teams"
        case openHour = "openHour"
        case closeHour = "closeHour"
        case phone = "phone"
        case officeEmail = "officeEmail"
        case industry = "industry"
        case companySize = "companySize"
        case companyAge = "companyAge"
        case employees = "employees"
        case admin = "admin"
        case website = "website"

        // Project collections
        case activeProjects = "activeProjects"
        case completedProjects = "completedProjects"
        case lateProjects = "lateProjects"

        // Calendar and Tasks
        case calendarEventsList = "calendarEventsList"
        case defaultProjectColor = "defaultProjectColor"
        case taskTypes = "taskTypes"

        // Client management
        case clients = "clients"
        case estimates = "estimates"
        case invoices = "invoices"

        // Financial
        case receivables = "receivables"
        case billingPeriodEnd = "billingPeriodEnd"

        // QuickBooks integration
        case qbConnected = "qbConnected"
        case qbAccessToken = "qbAccessToken"
        case qbAuthBasic = "qbAuthBasic"
        case qbCode = "qbCode"
        case qbCompanyId = "qbCompanyId"
        case qbIdToken = "qbIdToken"
        case qbRefreshToken = "qbRefreshToken"

        // Security
        case securityClearances = "securityClearances"

        // Referral tracking
        case referralMethod = "referralMethod"
        case referralMethodOther = "referralMethodOther"

        // User management
        case accountHolder = "accountHolder"
        case registered = "registered"
        case visit = "visit"
        
        // Website
        case hasWebsite = "hasWebsite"
        
        // Subscription fields
        case subscriptionStatus = "subscriptionStatus"
        case subscriptionPlan = "subscriptionPlan"
        case subscriptionEnd = "subscriptionEnd"
        case subscriptionPeriod = "subscriptionPeriod"
        case maxSeats = "maxSeats"
        case seatedEmployees = "seatedEmployees"
        case seatGraceStartDate = "seatGraceStartDate"
        case seatGraceEndDate = "seatGraceEndDate"
        case reactivatedSubscription = "reactivatedSubscription"
        case subscriptionEndls = "subscriptionEndls"
        
        // Trial fields
        case trialStartDate = "trialStartDate"
        case trialEndDate = "trialEndDate"
        
        // Add-on fields
        case hasPrioritySupport = "hasPrioritySupport"
        case dataSetupPurchased = "dataSetupPurchased"
        case dataSetupCompleted = "dataSetupCompleted"
        case dataSetupScheduledDate = "dataSetupScheduledDate"
        case prioritySupportPurchaseDate = "prioritySupportPurchDate"
        
        // Stripe
        case stripeCustomerId = "stripeCustomerId"

        // Soft delete
        case deletedAt = "deletedAt"
    }
    
    // Custom decoder to handle both UNIX timestamps (from Stripe) and ISO8601 dates (from Bubble)
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Decode required fields
        self.id = try container.decode(String.self, forKey: .id)
        
        // Decode optional string fields
        self.companyName = try container.decodeIfPresent(String.self, forKey: .companyName)
        self.companyID = try container.decodeIfPresent(String.self, forKey: .companyID)
        self.companyDescription = try container.decodeIfPresent(String.self, forKey: .companyDescription)
        self.openHour = try container.decodeIfPresent(String.self, forKey: .openHour)
        self.closeHour = try container.decodeIfPresent(String.self, forKey: .closeHour)
        self.phone = try container.decodeIfPresent(String.self, forKey: .phone)
        self.officeEmail = try container.decodeIfPresent(String.self, forKey: .officeEmail)
        self.companySize = try container.decodeIfPresent(String.self, forKey: .companySize)
        self.companyAge = try container.decodeIfPresent(String.self, forKey: .companyAge)
        self.website = try container.decodeIfPresent(String.self, forKey: .website)
        self.defaultProjectColor = try container.decodeIfPresent(String.self, forKey: .defaultProjectColor)
        self.referralMethod = try container.decodeIfPresent(String.self, forKey: .referralMethod)
        self.referralMethodOther = try container.decodeIfPresent(String.self, forKey: .referralMethodOther)
        self.subscriptionStatus = try container.decodeIfPresent(String.self, forKey: .subscriptionStatus)
        self.subscriptionPlan = try container.decodeIfPresent(String.self, forKey: .subscriptionPlan)
        self.subscriptionPeriod = try container.decodeIfPresent(String.self, forKey: .subscriptionPeriod)
        self.stripeCustomerId = try container.decodeIfPresent(String.self, forKey: .stripeCustomerId)
        
        // Decode complex object fields
        self.location = try container.decodeIfPresent(BubbleAddress.self, forKey: .location)
        self.logo = try container.decodeIfPresent(BubbleImage.self, forKey: .logo)
        self.projects = try container.decodeIfPresent([BubbleReference].self, forKey: .projects)
        self.teams = try container.decodeIfPresent([BubbleReference].self, forKey: .teams)
        self.employees = try container.decodeIfPresent([BubbleReference].self, forKey: .employees)
        self.admin = try container.decodeIfPresent([BubbleReference].self, forKey: .admin)
        self.activeProjects = try container.decodeIfPresent([BubbleReference].self, forKey: .activeProjects)
        self.completedProjects = try container.decodeIfPresent([BubbleReference].self, forKey: .completedProjects)
        self.lateProjects = try container.decodeIfPresent([BubbleReference].self, forKey: .lateProjects)
        self.calendarEventsList = try container.decodeIfPresent([BubbleReference].self, forKey: .calendarEventsList)
        self.taskTypes = try container.decodeIfPresent([BubbleReference].self, forKey: .taskTypes)
        self.clients = try container.decodeIfPresent([BubbleReference].self, forKey: .clients)
        self.estimates = try container.decodeIfPresent([BubbleReference].self, forKey: .estimates)
        self.invoices = try container.decodeIfPresent([BubbleReference].self, forKey: .invoices)
        self.securityClearances = try container.decodeIfPresent([BubbleReference].self, forKey: .securityClearances)
        self.accountHolder = try container.decodeIfPresent(BubbleReference.self, forKey: .accountHolder)
        self.seatedEmployees = try container.decodeIfPresent([BubbleReference].self, forKey: .seatedEmployees)
        self.subscriptionEndls = try container.decodeIfPresent([BubbleReference].self, forKey: .subscriptionEndls)
        
        // Decode array fields
        self.industry = try container.decodeIfPresent([String].self, forKey: .industry)
        
        // Decode numeric fields
        self.receivables = try container.decodeIfPresent(Double.self, forKey: .receivables)
        self.registered = try container.decodeIfPresent(Int.self, forKey: .registered)
        self.visit = try container.decodeIfPresent(Int.self, forKey: .visit)
        self.maxSeats = try container.decodeIfPresent(Int.self, forKey: .maxSeats)
        
        // Decode boolean fields
        self.qbConnected = try container.decodeIfPresent(Bool.self, forKey: .qbConnected)
        self.hasWebsite = try container.decodeIfPresent(Bool.self, forKey: .hasWebsite)
        self.reactivatedSubscription = try container.decodeIfPresent(Bool.self, forKey: .reactivatedSubscription)
        self.hasPrioritySupport = try container.decodeIfPresent(Bool.self, forKey: .hasPrioritySupport)
        self.dataSetupPurchased = try container.decodeIfPresent(Bool.self, forKey: .dataSetupPurchased)
        self.dataSetupCompleted = try container.decodeIfPresent(Bool.self, forKey: .dataSetupCompleted)
        
        // Decode QuickBooks fields
        self.qbAccessToken = try container.decodeIfPresent(String.self, forKey: .qbAccessToken)
        self.qbAuthBasic = try container.decodeIfPresent(String.self, forKey: .qbAuthBasic)
        self.qbCode = try container.decodeIfPresent(String.self, forKey: .qbCode)
        self.qbCompanyId = try container.decodeIfPresent(String.self, forKey: .qbCompanyId)
        self.qbIdToken = try container.decodeIfPresent(String.self, forKey: .qbIdToken)
        self.qbRefreshToken = try container.decodeIfPresent(String.self, forKey: .qbRefreshToken)
        
        // Decode date fields with special handling for UNIX timestamps vs ISO8601 dates
        // Stripe-related fields are typically UNIX timestamps
        self.subscriptionEnd = Self.decodeFlexibleDate(from: container, forKey: .subscriptionEnd, isStripeField: true)
        self.billingPeriodEnd = Self.decodeFlexibleDate(from: container, forKey: .billingPeriodEnd, isStripeField: true)
        self.seatGraceStartDate = Self.decodeFlexibleDate(from: container, forKey: .seatGraceStartDate, isStripeField: true)
        self.seatGraceEndDate = Self.decodeFlexibleDate(from: container, forKey: .seatGraceEndDate, isStripeField: true)
        
        // Trial and setup fields may also be UNIX timestamps if they come from Stripe
        self.trialStartDate = Self.decodeFlexibleDate(from: container, forKey: .trialStartDate, isStripeField: true)
        self.trialEndDate = Self.decodeFlexibleDate(from: container, forKey: .trialEndDate, isStripeField: true)
        self.dataSetupScheduledDate = Self.decodeFlexibleDate(from: container, forKey: .dataSetupScheduledDate, isStripeField: false)
        self.prioritySupportPurchaseDate = Self.decodeFlexibleDate(from: container, forKey: .prioritySupportPurchaseDate, isStripeField: true)

        // Soft delete
        self.deletedAt = try container.decodeIfPresent(String.self, forKey: .deletedAt)

        print("[CompanyDTO] Successfully decoded company with ID: \(id)")
    }
    
    /// Decodes date fields that may be either UNIX timestamps (numbers) or ISO8601 strings
    /// - Parameters:
    ///   - container: The decoder container
    ///   - key: The coding key for the date field
    ///   - isStripeField: Whether this field typically comes from Stripe (UNIX timestamp) or Bubble (ISO8601)
    /// - Returns: Decoded Date or nil
    private static func decodeFlexibleDate(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys, isStripeField: Bool) -> Date? {
        // First check if the field exists
        guard container.contains(key) else {
            return nil
        }
        
        // Try to decode as number first (UNIX timestamp) - especially for Stripe fields
        if let timestamp = try? container.decodeIfPresent(Double.self, forKey: key) {
            let date = Date(timeIntervalSince1970: timestamp)
            print("[CompanyDTO] Decoded \(key.rawValue) as UNIX timestamp: \(timestamp) -> \(date)")
            return date
        }
        
        // Try to decode as Int UNIX timestamp
        if let timestamp = try? container.decodeIfPresent(Int.self, forKey: key) {
            let date = Date(timeIntervalSince1970: Double(timestamp))
            print("[CompanyDTO] Decoded \(key.rawValue) as Int UNIX timestamp: \(timestamp) -> \(date)")
            return date
        }
        
        // Try to decode as ISO8601 string (typical for Bubble fields)
        if let dateString = try? container.decodeIfPresent(String.self, forKey: key) {
            if let date = DateFormatter.dateFromBubble(dateString) {
                print("[CompanyDTO] Decoded \(key.rawValue) as ISO8601 string: \(dateString) -> \(date)")
                return date
            } else {
                print("[CompanyDTO] Failed to parse date string for \(key.rawValue): \(dateString)")
                return nil
            }
        }
        
        print("[CompanyDTO] Could not decode date field \(key.rawValue) - field exists but format unrecognized")
        return nil
    }
    
    /// Convert DTO to SwiftData model
    func toModel() -> Company {
        // Create company
        let company = Company(
            id: id,
            name: companyName ?? "Unknown Company"
        )
        
        // Handle Company ID
        company.externalId = companyID
        
        // Handle description
        company.companyDescription = companyDescription
        
        // Handle location
        if let loc = location {
            company.address = loc.formattedAddress
            company.latitude = loc.lat
            company.longitude = loc.lng
        }
        
        // Handle contact information
        company.phone = phone
        company.email = officeEmail
        company.website = website
        
        // Handle logo
        if let logoImage = logo, let logoUrl = logoImage.url {
            company.logoURL = logoUrl
            // Note: Actual image data will need to be downloaded separately
        }
        
        // Handle hours
        company.openHour = openHour
        company.closeHour = closeHour
        
        // Handle projects and teams - using the string storage methods
        if let projectRefs = projects {
            let projectIds = projectRefs.compactMap { $0.stringValue }
            company.projectIdsString = projectIds.joined(separator: ",")
        }
        
        if let teamRefs = teams {
            let teamIds = teamRefs.compactMap { $0.stringValue }
            company.teamIdsString = teamIds.joined(separator: ",")
        }
        
        // Handle admin list
        if let adminRefs = admin {
            let adminIds = adminRefs.compactMap { $0.stringValue }
            company.adminIdsString = adminIds.joined(separator: ",")
            print("[SUBSCRIPTION] Admin IDs: \(adminIds.count) admins")
        }
        
        // Handle company details
        company.setIndustries(industry ?? [])
        company.companySize = companySize
        company.companyAge = companyAge
        company.referralMethod = nil // Not in DTO yet
        
        // Handle subscription status
        if let status = subscriptionStatus {
            // CRITICAL FIX: Convert to lowercase to match enum values
            // The SubscriptionStatus enum expects lowercase values but Bubble might send them in different cases
            let normalizedStatus = status.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            company.subscriptionStatus = normalizedStatus
            print("[SUBSCRIPTION] From Bubble: Status=\(status) -> \(normalizedStatus)")
        } else {
            company.subscriptionStatus = nil
            print("[SUBSCRIPTION] From Bubble: Status=nil")
        }
        
        // Handle subscription plan
        if let plan = subscriptionPlan {
            // CRITICAL FIX: Convert to lowercase to match enum values
            let normalizedPlan = plan.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            company.subscriptionPlan = normalizedPlan
            print("[SUBSCRIPTION] From Bubble: Plan=\(plan) -> \(normalizedPlan)")
        } else {
            company.subscriptionPlan = nil
            print("[SUBSCRIPTION] From Bubble: Plan=nil")
        }
        
        // Handle subscription end date
        if let endDate = subscriptionEnd {
            company.subscriptionEnd = endDate
        } else {
            company.subscriptionEnd = nil
        }
        
        // Handle subscription period
        if let period = subscriptionPeriod {
            company.subscriptionPeriod = period
        } else {
            company.subscriptionPeriod = nil
        }
        
        // Handle max seats - use exactly what Bubble sends, default to 0 if nil
        company.maxSeats = maxSeats ?? 0
        let seatedCount = seatedEmployees?.count ?? 0
        print("[SUBSCRIPTION] From Bubble: Seats=\(seatedCount)/\(company.maxSeats)")
        
        // Handle seated employees
        if let seatedRefs = seatedEmployees {
            print("[SUBSCRIPTION] 🔍 Processing seated employees: \(seatedRefs.count) refs")
            let seatedIds = seatedRefs.compactMap { $0.stringValue }
            print("[SUBSCRIPTION] 🔍 Extracted \(seatedIds.count) seated IDs: \(seatedIds)")
            company.setSeatedEmployeeIds(seatedIds)
            print("[SUBSCRIPTION] ✅ Set seated employees on company: \(company.getSeatedEmployeeIds())")
            if seatedIds.isEmpty && !seatedRefs.isEmpty {
                print("[SUBSCRIPTION] ⚠️ Warning: Seated employees present but no valid IDs extracted")
                print("[SUBSCRIPTION] ⚠️ Raw refs: \(seatedRefs)")
            }
        } else {
            print("[SUBSCRIPTION] ⚠️ Warning: seatedEmployees field is nil from Bubble")
        }
        
        // Handle grace period start
        if let graceStart = seatGraceStartDate {
            company.seatGraceStartDate = graceStart
        } else {
            company.seatGraceStartDate = nil
        }
        
        // Handle trial fields
        if let trialStart = trialStartDate {
            company.trialStartDate = trialStart
        }
        
        if let trialEnd = trialEndDate {
            company.trialEndDate = trialEnd
        }
        
        // Handle add-ons
        
        company.hasPrioritySupport = hasPrioritySupport ?? false
        company.dataSetupPurchased = dataSetupPurchased ?? false
        company.dataSetupCompleted = dataSetupCompleted ?? false
        company.dataSetupScheduledDate = dataSetupScheduledDate
        
        // Handle Stripe
        if let stripeId = stripeCustomerId {
            company.stripeCustomerId = stripeId
        }

        // Parse deletedAt if present
        if let deletedAtString = deletedAt {
            let formatter = ISO8601DateFormatter()
            company.deletedAt = formatter.date(from: deletedAtString)
        }

        company.lastSyncedAt = Date()


        return company
    }
}
