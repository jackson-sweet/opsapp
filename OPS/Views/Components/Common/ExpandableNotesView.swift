//
//  ExpandableNotesView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI

struct ExpandableNotesView: View {
    let notes: String
    @Binding var isExpanded: Bool
    @State private var isEditing = false
    @Binding var editedNotes: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditing {
                // Editable notes
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 120)
                    .padding(12)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.6))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.9))
                    .scrollContentBackground(.hidden)
                    .onChange(of: editedNotes) { _, newValue in
                        // Auto-save draft notes if needed
                        UserDefaults.standard.set(newValue, forKey: "draft_notes_temp")
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                
                HStack {
                    Spacer()
                    
                    // Cancel button
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = false
                        }
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
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isEditing = false
                        }
                        onSave()
                    }) {
                        Text("SAVE")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(OPSStyle.Colors.primaryAccent)
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
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isEditing = true
                                isExpanded = true
                            }
                        }) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 16))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
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
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        isEditing = true
                                    }
                                }) {
                                    Text("EDIT")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 6)
                                        .background(OPSStyle.Colors.primaryAccent)
                                        .foregroundColor(.white)
                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }
                            }
                        } else {
                            // Single line with truncation and gradient
                            ZStack(alignment: .bottomLeading) {
                                Text(notes)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineLimit(3)
                                    .padding(.bottom, 24)

                                LinearGradient(
                                    gradient: Gradient(colors: [
                                        OPSStyle.Colors.cardBackgroundDark.opacity(0),
                                        OPSStyle.Colors.cardBackgroundDark
                                    ]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                                .frame(height: 40)
                                .frame(maxWidth: .infinity)

                                HStack {
                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isExpanded = true
                                        }
                                    }) {
                                        Text("Show more...")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }

                                    Spacer()

                                    Button(action: {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            isEditing = true
                                            isExpanded = true
                                        }
                                    }) {
                                        Image(systemName: "square.and.pencil")
                                            .font(.system(size: 24))
                                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isEditing)
    }
}
