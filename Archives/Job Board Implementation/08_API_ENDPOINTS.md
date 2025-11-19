# API Endpoints Specification

## Overview
Complete specification of all Bubble API endpoints required for Job Board functionality, including request/response formats and error handling.

## Base Configuration
```swift
struct APIConfiguration {
    static let baseURL = "https://ops-app-kt5421.bubbleapps.io/version-test/api/1.1"
    static let apiKey = "YOUR_API_KEY" // Stored in Keychain
    
    static var headers: [String: String] {
        [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json",
            "Accept": "application/json"
        ]
    }
}
```

## Client Endpoints

### Create Client
```swift
// POST /obj/client
struct CreateClientRequest: Encodable {
    let name_text: String
    let email_text: String?
    let phone_text: String?
    let address_text: String?
    let notes_text: String?
    let company_id_text: String
    let created_by_text: String // User ID
}

struct CreateClientResponse: Decodable {
    let status: String
    let response: ClientDTO
}

// Implementation
func createClient(_ request: CreateClientRequest) async throws -> Client {
    let url = URL(string: "\(APIConfiguration.baseURL)/obj/client")!
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    urlRequest.httpBody = try JSONEncoder().encode(request)
    
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.requestFailed
    }
    
    let result = try JSONDecoder().decode(CreateClientResponse.self, from: data)
    return result.response.toClient()
}
```

### Update Client
```swift
// PUT /obj/client/{id}
struct UpdateClientRequest: Encodable {
    let name_text: String?
    let email_text: String?
    let phone_text: String?
    let address_text: String?
    let notes_text: String?
    let modified_by_text: String // User ID
    let Modified_Date: String // ISO 8601
}

// Implementation
func updateClient(_ clientId: String, _ request: UpdateClientRequest) async throws -> Client {
    let url = URL(string: "\(APIConfiguration.baseURL)/obj/client/\(clientId)")!
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "PUT"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    urlRequest.httpBody = try JSONEncoder().encode(request)
    
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.requestFailed
    }
    
    let result = try JSONDecoder().decode(ClientDTO.self, from: data)
    return result.toClient()
}
```

### Delete Client
```swift
// DELETE /obj/client/{id}
func deleteClient(_ clientId: String) async throws {
    let url = URL(string: "\(APIConfiguration.baseURL)/obj/client/\(clientId)")!
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "DELETE"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    
    let (_, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.deleteFailed
    }
}
```

### Check Duplicate Client
```swift
// GET /wf/check-duplicate-client
struct DuplicateCheckRequest {
    let name: String
    let email: String?
    let companyId: String
}

struct DuplicateCheckResponse: Decodable {
    let status: String
    let response: DuplicateResult
    
    struct DuplicateResult: Decodable {
        let isDuplicate: Bool
        let similarClients: [SimilarClient]
        
        struct SimilarClient: Decodable {
            let id: String
            let name: String
            let email: String?
            let similarity: Double // 0.0 to 1.0
        }
    }
}

// Implementation
func checkDuplicateClient(_ request: DuplicateCheckRequest) async throws -> DuplicateCheckResponse.DuplicateResult {
    var components = URLComponents(string: "\(APIConfiguration.baseURL)/wf/check-duplicate-client")!
    components.queryItems = [
        URLQueryItem(name: "name", value: request.name),
        URLQueryItem(name: "email", value: request.email),
        URLQueryItem(name: "company_id", value: request.companyId)
    ]
    
    var urlRequest = URLRequest(url: components.url!)
    urlRequest.httpMethod = "GET"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    
    let (data, _) = try await URLSession.shared.data(for: urlRequest)
    let result = try JSONDecoder().decode(DuplicateCheckResponse.self, from: data)
    
    return result.response
}
```

## Project Endpoints

