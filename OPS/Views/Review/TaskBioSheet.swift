//
//  TaskBioSheet.swift
//  OPS
//
//  Expanded detail view shown when tapping a task review card.
//  Displays task info, project context, schedule, team, and notes.
//

import SwiftUI
import SwiftData

struct TaskBioSheet: View {
    let task: ProjectTask
    let onDismiss: () -> Void

    @Query private var allUsers: [User]
    @State private var resolvedMembers: [User] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                    photoCarousel

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3_5) {
                        headerSection
                        divider
                        projectInfoSection
                        divider
                        scheduleSection
                        divider
                        teamSection

                        if let notes = task.taskNotes, !notes.isEmpty {
                            divider
                            notesSection(notes)
                        }

                        divider
                        fullDetailsButton
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
            }
            .background(OPSStyle.Colors.background)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text("TASK DETAILS")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .toolbarBackground(OPSStyle.Colors.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear { resolveTeamMembers() }
        }
    }

    private func resolveTeamMembers() {
        let ids = task.getTeamMemberIds()
        if !ids.isEmpty && task.teamMembers.isEmpty {
            resolvedMembers = ids.compactMap { id in allUsers.first { $0.id == id } }
        } else {
            resolvedMembers = Array(task.teamMembers)
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.line)
            .frame(height: 1)
    }

    // MARK: - Photo Carousel

    @ViewBuilder
    private var photoCarousel: some View {
        let photos = task.project?.getProjectImages() ?? []
        if photos.isEmpty {
            Rectangle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(height: 200)
                .overlay(
                    VStack(spacing: OPSStyle.Layout.spacing2) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 32))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Text("NO PHOTOS")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                )
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    ForEach(photos, id: \.self) { url in
                        PhotoThumbnail(url: url, project: task.project)
                            .frame(width: 200, height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.modalRadius))
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .frame(height: 200)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Color bar
            Rectangle()
                .fill(Color(hex: task.effectiveColor) ?? OPSStyle.Colors.primaryAccent)
                .frame(height: 4)
                .cornerRadius(OPSStyle.Layout.progressBarRadius)

            // Task title
            Text(task.displayTitle.uppercased())
                .font(OPSStyle.Typography.pageTitle)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)

            // Status badge
            Text(task.status.displayName.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(.white)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, 3)
                .background(Capsule().fill(task.status.color))
        }
    }

    // MARK: - Project Info

    private var projectInfoSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(icon: "folder.fill", title: "PROJECT")

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                if let project = task.project {
                    Text(project.title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text(project.effectiveClientName.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                } else {
                    Text("No project")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
    }

    // MARK: - Schedule

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(icon: "calendar", title: "SCHEDULE")

            HStack(spacing: OPSStyle.Layout.spacing4) {
                if let start = task.startDate {
                    dateColumn("SCHEDULED", date: start)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("DURATION")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("\(task.duration) DAY\(task.duration == 1 ? "" : "S")")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.line, lineWidth: 1)
            )
        }
    }

    private func dateColumn(_ label: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    // MARK: - Team

    private var teamSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(icon: "person.2.fill", title: "TEAM")

            if resolvedMembers.isEmpty {
                Text("No team members assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                VStack(spacing: 0) {
                    ForEach(resolvedMembers, id: \.id) { member in
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            UserAvatar(user: member, size: 36)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(member.firstName) \(member.lastName)")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                Text(member.role.displayName)
                                    .font(OPSStyle.Typography.smallCaption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                            }

                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                }
            }
        }
    }

    // MARK: - Notes

    private func notesSection(_ notes: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader(icon: "note.text", title: "NOTES")

            Text(notes)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(6)
        }
    }

    // MARK: - Full Details Button

    private var fullDetailsButton: some View {
        NavigationLink {
            if let project = task.project {
                TaskDetailsView(task: task, project: project)
            }
        } label: {
            Text("VIEW FULL DETAILS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                )
        }
        .disabled(task.project == nil)
    }

    // MARK: - Helpers

    private func sectionHeader(icon: String, title: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(title)
                .font(OPSStyle.Typography.captionBold)
        }
        .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}
