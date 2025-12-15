//
//  ProjectMarkerPopup.swift
//  OPS
//
//  Small popup that appears below project markers when tapped during active project

import SwiftUI
import MapKit

struct ProjectMarkerPopup: View {
    let project: Project
    let task: ProjectTask?
    let isActiveProject: Bool
    let onDismiss: () -> Void

    @EnvironmentObject private var appState: AppState

    /// Extract just street number and name from full address
    private var streetAddress: String {
        guard let address = project.address else { return "No address" }
        let components = address.split(separator: ",")
        return components.first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? address
    }

    /// Task type display text
    private var taskTypeText: String? {
        task?.taskType?.display
    }

    /// Task color
    private var taskColor: Color {
        if let task = task, let color = Color(hex: task.effectiveColor) {
            return color
        }
        return OPSStyle.Colors.tertiaryText
    }

    var body: some View {
        VStack(spacing: 0) {
            // Arrow pointing up to marker
            Triangle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(width: 14, height: 7)
                .offset(y: 1)

            // Content card
            VStack(alignment: .leading, spacing: 12) {

                // Project title
                Text(project.title)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                // Client and address
                VStack(alignment: .leading, spacing: 4) {
                    Text(project.effectiveClientName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)

                    Text(streetAddress)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }

                // Badges row
                HStack(spacing: 8) {
                    // Status badge
                    Text(project.status.displayName.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(project.status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(project.status.color.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(project.status.color, lineWidth: 1)
                        )

                    // Task type badge
                    if let taskType = taskTypeText {
                        Text(taskType.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(taskColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(taskColor.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(taskColor, lineWidth: 1)
                            )
                    }

                    Spacer()
                }

                // Action button
                if isActiveProject {
                    HStack {
                        Spacer()
                        Text("CURRENT PROJECT")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                        Spacer()
                    }
                } else {
                    Button(action: {
                        if let task = task {
                            appState.viewTaskDetails(task: task, project: project)
                        } else {
                            appState.viewProjectDetails(project)
                        }
                        onDismiss()
                    }) {
                        HStack {
                            Spacer()
                            Text("VIEW DETAILS")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: 1)
                        )
                    }
                }
            }
            .padding(14)
            .frame(width: 240)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(8)
        }
        .contentShape(Rectangle())
        .onTapGesture { }
        .allowsHitTesting(true)
    }
}

// Triangle shape for arrow
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
