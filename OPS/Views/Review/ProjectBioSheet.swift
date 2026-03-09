//
//  ProjectBioSheet.swift
//  OPS
//

import SwiftUI

/// Condensed project detail view -- the "Tinder bio" shown when tapping a review card.
struct ProjectBioSheet: View {
    let project: Project
    let showFinancialInfo: Bool
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    photoCarousel

                    VStack(alignment: .leading, spacing: 20) {
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
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
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
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.1))
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
                    VStack(spacing: 8) {
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
                HStack(spacing: 4) {
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
        VStack(alignment: .leading, spacing: 4) {
            Text(project.title.uppercased())
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            if let address = project.address, !address.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 12))
                    Text(address)
                        .font(OPSStyle.Typography.caption)
                }
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TIMELINE")

            HStack(spacing: 24) {
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
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("TEAM")

            let members = project.teamMembers
            if members.isEmpty {
                Text("No team members assigned")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            } else {
                HStack(spacing: -8) {
                    ForEach(Array(members.prefix(6).enumerated()), id: \.offset) { _, member in
                        Circle()
                            .fill(OPSStyle.Colors.cardBackground)
                            .frame(width: 36, height: 36)
                            .overlay(
                                Text(String(member.firstName.prefix(1)).uppercased())
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            )
                            .overlay(Circle().stroke(OPSStyle.Colors.background, lineWidth: 2))
                    }
                    if members.count > 6 {
                        Text("+\(members.count - 6)")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.leading, 12)
                    }
                }
            }
        }
    }

    // MARK: - Notes

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
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
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader("INVOICING")

            // Placeholder -- will wire to actual invoice data
            HStack(spacing: 24) {
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
