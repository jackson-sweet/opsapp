//
//  ProjectBioSheet.swift
//  OPS
//

import SwiftUI
import SwiftData

/// Condensed project detail view -- the "Tinder bio" shown when tapping a review card.
struct ProjectBioSheet: View {
    let project: Project
    let showFinancialInfo: Bool
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
                        timelineSection
                        divider
                        teamSection
                        divider
                        notesSection

                        if showFinancialInfo {
                            divider
                            financialSection
                        }
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
                    Text("PROJECT DETAILS")
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
        let ids = project.getTeamMemberIds()
        if !ids.isEmpty && project.teamMembers.isEmpty {
            resolvedMembers = ids.compactMap { id in allUsers.first { $0.id == id } }
        } else {
            resolvedMembers = Array(project.teamMembers)
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
        let photos = project.getProjectImages()
        if photos.isEmpty {
            Rectangle()
                .fill(OPSStyle.Colors.cardBackgroundDark)
                .frame(height: 220)
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
                        PhotoThumbnail(url: url, project: project)
                            .frame(width: 280, height: 220)
                            .clipped()
                    }
                }
            }
            .frame(height: 220)
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(project.title.uppercased())
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if let address = project.address, !address.isEmpty {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: "mappin")
                        .font(.system(size: 12))
                    Text(address)
                        .font(OPSStyle.Typography.caption)
                }
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader("TIMELINE")

            HStack(spacing: OPSStyle.Layout.spacing4) {
                if let start = project.startDate {
                    dateColumn("STARTED", date: start)
                }
                if let completed = project.completedAt {
                    dateColumn("COMPLETED", date: completed)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("OVERDUE")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("\(OverdueProjectDetector.daysSinceCompleted(project)) DAYS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
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
            sectionHeader("TEAM")

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

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader("NOTES")

            if let notes = project.notes, !notes.isEmpty {
                Text(notes)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(6)
            } else {
                Text("No notes")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Financial

    @ViewBuilder
    private var financialSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            sectionHeader("INVOICING")

            // Placeholder -- will wire to actual invoice data
            HStack(spacing: OPSStyle.Layout.spacing4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("STATUS")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("\u{2014}")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }

    // MARK: - Helpers

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(OPSStyle.Typography.captionBold)
            .foregroundColor(OPSStyle.Colors.secondaryText)
    }
}
