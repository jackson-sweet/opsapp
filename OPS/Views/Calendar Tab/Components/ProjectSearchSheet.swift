//
//  ProjectSearchSheet.swift
//  OPS
//
//  Search sheet for finding projects with role-based filtering
//

import SwiftUI
import SwiftData

struct ProjectSearchSheet: View {
    let dataController: DataController
    let onProjectSelected: (Project) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var allProjects: [Project] = []
    @State private var isLoading = true
    @FocusState private var isSearchFieldFocused: Bool
    
    // Filtered projects based on search text
    private var filteredProjects: [Project] {
        if searchText.isEmpty {
            return allProjects
        }
        
        return allProjects.filter { project in
            // Search in project title
            if project.title.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Search in client name
            if project.clientName.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Search in address
            if project.address.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            // Search in status
            if project.status.displayName.localizedCaseInsensitiveContains(searchText) {
                return true
            }
            
            return false
        }
    }
    
    // Group projects by status
    private var groupedProjects: [(Status, [Project])] {
        let grouped = Dictionary(grouping: filteredProjects) { $0.status }
        
        // Define the order of statuses
        let statusOrder: [Status] = [.inProgress, .accepted, .estimated, .rfq, .completed, .closed, .archived]
        
        return statusOrder.compactMap { status in
            guard let projects = grouped[status], !projects.isEmpty else { return nil }
            // Sort projects within each status by date (most recent first)
            let sortedProjects = projects.sorted { 
                ($0.startDate ?? Date.distantPast) > ($1.startDate ?? Date.distantPast)
            }
            return (status, sortedProjects)
        }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                // Background
                OPSStyle.Colors.background.ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Search bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        TextField("Search projects...", text: $searchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocorrectionDisabled()
                            .focused($isSearchFieldFocused)
                        
                        if !searchText.isEmpty {
                            Button(action: {
                                searchText = ""
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }
                        }
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    
                    if isLoading {
                        Spacer()
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(1.5)
                        Spacer()
                    } else if filteredProjects.isEmpty {
                        Spacer()
                        VStack(spacing: 16) {
                            Image(systemName: searchText.isEmpty ? "folder" : "magnifyingglass")
                                .font(OPSStyle.Typography.largeTitle)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text(searchText.isEmpty ? "No projects available" : "No projects found")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            if !searchText.isEmpty {
                                Text("Try adjusting your search terms")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                        Spacer()
                    } else {
                        // Project list grouped by status
                        ScrollView {
                            VStack(spacing: 24) {
                                ForEach(groupedProjects, id: \.0) { status, projects in
                                    VStack(alignment: .leading, spacing: 12) {
                                        // Status header
                                        HStack {
                                            Circle()
                                                .fill(status.color)
                                                .frame(width: 8, height: 8)
                                            
                                            Text(status.displayName.uppercased())
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                            
                                            Text("(\(projects.count))")
                                                .font(OPSStyle.Typography.caption)
                                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            
                                            Spacer()
                                        }
                                        .padding(.horizontal)
                                        
                                        // Projects in this status
                                        ForEach(projects) { project in
                                            ProjectSearchRow(project: project) {
                                                onProjectSelected(project)
                                                dismiss()
                                            }
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle("Search Projects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onAppear {
            loadProjects()
            // Auto-focus the search field with a small delay to ensure the view is fully loaded
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isSearchFieldFocused = true
            }
        }
    }
    
    private func loadProjects() {
        isLoading = true
        
        Task {
            await MainActor.run {
                // Get projects based on user role
                guard let currentUser = dataController.currentUser else {
                    allProjects = []
                    isLoading = false
                    return
                }
                
                // Get all projects
                let projects = dataController.getAllProjects()
                
                // Filter based on user role
                if currentUser.role == .fieldCrew {
                    // Field crew can only see projects they're assigned to
                    allProjects = projects.filter { project in
                        project.getTeamMemberIds().contains(currentUser.id)
                    }
                } else {
                    // Admin and office crew can see all projects
                    allProjects = projects
                }
                
                isLoading = false
            }
        }
    }
}

// Project row component
struct ProjectSearchRow: View {
    let project: Project
    let onTap: () -> Void
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
    }
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Status indicator
                Circle()
                    .fill(project.status.color)
                    .frame(width: 10, height: 10)
                
                VStack(alignment: .leading, spacing: 4) {
                    // Project title
                    Text(project.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    
                    // Client and date info
                    HStack(spacing: 8) {
                        if !project.clientName.isEmpty {
                            Text(project.clientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        
                        if let startDate = project.startDate {
                            Text("•")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            
                            Text(formatDate(startDate))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                    
                    // Address if available
                    if !project.address.isEmpty {
                        Text(project.address)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding()
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(12)
            .padding(.horizontal)
        }
    }
}

// Preview
struct ProjectSearchSheet_Previews: PreviewProvider {
    static var previews: some View {
        ProjectSearchSheet(
            dataController: DataController(),
            onProjectSelected: { _ in }
        )
        .preferredColorScheme(.dark)
    }
}