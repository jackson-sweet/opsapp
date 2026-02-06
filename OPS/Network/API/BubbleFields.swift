//
//  BubbleFields.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//

import Foundation

/// Exact field mappings from Bubble to Swift
/// This ensures our code matches your Bubble database structure perfectly
struct BubbleFields {
    
    /// Entity types in Bubble
    struct Types {
        static let client = "Client"
        static let company = "Company"
        static let project = "Project"
        static let user = "User"
        static let subClient = "Sub Client"  // Note the space - Bubble uses "Sub Client"
        static let task = "Task"
        static let taskType = "TaskType"
        static let calendarEvent = "calendarevent"  // Bubble uses lowercase
        static let inventoryItem = "inventoryitem"  // Bubble API uses lowercase
        static let inventoryUnit = "inventoryunit"  // Bubble API uses lowercase
        static let inventorySnapshot = "inventorysnapshot"  // Bubble API uses lowercase
        static let inventorySnapshotItem = "inventorysnapshotitem"  // Bubble API uses lowercase
        static let tag = "tag"  // Bubble API uses lowercase
        static let tutorialLog = "TutorialLog"
    }

    /// TutorialLog fields (analytics for tutorial completion tracking)
    struct TutorialLog {
        static let date = "date"
        static let appVersion = "appVersion"
        static let isLoggedIn = "isLoggedIn"
        static let flowType = "flowType"
        static let stepsCompleted = "stepsCompleted"
        static let lastCompletedStep = "lastCompletedStep"
        static let completed = "completed"
        static let skipped = "skipped"
        static let durationSeconds = "durationSeconds"
    }
    
    /// Job status values (from your Job Status custom type)
    /// NOTE: Display values remain unchanged (capitalized)
    struct JobStatus {
        static let rfq = "RFQ"
        static let estimated = "Estimated"
        static let accepted = "Accepted"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let closed = "Closed"
        static let archived = "Archived"

        static func toSwiftEnum(_ bubbleStatus: String) -> Status {
            switch bubbleStatus {
            case rfq: return .rfq
            case estimated: return .estimated
            case accepted: return .accepted
            case inProgress: return .inProgress
            case completed: return .completed
            case closed: return .closed
            case archived: return .archived
            default: return .rfq // Default to RFQ if unknown
            }
        }
    }
    
    /// Employee Type values (from your Employee Type custom type)
    /// ACTUAL BUBBLE VALUES: "Office Crew", "Field Crew", "Admin"
    struct EmployeeType {
        static let officeCrew = "Office Crew"
        static let fieldCrew = "Field Crew"
        static let admin = "Admin"

        static func toSwiftEnum(_ bubbleType: String) -> UserRole {
            switch bubbleType {
            case officeCrew: return .officeCrew  // "Office Crew" → .officeCrew
            case fieldCrew: return .fieldCrew    // "Field Crew" → .fieldCrew
            case admin: return .admin            // "Admin" → .admin (company admin)
            default: return .fieldCrew           // Default to field crew if unknown
            }
        }
    }
    
    /// User Type values (from your User Type custom type)
    struct UserType {
        static let company = "Company"
        static let employee = "Employee"
        static let client = "Client"
        static let admin = "Admin"
    }
    
    /// Project entity fields (match your Bubble field names exactly)
    struct Project {
        static let id = "_id"
        static let address = "address"
        static let allDay = "allDay"
        static let calendarEvent = "calendarEvent"
        static let client = "client"
        static let company = "company"
        static let completion = "completion"
        static let description = "description"
        static let eventType = "eventType"
        static let projectName = "projectName"
        static let startDate = "startDate"
        static let status = "status"
        static let teamMembers = "teamMembers"
        static let teamNotes = "teamNotes"
        static let clientName = "clientName"
        static let tasks = "tasks"
    }
    
    /// User entity fields (match your Bubble field names exactly)
    struct User {
        static let id = "_id"
        static let clientID = "clientId"
        static let company = "company"
        static let currentLocation = "currentLocation"
        static let employeeType = "employeeType"
        static let nameFirst = "nameFirst"
        static let nameLast = "nameLast"
        static let userType = "userType"
        static let avatar = "avatar"
        static let profileImageURL = "profileImageURL"
        static let email = "email"
        static let phone = "phone"
        static let homeAddress = "homeAddress"
        static let deviceToken = "deviceToken"  // APNs device token for push notifications
        static let hasCompletedAppTutorial = "hasCompletedAppTutorial"  // Bool for tutorial completion
        static let inventoryAccess = "inventoryAccess"  // Bool for inventory feature access
    }
    
