//
//  ExpandableNotesView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct ExpandableNotesView: View {
    let notes: String
    @State private var isExpanded = false
    @State private var isEditing = false
    @Binding var editedNotes: String
    let onSave: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header with expand/collapse button
            HStack {
                Text("NOTES")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Spacer()
                
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.toggle()
                    }
                }) {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            if isEditing {
                // Editable notes
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 120)
                    .padding(8)
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .onChange(of: editedNotes) { _, newValue in
                        // Auto-save draft notes if needed
                        UserDefaults.standard.set(newValue, forKey: "draft_notes_temp")
                    }
                
                HStack {
                    Spacer()
                    
                    // Cancel button
                    Button(action: {
                        isEditing = false
                        // Reset to original notes
                        editedNotes = notes
                    }) {
                        Text("CANCEL")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Save button
                    Button(action: {
                        isEditing = false
                        onSave()
                    }) {
                        Text("SAVE")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.secondaryAccent)
                            .foregroundColor(.white)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            } else {
                // Notes display (single line or expanded)
                if notes.isEmpty {
                    // Empty state
                    HStack {
                        Text("No notes added yet")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
                            .padding(.vertical, 8)
                        
                        Spacer()
                        
                        Button(action: {
                            isEditing = true
                            isExpanded = true
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16))
                                .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        }
                    }
                } else {
                    // Notes content
                    VStack(alignment: .leading, spacing: 8) {
                        if isExpanded {
                            // Full text
                            Text(notes)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 4)
                            
                            // Edit button
                            HStack {
                                Spacer()
                                
                                Button(action: {
                                    isEditing = true
                                }) {
                                    Text("EDIT")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(OPSStyle.Colors.secondaryAccent)
                                        .foregroundColor(.white)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }
                            }
                        } else {
                            // Single line with truncation
                            HStack {
                                Text(notes)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                
                                Spacer()
                                
                                Button(action: {
                                    isEditing = true
                                    isExpanded = true
                                }) {
                                    Image(systemName: "square.and.pencil")
                                        .font(.system(size: 16))
                                        .foregroundColor(OPSStyle.Colors.secondaryAccent)
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding()
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}