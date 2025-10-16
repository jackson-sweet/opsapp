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
    }
    
    /// Job status values (from your Job Status custom type)
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
    struct EmployeeType {
        static let officeCrew = "Office Crew"
        static let fieldCrew = "Field Crew"
        
        static func toSwiftEnum(_ bubbleType: String) -> UserRole {
            switch bubbleType {
            case officeCrew: return .officeCrew
            case fieldCrew: return .fieldCrew
            default: return .fieldCrew // Default to field crew if unknown
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
        static let id = "_id" // Bubble uses _id for internal ID
        static let address = "Address"
        static let allDay = "All Day"
        static let client = "Client"
        static let company = "Company"
        static let completion = "Completion"
        static let description = "Description"
        static let projectName = "Project Name"
        static let startDate = "Start Date"
        static let status = "Status"
        static let teamMembers = "Team Members"
        static let teamNotes = "Team Notes"
        static let clientName = "Client Name"
    }
    
    /// User entity fields (match your Bubble field names exactly)
    struct User {
        static let id = "_id" // Bubble uses _id for internal ID
        static let clientID = "Client ID"
        static let company = "Company"
        static let currentLocation = "Current Location"
        static let employeeType = "Employee Type"
        static let nameFirst = "Name First"
        static let nameLast = "Name Last"
        static let userType = "User Type"
        static let avatar = "Avatar"
        static let email = "email" // Bubble's built-in field
        static let phone = "Phone"
        static let homeAddress = "Home Address"
    }
    
    /// Company entity fields (match your Bubble field names exactly)
    struct Company {
        static let id = "_id" // Bubble uses _id for internal ID
        static let companyName = "Company Name"
        static let companyID = "companyID"
        static let location = "Location"
        static let logo = "Logo"
        static let projects = "Projects"
        static let teams = "Teams"
    }
    
    /// Client entity fields (match your Bubble field names exactly)
    struct Client {
        static let id = "_id" // Bubble uses _id for internal ID
        static let address = "Address"
        static let balance = "Balance"
        static let clientIdNo = "Client ID No"
        static let clientsList = "Clients List"
        static let emailAddress = "Email Address"
        static let estimatesList = "Estimates List"
        static let invoices = "Invoices"
        static let isCompany = "Is Company"
        static let name = "Name"
        static let parentCompany = "Parent Company"
        static let phoneNumber = "Phone Number"
        static let projectsList = "Projects List"
        static let status = "Status"
        static let thumbnail = "Thumbnail"
        static let unit = "Unit"
        static let userId = "User ID"
    }
    
    /// SubClient entity fields (match your Bubble field names exactly)
    struct SubClient {
        static let id = "_id"
        static let address = "Address"
        static let emailAddress = "Email Address"
        static let name = "Name"
        static let parentClient = "Parent Client"
        static let phoneNumber = "Phone Number"
        static let title = "Title"
    }
    
    /// Task entity fields (match your Bubble field names exactly)
    struct Task {
        static let id = "_id"
        static let calendarEventId = "calendarEventId"
        static let companyId = "companyId"
        static let completionDate = "completionDate"
        static let projectID = "projectID"
        static let scheduledDate = "scheduledDate"
        static let status = "status"
        static let taskColor = "taskColor"
        static let taskIndex = "taskIndex"
        static let taskNotes = "taskNotes"
        static let teamMembers = "Team Members"
        static let type = "type"
    }
    
    /// TaskType entity fields (match your Bubble field names exactly)
    struct TaskType {
        static let id = "_id"
        static let color = "Color"
        static let display = "Display"
        static let isDefault = "isDefault"
    }
    
    /// CalendarEvent entity fields (match your Bubble field names exactly)
    struct CalendarEvent {
        static let id = "_id"
        static let active = "active"
        static let color = "Color"
        static let companyId = "companyId"  // lowercase 'c'
        static let duration = "Duration"
        static let endDate = "End Date"
        static let projectId = "projectId"  // lowercase 'p'
        static let startDate = "Start Date"
        static let taskId = "taskId"  // lowercase 't'
        static let teamMembers = "Team Members"
        static let title = "Title"
        static let type = "Type"
    }
    
    /// Task Status values
    struct TaskStatus {
        static let scheduled = "Scheduled"
        static let inProgress = "In Progress"
        static let completed = "Completed"
        static let cancelled = "Cancelled"
    }
}
