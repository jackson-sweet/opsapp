//
//  TaskTypeDetailSheet.swift
//  OPS
//
//  Created by Assistant on 2025-09-26.
//

import SwiftUI

struct TaskTypeDetailSheet: View {
    let taskType: TaskType
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var showingEditForm = false
    @State private var showingDeletionSheet = false

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        // Task Type Info Card
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            HStack {
                                Image(systemName: taskType.icon ?? "checklist")
                                    .font(.system(size: 24))
                                    .foregroundColor(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(taskType.display)
                                        .font(OPSStyle.Typography.title)
                                        .foregroundColor(OPSStyle.Colors.primaryText)

                                    Text(taskType.isDefault ? "Default Task Type" : "Custom Task Type")
                                        .font(OPSStyle.Typography.caption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }

                                Spacer()
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }

                        // Properties
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("PROPERTIES")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                PropertyRow(
                                    label: "Name",
                                    value: taskType.display
                                )

                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                                PropertyRow(
                                    label: "Icon",
                                    value: taskType.icon ?? "checklist"
                                )

                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                                HStack {
                                    Text("COLOR")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)

                                    Spacer()

                                    Circle()
                                        .fill(Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent)
                                        .frame(width: 24, height: 24)
                                }
                                .padding(OPSStyle.Layout.spacing3)

                                Divider()
                                    .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                                PropertyRow(
                                    label: "Type",
                                    value: taskType.isDefault ? "System Default" : "User Created"
                                )
                            }
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }

                        // Usage Stats (placeholder)
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("USAGE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: OPSStyle.Layout.spacing3) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Used in Projects")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("0")
                                            .font(OPSStyle.Typography.title)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text("Total Tasks")
                                            .font(OPSStyle.Typography.caption)
                                            .foregroundColor(OPSStyle.Colors.secondaryText)
                                        Text("0")
                                            .font(OPSStyle.Typography.title)
                                            .foregroundColor(OPSStyle.Colors.primaryText)
                                    }
                                }
                            }
                            .padding(OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                        }

                        if !taskType.isDefault {
                            // Edit/Delete buttons for custom task types
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                Button(action: {
                                    showingEditForm = true
                                }) {
                                    HStack {
                                        Image(systemName: OPSStyle.Icons.pencil)
                                            .font(.system(size: 16))
                                        Text("EDIT TASK TYPE")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .frame(maxWidth: .infinity)
                                    .padding(OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.primaryAccent)
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                }

                                Button(action: {
                                    showingDeletionSheet = true
                                }) {
                                    HStack {
                                        Image(systemName: OPSStyle.Icons.trash)
                                            .font(.system(size: 16))
                                        Text("DELETE TASK TYPE")
                                            .font(OPSStyle.Typography.bodyBold)
                                    }
                                    .foregroundColor(OPSStyle.Colors.errorStatus)
                                    .frame(maxWidth: .infinity)
                                    .padding(OPSStyle.Layout.spacing3)
                                    .background(OPSStyle.Colors.errorStatus.opacity(0.1))
                                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                            .stroke(OPSStyle.Colors.errorStatus.opacity(0.3), lineWidth: 1)
                                    )
                                }
                            }
                            .padding(.top, OPSStyle.Layout.spacing3)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .navigationTitle(taskType.display.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .sheet(isPresented: $showingEditForm) {
            TaskTypeEditSheet(taskType: taskType) {
                showingEditForm = false
            }
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showingDeletionSheet) {
            TaskTypeDeletionSheet(taskType: taskType)
                .environmentObject(dataController)
        }
    }
}

struct PropertyRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(OPSStyle.Layout.spacing3)
    }
}