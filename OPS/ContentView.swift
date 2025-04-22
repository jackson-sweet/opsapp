//
//  ContentView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//
import SwiftUI
import SwiftData

/// Main content view - temporary placeholder until you build your UI
struct ContentView: View {
    @EnvironmentObject private var viewModel: ProjectsViewModel
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        Group {
            if dataController.isAuthenticated {
                mainView
            } else {
                loginView
            }
        }
    }
    
    // Main authenticated view
    private var mainView: some View {
        NavigationView {
            VStack {
                Text("OPS")
                    .font(.largeTitle)
                    .padding()
                
                if viewModel.isLoading {
                    ProgressView("Loading projects...")
                        .padding()
                } else if let error = viewModel.error {
                    Text("Error: \(error)")
                        .foregroundColor(.red)
                        .padding()
                } else if viewModel.projects.isEmpty {
                    Text("No projects found. Projects will appear here once assigned.")
                        .padding()
                } else {
                    List {
                        ForEach(viewModel.projects) { project in
                            ProjectRow(project: project)
                        }
                    }
                }
                
                Spacer()
                
                Button("Refresh") {
                    viewModel.loadProjects(context: modelContext)
                }
                .padding()
            }
            .onAppear {
                // Load projects when view appears
                viewModel.loadProjects(context: modelContext)
            }
        }
    }
    
    // Login view for authentication
    private var loginView: some View {
        VStack {
            Text("OPS")
                .font(.largeTitle)
                .padding()
            
            Text("Please sign in to continue")
                .padding()
            
            // In a real app, we would add text fields for username/password
            // and a login button that calls dataController.login()
            
            Button("Login (Placeholder)") {
                // This would call the real login method in production
                Task {
                    let _ = await dataController.login(username: "demo", password: "password")
                }
            }
            .padding()
        }
    }
}

// Simple row view for a project
struct ProjectRow: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(project.title)
                .font(.headline)
            
            Text(project.address)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text("Status:")
                Text(project.status.displayName)
                    .foregroundColor(project.statusColor)
            }
            
            if let startDate = project.startDate {
                Text("Start: \(startDate, formatter: dateFormatter)")
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
    
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Project.self, inMemory: true)
        .environmentObject(ProjectsViewModel(syncManager: SyncManager(
            modelContext: ModelContext(try! ModelContainer(for: Project.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))),
            apiService: APIService(authManager: AuthManager()),
            connectivityMonitor: ConnectivityMonitor()
        )))
        .environmentObject(DataController())
}
