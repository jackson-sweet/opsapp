//
//  DataController.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData
import Combine

/// Main Data Controller
/// The single source of truth for data access in the app
@MainActor // Mark the entire class as running on the main actor
class DataController: ObservableObject {
    // Dependencies - all properly isolated to the main thread
    private let modelContainer: ModelContainer
    private let syncManager: SyncManager
    private let apiService: APIService
    private let authManager: AuthManager
    private let connectivityMonitor: ConnectivityMonitor
    
    // State
    @Published var isInitialized = false
    @Published var isAuthenticated = false
    @Published var isSyncing = false
    
    // Current user
    @Published private(set) var currentUser: User?
    
    init() {
        // Setup dependencies
        do {
            // 1. Set up SwiftData
            let schema = Schema([
                User.self,
                Project.self,
                Company.self
            ])
            
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // 2. Set up other services
            let keychain = KeychainManager()
            let authManager = AuthManager()
            self.authManager = authManager
            
            let apiService = APIService(authManager: authManager)
            self.apiService = apiService
            
            self.connectivityMonitor = ConnectivityMonitor()
            
            // 3. Initialize sync manager with the main context
            let modelContext = ModelContext(modelContainer)
            let syncManager = SyncManager(
                modelContext: modelContext,
                apiService: apiService,
                connectivityMonitor: connectivityMonitor
            )
            self.syncManager = syncManager
            
            // 4. Check for existing login
            checkExistingAuth()
        } catch {
            fatalError("Failed to initialize data controller: \(error)")
        }
    }
    
    // MARK: - Authentication
    
    private func checkExistingAuth() {
        Task {
            do {
                // Try to get a valid token
                _ = try await authManager.getValidToken()
                
                // If we get here, we have valid credentials
                await MainActor.run {
                    self.isAuthenticated = true
                    self.loadCurrentUser()
                }
            } catch {
                // Not authenticated
                await MainActor.run {
                    self.isAuthenticated = false
                }
            }
        }
    }
    
    func login(username: String, password: String) async -> Bool {
        do {
            // Attempt to sign in
            _ = try await authManager.signIn(username: username, password: password)
            
            // Success
            self.isAuthenticated = true
            self.loadCurrentUser()
            
            return true
        } catch {
            print("Login failed: \(error)")
            return false
        }
    }
    
    func logout() {
        authManager.signOut()
        isAuthenticated = false
        currentUser = nil
    }
    
    // MARK: - User Management
    
    private func loadCurrentUser() {
        Task {
            do {
                // Get current user ID from auth manager
                guard let currentUserId = authManager.getUserId() else {
                    // No current user ID available
                    return
                }
                
                // Try to fetch from local database first
                let predicate = #Predicate<User> { $0.id == currentUserId }
                let descriptor = FetchDescriptor<User>(predicate: predicate)
                let localUsers = try modelContainer.mainContext.fetch(descriptor)
                
                if let localUser = localUsers.first {
                    await MainActor.run {
                        self.currentUser = localUser
                        self.isInitialized = true
                    }
                } else {
                    // Fetch from API if not found locally
                    let remoteUser = try await apiService.fetchUser(id: currentUserId)
                    let newUser = remoteUser.toModel()
                    
                    await MainActor.run {
                        self.modelContainer.mainContext.insert(newUser)
                        try? self.modelContainer.mainContext.save()
                        self.currentUser = newUser
                        self.isInitialized = true
                    }
                }
                
                // Store company ID for sync
                if let companyId = currentUser?.companyId {
                    UserDefaults.standard.set(companyId, forKey: "currentUserCompanyId")
                }
                
                // Trigger initial sync
                await syncManager.performFullSync()
                
            } catch {
                print("Failed to load current user: \(error)")
            }
        }
    }
    
    func updateUserProfile(firstName: String, lastName: String, email: String?) {
        guard var user = currentUser else { return }
        
        user.firstName = firstName
        user.lastName = lastName
        user.email = email
        user.needsSync = true
        
        do {
            try modelContainer.mainContext.save()
        } catch {
            print("Failed to update user profile: \(error)")
        }
    }
    
    func updateUserProfileImage(_ imageData: Data?) {
        guard var user = currentUser else { return }
        
        user.profileImageData = imageData
        user.needsSync = true
        
        do {
            try modelContainer.mainContext.save()
        } catch {
            print("Failed to update profile image: \(error)")
        }
    }
    
    // MARK: - Project Management
    
