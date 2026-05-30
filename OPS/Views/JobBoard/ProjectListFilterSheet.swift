//
//  ProjectListFilterSheet.swift
//  OPS
//
//  Dedicated filter / sort sheet for the Job Board project list.
//  Uses a top-level segmented picker to split Filter vs Sort so a long
//  filter list never pushes the sort options off-screen, and wraps each
//  filter section in a collapsible DisclosureGroup with an internal
//  max-height scroll so large team rosters don't take over the sheet.
//

import SwiftUI

struct ProjectListFilterSheet: View {
    enum Segment: String, CaseIterable, Hashable {
        case filter = "FILTER"
        case sort = "SORT"
    }

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedStatuses: Set<Status>
    @Binding var selectedTeamMemberIds: Set<String>
    @Binding var sortOption: ProjectSortOption

    let availableTeamMembers: [User]

    @State private var segment: Segment = .filter
    @State private var statusSectionExpanded: Bool = true
    @State private var teamSectionExpanded: Bool = false

    /// Max height for an expanded filter section's content area. Keeps the
    /// list scrollable inside the section instead of expanding the sheet.
    private let expandedSectionMaxHeight: CGFloat = 260

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    segmentedHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 12)

                    ScrollView {
                        VStack(spacing: 16) {
                            switch segment {
                            case .filter:
                                filterSectionsContent
                            case .sort:
                                sortSectionContent
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("RESET") { resetAll() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .disabled(!hasAnyChange)
                }
                ToolbarItem(placement: .principal) {
                    Text("FILTER PROJECTS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") { dismiss() }
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    // MARK: - Header

    private var segmentedHeader: some View {
        HStack(spacing: 0) {
            ForEach(Segment.allCases, id: \.self) { option in
                Button {
                    withAnimation(OPSStyle.Animation.fast) {
                        segment = option
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 6) {
                        Text(option.rawValue)
                            .font(OPSStyle.Typography.captionBold)
                            .tracking(0.8)
                        if option == .filter, activeFilterCount > 0 {
                            Text("\(activeFilterCount)")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.background)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(segment == .filter ? OPSStyle.Colors.background : OPSStyle.Colors.primaryAccent)
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundColor(segment == option ? OPSStyle.Colors.background : OPSStyle.Colors.primaryText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(segment == option ? OPSStyle.Colors.primaryAccent : Color.clear)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius + 4)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Filter Content

    @ViewBuilder
    private var filterSectionsContent: some View {
        collapsibleSection(
            title: "PROJECT STATUS",
            icon: OPSStyle.Icons.alert,
            isExpanded: $statusSectionExpanded,
            badgeCount: selectedStatuses.count
        ) {
            VStack(spacing: 0) {
                let statuses: [Status] = [.rfq, .estimated, .accepted, .inProgress, .completed, .closed]
                ForEach(Array(statuses.enumerated()), id: \.element) { index, status in
                    multiSelectRow(
                        label: status.displayName,
                        isSelected: selectedStatuses.contains(status),
                        colorIndicator: status.color,
                        onTap: {
                            if selectedStatuses.contains(status) {
                                selectedStatuses.remove(status)
                            } else {
                                selectedStatuses.insert(status)
                            }
                        }
                    )
                    if index < statuses.count - 1 {
                        Divider().background(OPSStyle.Colors.cardBackground).padding(.leading, 44)
                    }
                }
            }
        }

        if !availableTeamMembers.isEmpty {
            collapsibleSection(
                title: "ASSIGNED TEAM MEMBERS",
                icon: OPSStyle.Icons.crew,
                isExpanded: $teamSectionExpanded,
                badgeCount: selectedTeamMemberIds.count
            ) {
                VStack(spacing: 0) {
                    ForEach(Array(availableTeamMembers.enumerated()), id: \.element.id) { index, member in
                        multiSelectRow(
                            label: "\(member.firstName) \(member.lastName)",
                            subtitle: member.role.rawValue,
                            isSelected: selectedTeamMemberIds.contains(member.id),
                            colorIndicator: nil,
                            onTap: {
                                if selectedTeamMemberIds.contains(member.id) {
                                    selectedTeamMemberIds.remove(member.id)
                                } else {
                                    selectedTeamMemberIds.insert(member.id)
                                }
                            }
                        )
                        if index < availableTeamMembers.count - 1 {
                            Divider().background(OPSStyle.Colors.cardBackground).padding(.leading, 44)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Sort Content

    @ViewBuilder
    private var sortSectionContent: some View {
        VStack(spacing: 0) {
            ForEach(Array(ProjectSortOption.allCases.enumerated()), id: \.element) { index, option in
                HStack {
                    Text(option.rawValue)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Spacer()
                    if sortOption == option {
                        Image(OPSStyle.Icons.checkmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
                .onTapGesture {
                    sortOption = option
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                if index < ProjectSortOption.allCases.count - 1 {
                    Divider().background(OPSStyle.Colors.cardBackground).padding(.leading, 16)
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Collapsible Section Shell

    @ViewBuilder
    private func collapsibleSection<Content: View>(
        title: String,
        icon: String,
        isExpanded: Binding<Bool>,
        badgeCount: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(OPSStyle.Animation.standard) {
                    isExpanded.wrappedValue.toggle()
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .frame(width: 20)

                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    if badgeCount > 0 {
                        Text("\(badgeCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.background)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image("ops.chevron-down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .rotationEffect(.degrees(isExpanded.wrappedValue ? 0 : -90))
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded.wrappedValue {
                Divider().background(OPSStyle.Colors.cardBackground)
                // Wrap the content in its own ScrollView bounded to a max
                // height so long lists (e.g. a 40-member team roster) don't
                // take over the sheet. Native scroll indicators are on for
                // discoverability.
                ScrollView {
                    content()
                }
                .frame(maxHeight: expandedSectionMaxHeight)
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Row Primitives

    @ViewBuilder
    private func multiSelectRow(
        label: String,
        subtitle: String? = nil,
        isSelected: Bool,
        colorIndicator: Color?,
        onTap: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            if let colorIndicator = colorIndicator {
                RoundedRectangle(cornerRadius: 3)
                    .fill(colorIndicator)
                    .frame(width: 10, height: 18)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }

            Spacer()

            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .font(.system(size: OPSStyle.Layout.IconSize.md))
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    // MARK: - Helpers

    private var activeFilterCount: Int {
        var count = 0
        if !selectedStatuses.isEmpty { count += 1 }
        if !selectedTeamMemberIds.isEmpty { count += 1 }
        return count
    }

    private var hasAnyChange: Bool {
        !selectedStatuses.isEmpty || !selectedTeamMemberIds.isEmpty || sortOption != .latestEdited
    }

    private func resetAll() {
        selectedStatuses.removeAll()
        selectedTeamMemberIds.removeAll()
        sortOption = .latestEdited
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }
}
