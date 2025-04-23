//
//  HomeView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// HomeView.swift
import SwiftUI
import MapKit

struct HomeView: View {
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @State private var projects = [Project]()
    @State private var isLoading = true
    @State private var hasError = false
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 37.33233141, longitude: -122.03121860),
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    
    var body: some View {
        ZStack {
            // Map background - We'll implement the custom MapView later
            Color.black.opacity(0.9) // Placeholder for map
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                if !appState.isInProjectMode {
                    userHeader
                } else if let activeProject = projects.first(where: { $0.id == appState.activeProjectID }) {
                    projectHeader(for: activeProject)
                }
                
                Spacer()
                
                // Project cards or active project UI
                if !appState.isInProjectMode {
                    projectCards
                } else if let activeProject = projects.first(where: { $0.id == appState.activeProjectID }) {
                    // Project mode actions - We'll implement this later
                    VStack {
                        Text("Project Actions")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            
                        HStack(spacing: OPSStyle.Layout.spacing4) {
                            Button(action: {
                                // Update status
                            }) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Notes
                            }) {
                                Image(systemName: "doc.text.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Pencil/edit
                            }) {
                                Image(systemName: "pencil")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                            
                            Button(action: {
                                // Camera
                            }) {
                                Image(systemName: "camera.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(width: 56, height: 56)
                                    .background(Circle().fill(OPSStyle.Colors.primaryAccent))
                            }
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing4)
                        .padding(.horizontal)
                        .background(OPSStyle.Colors.background.opacity(0.7))
                    }
                }
            }
            
            // Loading/error overlays
            if isLoading {
                VStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                    Text("Loading projects...")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding()
                }
                .frame(width: 200, height: 150)
                .background(OPSStyle.Colors.cardBackground.opacity(0.9))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            } else if hasError {
                VStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .font(.system(size: 40))
                        .padding(.bottom)
                    
                    Text("Unable to load projects")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Button("Retry") {
                        loadProjects()
                    }
                    .padding(.top)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                .padding()
                .frame(width: 250, height: 200)
                .background(OPSStyle.Colors.cardBackground.opacity(0.9))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .onAppear {
            loadProjects()
        }
    }
    
    // MARK: - Components
    
    private var userHeader: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Good Morning, \(dataController.currentUser?.firstName ?? "User")")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let company = dataController.getCurrentUserCompany() {
                    Text(company.name.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            // User profile image
            if let imageData = dataController.currentUser?.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(dataController.currentUser?.firstName.prefix(1) ?? "U")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    )
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
    
    private func projectHeader(for project: Project) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(project.status.rawValue.uppercased())
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                Text("\(project.clientName), \(project.title)")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
            
            Button(action: {
                appState.exitProjectMode()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
    
    private var projectCards: some View {
        ScrollView {
            VStack(spacing: OPSStyle.Layout.spacing3) {
                ForEach(projects) { project in
                    projectCard(for: project)
                }
            }
            .padding()
        }
        .background(OPSStyle.Colors.background.opacity(0.2))
    }
    
    private func projectCard(for project: Project) -> some View {
        Button(action: {
            appState.enterProjectMode(projectID: project.id)
        }) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                HStack {
                    Text(project.status.rawValue.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .fontWeight(.bold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .padding(.horizontal, OPSStyle.Layout.spacing2)
                        .padding(.vertical, OPSStyle.Layout.spacing1)
                        .background(OPSStyle.Colors.statusColor(for: project.status))
                        .cornerRadius(OPSStyle.Layout.cornerRadius / 2)
                    
                    Spacer()
                    
                    if let startDate = project.startDate {
                        Text(formattedDate(startDate))
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Text(project.title)
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
                
                Text(project.clientName)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.address)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
            .padding(OPSStyle.Layout.contentPadding)
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - Helper Methods
    
    private func loadProjects() {
        isLoading = true
        hasError = false
        
        // Simulate loading projects for now
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                self.projects = try dataController.getProjectsForMap()
                self.isLoading = false
            } catch {
                self.hasError = true
                self.isLoading = false
            }
        }
    }
    
    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}