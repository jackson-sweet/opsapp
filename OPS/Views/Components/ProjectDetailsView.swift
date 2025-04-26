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
                
                // Client and address
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("CLIENT") {
                        Text(project.clientName)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    LabeledContent("ADDRESS") {
                        Text(project.address)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    
                    LabeledContent("SCHEDULED") {
                        Text(project.formattedStartDate)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                .labeledContentStyle(DarkLabeledContentStyle())
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Project details section
                Text("PROJECT DETAILS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.projectDescription ?? "No detailed description provided.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Notes section
                Text("NOTES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                TextEditor(text: $noteText)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .font(OPSStyle.Typography.body)
                
                // Save notes button
                Button(action: saveNotes) {
                    Text("SAVE NOTES")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OPSStyle.Colors.secondaryAccent)
                        .foregroundColor(.white)
                        .cornerRadius(OPSStyle.Layout.buttonRadius)
                }
                .padding(.vertical)
                
                // Photos section - placeholder for now
                Text("PHOTOS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text("No photos added yet")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(24)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
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
    }
    
    private func saveNotes() {
        // This would typically update the database through DataController
        // For now, let's just print the notes
        print("Saving notes: \(noteText)")
        // We would call a method on DataController to update project notes
    }
}

// Custom labeled content style for consistent field labels
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