### Create Project
```swift
// POST /wf/create-project
struct CreateProjectRequest: Encodable {
    let title_text: String
    let client_id_text: String
    let address_text: String?
    let description_text: String?
    let notes_text: String?
    let scheduling_mode_text: String // "project" or "task"
    let start_date_date: String? // ISO 8601
    let end_date_date: String? // ISO 8601
    let all_day_boolean: Bool
    let team_member_ids_list: [String]
    let company_id_text: String
    let created_by_text: String
}

struct CreateProjectResponse: Decodable {
    let status: String
    let response: ProjectWithCalendarEvent
    
    struct ProjectWithCalendarEvent: Decodable {
        let project: ProjectDTO
        let calendarEvent: CalendarEventDTO?
    }
}

// Implementation
func createProject(_ request: CreateProjectRequest) async throws -> (Project, CalendarEvent?) {
    let url = URL(string: "\(APIConfiguration.baseURL)/wf/create-project")!
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    urlRequest.httpBody = try JSONEncoder().encode(request)
    
    let (data, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.requestFailed
    }
    
    let result = try JSONDecoder().decode(CreateProjectResponse.self, from: data)
    let project = result.response.project.toProject()
    let calendarEvent = result.response.calendarEvent?.toCalendarEvent()
    
    return (project, calendarEvent)
}
```

### Update Project
```swift
// PUT /obj/project/{id}
struct UpdateProjectRequest: Encodable {
    let title_text: String?
    let client_id_text: String?
    let address_text: String?
    let description_text: String?
    let notes_text: String?
    let status_text: String?
    let team_member_ids_list: [String]?
    let modified_by_text: String
    let Modified_Date: String
}
```

### Update Project Scheduling Mode
```swift
// POST /wf/update-scheduling-mode
struct UpdateSchedulingModeRequest: Encodable {
    let project_id_text: String
    let scheduling_mode_text: String // "project" or "task"
    let calendar_event_updates_list: [CalendarEventUpdate]
    
    struct CalendarEventUpdate: Encodable {
        let event_id_text: String
        let active_boolean: Bool
    }
}

struct UpdateSchedulingModeResponse: Decodable {
    let status: String
    let response: UpdateResult
    
    struct UpdateResult: Decodable {
        let project: ProjectDTO
        let updatedEvents: [CalendarEventDTO]
    }
}
```

### Delete Project
```swift
// POST /wf/delete-project
struct DeleteProjectRequest: Encodable {
    let project_id_text: String
    let delete_tasks_boolean: Bool // Always true for our use case
}

func deleteProject(_ projectId: String) async throws {
    let url = URL(string: "\(APIConfiguration.baseURL)/wf/delete-project")!
    
    let request = DeleteProjectRequest(
        project_id_text: projectId,
        delete_tasks_boolean: true
    )
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "POST"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    urlRequest.httpBody = try JSONEncoder().encode(request)
    
    let (_, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.deleteFailed
    }
}
```

## Task Endpoints

### Create Task
```swift
// POST /wf/create-task
struct CreateTaskRequest: Encodable {
    let project_id_text: String
    let task_type_id_text: String
    let notes_text: String?
    let team_member_ids_list: [String]
    let start_date_date: String
    let end_date_date: String
    let all_day_boolean: Bool
    let created_by_text: String
}

struct CreateTaskResponse: Decodable {
    let status: String
    let response: TaskWithCalendarEvent
    
    struct TaskWithCalendarEvent: Decodable {
        let task: TaskDTO
        let calendarEvent: CalendarEventDTO
    }
}
```

### Update Task
```swift
// PUT /obj/task/{id}
struct UpdateTaskRequest: Encodable {
    let task_type_id_text: String?
    let notes_text: String?
    let team_member_ids_list: [String]?
    let start_date_date: String?
    let end_date_date: String?
    let status_text: String?
    let modified_by_text: String
    let Modified_Date: String
}
```

### Delete Task
```swift
// DELETE /obj/task/{id}
func deleteTask(_ taskId: String) async throws {
    let url = URL(string: "\(APIConfiguration.baseURL)/obj/task/\(taskId)")!
    
    var urlRequest = URLRequest(url: url)
    urlRequest.httpMethod = "DELETE"
    urlRequest.allHTTPHeaderFields = APIConfiguration.headers
    
    let (_, response) = try await URLSession.shared.data(for: urlRequest)
    
    guard let httpResponse = response as? HTTPURLResponse,
          httpResponse.statusCode == 200 else {
        throw APIError.deleteFailed
    }
}
```

## Task Type Endpoints