    /// Company entity fields (match your Bubble field names exactly)
    struct Company {
        static let id = "_id"
        static let companyName = "companyName"
        static let companyID = "companyId"
        static let location = "location"
        static let logo = "logo"  // Company logo image URL (actual Bubble field name)
        static let logoURL = "logoURL"  // Legacy/alternative field
        static let defaultProjectColor = "defaultProjectColor"  // Hex color for projects
        static let projects = "projects"
        static let teams = "teams"
        static let clients = "clients"
        static let taskTypes = "taskTypes"
        static let calendarEventsList = "calendarEventsList"
        static let inventoryUnits = "inventoryUnits"  // List of InventoryUnit references
    }
    
    /// Client entity fields (match your Bubble field names exactly)
    struct Client {
        static let id = "_id"
        static let address = "address"
        static let balance = "balance"
        static let clientIdNo = "clientIdNo"
        static let subClients = "subClients"  // Changed from "clientsList"
        static let emailAddress = "emailAddress"
        static let estimates = "estimates"  // Changed from "Estimates List" to "estimates"
        static let invoices = "invoices"
        static let isCompany = "isCompany"
        static let name = "name"
        static let parentCompany = "parentCompany"
        static let phoneNumber = "phoneNumber"
        static let projectsList = "projectsList"
        static let status = "status"
        static let avatar = "avatar"  // Changed from "Thumbnail" to "avatar"
        static let unit = "unit"
        static let userId = "userId"
        static let notes = "notes"
    }
    
    /// SubClient entity fields (match your Bubble field names exactly)
    struct SubClient {
        static let id = "_id"
        static let address = "address"
        static let emailAddress = "emailAddress"
        static let name = "name"
        static let parentClient = "parentClient"
        static let phoneNumber = "phoneNumber"
        static let title = "title"
    }

    struct TaskStatusOption {
        static let id = "_id"
        static let display = "Display"
        static let company = "company"
        static let color = "color"
        static let index = "index"
    }
    
    /// Task entity fields (match your Bubble field names exactly)
    struct Task {
        static let id = "_id"
        static let calendarEventId = "calendarEventId"
        static let companyId = "companyId"
        static let completionDate = "completionDate"
        static let projectId = "projectId"
        static let scheduledDate = "scheduledDate"
        static let status = "status"
        static let taskColor = "taskColor"
        static let taskIndex = "taskIndex"
        static let taskNotes = "taskNotes"
        static let teamMembers = "teamMembers"
        static let type = "type"
    }
    
    /// TaskType entity fields (match your Bubble field names exactly)
    struct TaskType {
        static let id = "_id"
        static let color = "color"
        static let display = "display"
        static let isDefault = "isDefault"
    }
    
    /// CalendarEvent entity fields (match your Bubble field names exactly)
    struct CalendarEvent {
        static let id = "_id"
        static let active = "active"
        static let color = "color"
        static let companyId = "companyId"
        static let duration = "duration"
        static let endDate = "endDate"
        static let projectId = "projectId"
        static let startDate = "startDate"
        static let taskId = "taskId"
        static let teamMembers = "teamMembers"
        static let title = "title"
        static let eventType = "eventType"
    }
    
    /// Task Status values
    /// NOTE: Display values remain unchanged (capitalized)
    struct TaskStatus {
        static let booked = "Booked"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let cancelled = "Cancelled"
    }

    /// InventoryItem entity fields (match your Bubble field names exactly)
    struct InventoryItem {
        static let id = "_id"
        static let name = "name"
        static let description = "description"
        static let quantity = "quantity"
        static let unit = "unit"
        static let tags = "tags"
        static let company = "company"
        static let sku = "sku"
        static let notes = "notes"
        static let imageUrl = "imageUrl"
        static let deletedAt = "deletedAt"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
    }

    /// InventoryUnit entity fields (match your Bubble field names exactly)
    struct InventoryUnit {
        static let id = "_id"
        static let display = "display"
        static let company = "company"
        static let isDefault = "isDefault"
        static let sortOrder = "sortOrder"
        static let deletedAt = "deletedAt"
    }

    /// InventorySnapshot entity fields (match your Bubble field names exactly)
    struct InventorySnapshot {
        static let id = "_id"
        static let company = "company"
        static let createdAt = "createdAt"
        static let createdBy = "createdBy"
        static let isAutomatic = "isAutomatic"
        static let itemCount = "itemCount"
        static let notes = "notes"
    }

    /// InventorySnapshotItem entity fields (match your Bubble field names exactly)
    struct InventorySnapshotItem {
        static let id = "_id"
        static let snapshot = "snapshot"
        static let originalItemId = "originalItemId"
        static let name = "name"
        static let quantity = "quantity"
        static let unitDisplay = "unitDisplay"
        static let sku = "sku"
        static let tags = "tags"
        static let description = "description"
    }

    /// Tag entity fields (match your Bubble field names exactly)
    /// Tags for inventory items with optional quantity thresholds
    struct Tag {
        static let id = "_id"
        static let name = "name"
        static let warningThreshold = "warningThreshold"
        static let criticalThreshold = "criticalThreshold"
        static let company = "company"
        static let deletedAt = "deletedAt"
    }
}
