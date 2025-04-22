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
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        NavigationView {
            VStack {
                Text("OPS")
                    .font(.largeTitle)
                    .padding()
                
                Text("Your projects will appear here.")
                    .padding()
                
                // This will be replaced with your actual UI
                Text("Loading...")
                    .padding()
            }
            .onAppear {
                // Load projects when view appears
                viewModel.loadProjects(context: modelContext)
            }
        }
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
}