    // Get projects for map view - the heart of the field crew experience
    func getProjectsForMap() -> [Project] {
        do {
            // For MVP, just show all projects assigned to current user
            guard let userId = currentUser?.id else { return [] }
            
            let predicate = #Predicate<Project> { project in
                project.teamMembers?.contains(where: { $0.id == userId }) == true
            }
            
            let descriptor = FetchDescriptor<Project>(predicate: predicate)
            return try modelContainer.mainContext.fetch(descriptor)
        } catch {
            print("Failed to fetch projects for map: \(error)")
            return []
        }
    }
    
    // Get projects for calendar view
    func getProjectsForCalendar(month: Int, year: Int) -> [Project] {
        do {
            // Get start and end date for the month
            let calendar = Calendar.current
            var dateComponents = DateComponents()
            dateComponents.year = year
            dateComponents.month = month
            dateComponents.day = 1
            
            guard let startDate = calendar.date(from: dateComponents),
                  let endDate = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: startDate) else {
                return []
            }
            
            // Fetch projects for current user in this date range
            guard let userId = currentUser?.id else { return [] }
            
            let predicate = #Predicate<Project> { project in
                project.teamMembers?.contains(where: { $0.id == userId }) == true &&
                ((project.startDate != nil && project.startDate! <= endDate) &&
                (project.endDate == nil || project.endDate! >= startDate))
            }
            
            let descriptor = FetchDescriptor<Project>(predicate: predicate)
            return try modelContainer.mainContext.fetch(descriptor)
        } catch {
            print("Failed to fetch projects for calendar: \(error)")
            return []
        }
    }
    
    // Get project by ID
    func getProject(id: String) -> Project? {
        do {
            let predicate = #Predicate<Project> { $0.id == id }
            let descriptor = FetchDescriptor<Project>(predicate: predicate)
            let projects = try modelContainer.mainContext.fetch(descriptor)
            return projects.first
        } catch {
            print("Failed to fetch project: \(error)")
            return nil
        }
    }
    
    // Update project status - key action for field crew
    func updateProjectStatus(projectId: String, status: Status) {
        guard let project = getProject(id: projectId) else { return }
        
        project.status = status
        project.needsSync = true
        project.syncPriority = 3 // Highest priority
        
        // If moving to in progress, record the start time if not already set
        if status == .inProgress && project.startDate == nil {
            project.startDate = Date()
        }
        
        // If moving to completed, record the end time
        if status == .completed && project.endDate == nil {
            project.endDate = Date()
        }
        
        do {
            try modelContainer.mainContext.save()
            
            // Try to sync the change immediately if online
            if connectivityMonitor.isConnected {
                Task {
                    syncManager.triggerBackgroundSync()
                }
            }
        } catch {
            print("Failed to update project status: \(error)")
        }
    }
    
    // MARK: - Company Management
    
    // Get company by ID
    func getCompany(id: String) -> Company? {
        do {
            let predicate = #Predicate<Company> { $0.id == id }
            let descriptor = FetchDescriptor<Company>(predicate: predicate)
            let companies = try modelContainer.mainContext.fetch(descriptor)
            return companies.first
        } catch {
            print("Failed to fetch company: \(error)")
            return nil
        }
    }
    
    // Get current user's company
    func getCurrentUserCompany() -> Company? {
        guard let companyId = currentUser?.companyId else {
            return nil
        }
        
        return getCompany(id: companyId)
    }
    
    // MARK: - Team Management
    
    // Get team members for the current user's company
    func getTeamMembers() -> [User] {
        guard let companyId = currentUser?.companyId else {
            return []
        }
        
        do {
            let predicate = #Predicate<User> { $0.companyId == companyId }
            let descriptor = FetchDescriptor<User>(predicate: predicate)
            return try modelContainer.mainContext.fetch(descriptor)
        } catch {
            print("Failed to fetch team members: \(error)")
            return []
        }
    }
    
    // Get field crew members for the current user's company
    func getFieldCrewMembers() -> [User] {
        guard let companyId = currentUser?.companyId else {
            return []
        }
        
        do {
            let predicate = #Predicate<User> {
                $0.companyId == companyId && $0.role == .fieldCrew
            }
            let descriptor = FetchDescriptor<User>(predicate: predicate)
            return try modelContainer.mainContext.fetch(descriptor)
        } catch {
            print("Failed to fetch field crew members: \(error)")
            return []
        }
    }
    
    // MARK: - Sync Management
    
    // Trigger a manual sync - only used internally when needed
    func forceSync() {
        Task {
            guard !isSyncing else { return }
            
            await MainActor.run {
                isSyncing = true
            }
            
            await syncManager.performFullSync()
            
            await MainActor.run {
                isSyncing = false
            }
        }
    }
}