### Create Task Type
```swift
// POST /obj/task_type
struct CreateTaskTypeRequest: Encodable {
    let display_text: String
    let color_text: String // Hex color
    let icon_text: String? // SF Symbol name
    let company_id_text: String
    let is_default_boolean: Bool // Always false for custom types
    let display_order_number: Int
}

struct CreateTaskTypeResponse: Decodable {
    let status: String
    let response: TaskTypeDTO
}
```

### Update Task Type
```swift
// PUT /obj/task_type/{id}
struct UpdateTaskTypeRequest: Encodable {
    let display_text: String?
    let color_text: String?
    let icon_text: String?
    let display_order_number: Int?
}
```

### Delete Task Type with Reassignment
```swift
// POST /wf/delete-task-type
struct DeleteTaskTypeRequest: Encodable {
    let task_type_id_text: String
    let replacement_type_id_text: String
}

struct DeleteTaskTypeResponse: Decodable {
    let status: String
    let response: DeleteResult
    
    struct DeleteResult: Decodable {
        let reassignedTaskCount: Int
        let success: Bool
    }
}
```

## Analytics Endpoints

### Dashboard Analytics
```swift
// GET /wf/dashboard-analytics
struct DashboardAnalyticsRequest {
    let companyId: String
    let userId: String
}

struct DashboardAnalyticsResponse: Decodable {
    let status: String
    let response: DashboardData
    
    struct DashboardData: Decodable {
        let projectsByStatus: [String: Int]
        let unscheduledCount: Int
        let unassignedCount: Int
        let todaysProjects: [ProjectDTO]
        let teamUtilization: [TeamMemberUtilization]
        let recentActivity: [ActivityItem]
        
        struct TeamMemberUtilization: Decodable {
            let memberId: String
            let memberName: String
            let assignedProjects: Int
            let tasksToday: Int
        }
        
        struct ActivityItem: Decodable {
            let type: String // "project_created", "status_changed", etc.
            let description: String
            let timestamp: String
            let userId: String
        }
    }
}
```

## Batch Operations

### Batch Reassign Projects
```swift
// POST /wf/batch-reassign-projects
struct BatchReassignRequest: Encodable {
    let project_ids_list: [String]
    let new_client_id_text: String
}

struct BatchReassignResponse: Decodable {
    let status: String
    let response: BatchResult
    
    struct BatchResult: Decodable {
        let successCount: Int
        let failedIds: [String]
    }
}
```

### Batch Update Calendar Events
```swift
// POST /wf/batch-update-calendar-events
struct BatchCalendarUpdateRequest: Encodable {
    let updates_list: [CalendarEventUpdate]
    
    struct CalendarEventUpdate: Encodable {
        let event_id_text: String
        let active_boolean: Bool?
        let start_date_date: String?
        let end_date_date: String?
    }
}
```

## Error Handling

### API Error Types
```swift
enum APIError: Error, LocalizedError {
    case invalidURL
    case requestFailed
    case decodingFailed
    case unauthorized
    case notFound
    case serverError(String)
    case rateLimited
    case networkError
    case deleteFailed
    case validationError(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .requestFailed:
            return "Request failed"
        case .decodingFailed:
            return "Failed to decode response"
        case .unauthorized:
            return "Unauthorized access"
        case .notFound:
            return "Resource not found"
        case .serverError(let message):
            return "Server error: \(message)"
        case .rateLimited:
            return "Too many requests. Please try again later"
        case .networkError:
            return "Network connection error"
        case .deleteFailed:
            return "Failed to delete resource"
        case .validationError(let message):
            return "Validation error: \(message)"
        }
    }
}
```

### Error Response Handling
```swift
struct ErrorResponse: Decodable {
    let status: String
    let message: String
    let code: String?
}

func handleAPIResponse(_ data: Data, _ response: URLResponse) throws {
    guard let httpResponse = response as? HTTPURLResponse else {
        throw APIError.requestFailed
    }
    
    switch httpResponse.statusCode {
    case 200...299:
        return // Success
    case 401:
        throw APIError.unauthorized
    case 404:
        throw APIError.notFound
    case 429:
        throw APIError.rateLimited
    case 500...599:
        if let error = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
            throw APIError.serverError(error.message)
        } else {
            throw APIError.serverError("Unknown server error")
        }
    default:
        throw APIError.requestFailed
    }
}
```