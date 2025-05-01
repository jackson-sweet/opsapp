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
    @State private var isSavingNotes = false
    @State private var notesSaved = false
    
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
                
                ZStack(alignment: .topTrailing) {
                    TextEditor(text: $noteText)
                        .frame(minHeight: 120)
                        .padding(8)
                        .background(OPSStyle.Colors.cardBackground)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    // Success indicator that appears briefly after saving
                    if notesSaved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.successStatus)
                            .font(.system(size: 24))
                            .padding(8)
                            .transition(.scale.combined(with: .opacity))
                            .onAppear {
                                // Hide after 2 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation {
                                        notesSaved = false
                                    }
                                }
                            }
                    }
                }
                
                // Save notes button
                Button(action: saveNotes) {
                    HStack {
                        if isSavingNotes {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryText))
                                .padding(.trailing, 8)
                        }
                        
                        Text("SAVE NOTES")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.secondaryAccent)
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
                    .opacity(isSavingNotes ? 0.7 : 1.0)
                }
                .disabled(isSavingNotes)
                .padding(.vertical)
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Photos section
                ProjectImagesSection(project: project)
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
        guard !isSavingNotes else { return }
        
        isSavingNotes = true
        
        Task {
            // Update the model
            await MainActor.run {
                project.notes = noteText
                project.needsSync = true
                
                // Save to the database
                if let modelContext = dataController.modelContext {
                    try? modelContext.save()
                }
            }
            
            // Sync will happen automatically via the normal sync mechanism
            // This is simpler and more reliable than duplicating sync logic here
            
            // Show success indicator
            await MainActor.run {
                withAnimation {
                    notesSaved = true
                    isSavingNotes = false
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
