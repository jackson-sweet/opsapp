//
//  ProjectDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-25.
//

import SwiftUI

struct ProjectDetailsView: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @State private var noteText: String
    @EnvironmentObject private var dataController: DataController
    @State private var showingPhotos = false
    
    // Initialize with project's existing notes
    init(project: Project) {
        self.project = project
        self._noteText = State(initialValue: project.notes ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status badge
                StatusBadge(status: project.status)
                    .padding(.top, 4)
                
                // Project title
                Text(project.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                // Client info
                clientInfoSection
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Project description
                Text("PROJECT DETAILS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.projectDescription ?? "No detailed description provided.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Notes section
                notesSection
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Photos button - simpler approach
                Text("PHOTOS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Button(action: {
                    showingPhotos = true
                }) {
                    HStack {
                        Image(systemName: "photo")
                            .font(.system(size: 20))
                        
                        Text("View Project Photos")
                            .font(OPSStyle.Typography.body)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.primaryAccent)
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
            }
            .padding()
        }
        .background(OPSStyle.Colors.background.edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(OPSStyle.Colors.secondaryAccent)
            }
        }
        .sheet(isPresented: $showingPhotos) {
            ProjectPhotosGrid(project: project)
        }
    }
    
    // Client info section
    private var clientInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIENT: \(project.clientName)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text("ADDRESS: \(project.address)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text("SCHEDULED: \(project.formattedStartDate)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }
    
    // Notes section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .padding(8)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Button(action: saveNotes) {
                Text("SAVE NOTES")
                    .font(OPSStyle.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.secondaryAccent)
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
        }
    }
    
    private func saveNotes() {
        project.notes = noteText
        project.needsSync = true
        
        if let modelContext = dataController.modelContext {
            try? modelContext.save()
        }
    }
}

// Separate view for photos to avoid loading images in main view
struct ProjectPhotosSheet: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            VStack {
                List {
                    ForEach(project.getProjectImages(), id: \.self) { urlString in
                        HStack {
                            Text("Project Photo")
                                .font(OPSStyle.Typography.body)
                            
                            Spacer()
                            
                            Image(systemName: "photo")
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            // We'll implement this in a separate step
                        }
                    }
                    
                    if project.getProjectImages().isEmpty {
                        Text("No photos added yet")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding()
                    }
                }
            }
            .navigationTitle("Project Photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DarkLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            configuration.content
                .font(OPSStyle.Typography.body)
        }
    }
}
