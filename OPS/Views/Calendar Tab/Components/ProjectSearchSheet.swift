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
    
    // Filter states
    @State private var selectedStatus: Status? = nil
    @State private var selectedTeamMemberId: String? = nil
    @State private var teamMembers: [TeamMember] = []
    @State private var showFilters = false
    
    // Check if any filters are active
    private var hasActiveFilters: Bool {
        selectedStatus != nil || selectedTeamMemberId != nil
    }
    
    // Filtered projects based on search text and filters
    private var filteredProjects: [Project] {
        var projects = allProjects
        
        // Filter by status
        if let selectedStatus = selectedStatus {
            projects = projects.filter { $0.status == selectedStatus }
        }
        
        // Filter by team member
        if let selectedTeamMemberId = selectedTeamMemberId {
            projects = projects.filter { project in
                project.getTeamMemberIds().contains(selectedTeamMemberId)
            }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            projects = projects.filter { project in
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
        
        return projects
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
                    searchBarSection
                    filterSection
                    projectListSection
                }
            }
            .navigationTitle("SEARCH PROJECTS")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        dismiss()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 14, weight: .medium))
                            Text("CLOSE")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                
                ToolbarItem(placement: .principal) {
                    Text("SEARCH PROJECTS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
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
    
    // MARK: - View Components
    
    private var searchBarSection: some View {
        HStack(spacing: 0) {
            // Search field
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                TextField("Search projects, clients, or addresses...", text: $searchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled()
                    .focused($isSearchFieldFocused)
                
                if !searchText.isEmpty {
                    Button(action: {
                        searchText = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .frame(maxWidth: .infinity)
            
            Spacer(minLength: 8)
            
            // Filter button with label and icon
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFilters.toggle()
                }
            }) {
                HStack(spacing: 6) {
                    Text("FILTERS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    
                    Image(systemName: showFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                        .font(.system(size: 16))
                        .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                    
                    if hasActiveFilters {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 6, height: 6)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(showFilters ? OPSStyle.Colors.cardBackground : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(hasActiveFilters ? OPSStyle.Colors.primaryAccent.opacity(0.3) : Color.clear, lineWidth: 1)
                        )
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    
    private var filterSection: some View {
        Group {
            if showFilters {
                VStack(spacing: 16) {
                    statusFilterSection
                    if !teamMembers.isEmpty {
                        teamMemberFilterSection
                    }
                    
                    // Clear filters button if any filters are active
                    if hasActiveFilters {
                        Button(action: {
                            selectedStatus = nil
                            selectedTeamMemberId = nil
                        }) {
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 14))
                                
                                Text("CLEAR ALL FILTERS")
                                    .font(OPSStyle.Typography.captionBold)
                            }
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(OPSStyle.Colors.cardBackgroundDark)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 16)
                .background(OPSStyle.Colors.cardBackground.opacity(0.5))
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
            }
        }
    }
    
    private var statusFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "flag.fill")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("STATUS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Status dropdown
            Menu {
                Button(action: { selectedStatus = nil }) {
                    Label("All Statuses", systemImage: selectedStatus == nil ? "checkmark" : "")
                }
                
                Divider()
                
                ForEach([Status.inProgress, .accepted, .estimated, .rfq, .completed, .closed, .archived], id: \.self) { status in
                    Button(action: { 
                        selectedStatus = selectedStatus == status ? nil : status 
                    }) {
                        HStack {
                            Circle()
                                .fill(status.color)
                                .frame(width: 8, height: 8)
                            Text(status.displayName)
                            Spacer()
                            if selectedStatus == status {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    if let selectedStatus = selectedStatus {
                        Circle()
                            .fill(selectedStatus.color)
                            .frame(width: 8, height: 8)
                    }
                    
                    Text(selectedStatus?.displayName ?? "All Statuses")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
        }
    }
    
    @ViewBuilder
    private var teamMemberFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text("TEAM MEMBER")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
            }
            .padding(.horizontal)
            
            // Team member dropdown
            Menu {
                Button(action: { selectedTeamMemberId = nil }) {
                    Label("All Team Members", systemImage: selectedTeamMemberId == nil ? "checkmark" : "")
                }
                
                Divider()
                
                ForEach(teamMembers, id: \.id) { member in
                    Button(action: { 
                        selectedTeamMemberId = selectedTeamMemberId == member.id ? nil : member.id 
                    }) {
                        HStack {
                            Text(member.fullName)
                            Spacer()
                            if selectedTeamMemberId == member.id {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Image(systemName: "person.fill")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(teamMembers.first(where: { $0.id == selectedTeamMemberId })?.fullName ?? "All Team Members")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
            }
            .padding(.horizontal)
        }
    }
    
    
    private var projectListSection: some View {
        Group {
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
    
    private func loadProjects() {
        isLoading = true
        
        Task {
            // First, sync team members to ensure we have the latest data
            if let companyId = dataController.currentUser?.companyId,
               let company = dataController.getCompany(id: companyId) {
                await dataController.syncManager?.syncCompanyTeamMembers(company)
            }
            
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
                
                // Load current team members from company
                // This ensures we only show active team members, not old ones stored in projects
                if let companyId = currentUser.companyId {
                    // Get fresh team members from the company
                    let users = dataController.getTeamMembers(companyId: companyId)
                    
                    // Convert Users to TeamMembers for the filter
                    teamMembers = users.map { user in
                        TeamMember(
                            id: user.id,
                            firstName: user.firstName,
                            lastName: user.lastName ?? "",
                            role: user.role.rawValue.capitalized,
                            avatarURL: user.profileImageURL,
                            email: user.email,
                            phone: user.phone
                        )
                    }.sorted { member1, member2 in
                        member1.fullName < member2.fullName
                    }
                } else {
                    // No company, no team members
                    teamMembers = []
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
            HStack(spacing: 0) {
                // Status color bar on the left
                Rectangle()
                    .fill(project.status.color)
                    .frame(width: 4)
                
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        // Project title
                        Text(project.title.uppercased())
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        
                        // Client name
                        if !project.clientName.isEmpty {
                            Text(project.clientName)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        
                        // Date and address info
                        HStack(spacing: 8) {
                            if let startDate = project.startDate {
                                HStack(spacing: 4) {
                                    Image(systemName: "calendar")
                                        .font(.system(size: 10))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    
                                    Text(formatDate(startDate))
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                            }
                            
                            if !project.address.isEmpty {
                                HStack(spacing: 4) {
                                    Image(systemName: "location")
                                        .font(.system(size: 10))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                    
                                    Text(project.address)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Chevron
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal)
        }
    }
}

// Filter chip component
struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isSelected {
                    Circle()
                        .fill(color)
                        .frame(width: 6, height: 6)
                }
                
                Text(title)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(isSelected ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.cardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(isSelected ? color.opacity(0.3) : Color.clear, lineWidth: 1)
            )
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