//
//  CalendarFilterView.swift
//  OPS
//
//  Filter sheet for calendar events by team member, task type, client, status.
//  Bug 294ea224 + f4f76acd — collapsible dropdown sections keep the sheet
//  compact instead of stacking every option expanded. Subsumes the legacy
//  ScheduleTeamScopeSheet (removed) since the TEAM filter lives here now.
//

import SwiftUI
import SwiftData

struct CalendarFilterView: View {
    @EnvironmentObject private var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.dismiss) private var dismiss

    // Local state for filters being edited
    @State private var selectedTeamMemberIds: Set<String> = []
    @State private var selectedTaskTypeIds: Set<String> = []
    @State private var selectedClientIds: Set<String> = []
    @State private var selectedStatuses: Set<Status> = []

    // Available options
    @State private var availableTeamMembers: [TeamMember] = []
    @State private var availableTaskTypes: [TaskType] = []
    @State private var availableClients: [Client] = []

    // Which dropdown is currently expanded (only one at a time so the sheet
    // stays scannable instead of becoming a wall of checkboxes).
    @State private var expandedSection: Section? = nil

    private enum Section: String, Hashable {
        case team, taskType, status, client
    }

    @State private var _clientSearchText: String = ""
    @State private var displayedClientCount: Int = 6

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 12) {
                        teamSection
                        taskTypeSection
                        statusSection
                        clientSection

                        if hasActiveFilters {
                            activeFiltersSummary
                                .padding(.top, 8)
                        }
                    }
                    .padding(.vertical, 16)
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("FILTER CALENDAR")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("RESET") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        resetAll()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!hasActiveFilters)
                }

                ToolbarItem(placement: .principal) {
                    Text("FILTER CALENDAR")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("DONE") {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
        .onAppear {
            loadAvailableOptions()
            loadCurrentFilters()
        }
        .onChange(of: selectedTeamMemberIds) { _, _ in applyFilters() }
        .onChange(of: selectedTaskTypeIds) { _, _ in applyFilters() }
        .onChange(of: selectedClientIds) { _, _ in applyFilters() }
        .onChange(of: selectedStatuses) { _, _ in applyFilters() }
    }

    // MARK: - Sections

    private var teamSection: some View {
        DropdownSection(
            title: "TEAM",
            icon: OPSStyle.Icons.crew,
            summary: teamSummary,
            isExpanded: expandedSection == .team,
            onToggle: { toggle(.team) }
        ) {
            VStack(spacing: 0) {
                allRow(
                    label: "ALL TEAM",
                    isSelected: selectedTeamMemberIds.isEmpty,
                    action: { selectedTeamMemberIds.removeAll() }
                )

                if !availableTeamMembers.isEmpty {
                    Divider().background(OPSStyle.Colors.separator)
                }

                ForEach(Array(sortedTeamMembers.enumerated()), id: \.element.id) { index, member in
                    selectRow(
                        title: member.fullName,
                        subtitle: member.role.isEmpty ? nil : member.role,
                        isSelected: selectedTeamMemberIds.contains(member.id),
                        action: { toggleId(&selectedTeamMemberIds, member.id) }
                    )

                    if index < sortedTeamMembers.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.separator)
                            .padding(.leading, 16)
                    }
                }

                if availableTeamMembers.isEmpty {
                    emptyRow(text: "No team members")
                }
            }
        }
    }

    private var taskTypeSection: some View {
        DropdownSection(
            title: "TASK TYPE",
            icon: "checkmark.circle.fill",
            summary: taskTypeSummary,
            isExpanded: expandedSection == .taskType,
            onToggle: { toggle(.taskType) }
        ) {
            VStack(spacing: 0) {
                allRow(
                    label: "ALL TASK TYPES",
                    isSelected: selectedTaskTypeIds.isEmpty,
                    action: { selectedTaskTypeIds.removeAll() }
                )

                if !availableTaskTypes.isEmpty {
                    Divider().background(OPSStyle.Colors.separator)
                }

                ForEach(Array(availableTaskTypes.enumerated()), id: \.element.id) { index, type in
                    HStack(spacing: 12) {
                        Image(systemName: type.icon ?? "checkmark.circle.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(Color(hex: type.color) ?? OPSStyle.Colors.primaryAccent)
                            .frame(width: 20)

                        Text(type.display)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if selectedTaskTypeIds.contains(type.id) {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture { toggleId(&selectedTaskTypeIds, type.id) }

                    if index < availableTaskTypes.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.separator)
                            .padding(.leading, 16)
                    }
                }

                if availableTaskTypes.isEmpty {
                    emptyRow(text: "No task types")
                }
            }
        }
    }

    private var statusSection: some View {
        DropdownSection(
            title: "STATUS",
            icon: OPSStyle.Icons.alert,
            summary: statusSummary,
            isExpanded: expandedSection == .status,
            onToggle: { toggle(.status) }
        ) {
            VStack(spacing: 0) {
                allRow(
                    label: "ALL STATUSES",
                    isSelected: selectedStatuses.isEmpty,
                    action: { selectedStatuses.removeAll() }
                )

                Divider().background(OPSStyle.Colors.separator)

                ForEach(Array(Status.allCases.enumerated()), id: \.offset) { index, status in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(status.color)
                            .frame(width: 10, height: 10)

                        Text(status.displayName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if selectedStatuses.contains(status) {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if selectedStatuses.contains(status) {
                            selectedStatuses.remove(status)
                        } else {
                            selectedStatuses.insert(status)
                        }
                    }

                    if index < Status.allCases.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.separator)
                            .padding(.leading, 16)
                    }
                }
            }
        }
    }

    private var clientSection: some View {
        DropdownSection(
            title: "CLIENT",
            icon: "building.2.fill",
            summary: clientSummary,
            isExpanded: expandedSection == .client,
            onToggle: { toggle(.client) }
        ) {
            VStack(spacing: 0) {
                allRow(
                    label: "ALL CLIENTS",
                    isSelected: selectedClientIds.isEmpty,
                    action: { selectedClientIds.removeAll() }
                )

                if !availableClients.isEmpty {
                    Divider().background(OPSStyle.Colors.separator)

                    // Search field
                    HStack(spacing: 8) {
                        Image(systemName: OPSStyle.Icons.search)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        TextField("Search clients...", text: $_clientSearchText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .autocapitalization(.none)
                            .autocorrectionDisabled(true)

                        if !_clientSearchText.isEmpty {
                            Button(action: { _clientSearchText = "" }) {
                                Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(OPSStyle.Colors.surfaceInput)

                    Divider().background(OPSStyle.Colors.separator)
                }

                let visible = displayedClients
                ForEach(Array(visible.enumerated()), id: \.element.id) { index, client in
                    selectRow(
                        title: client.name,
                        subtitle: client.email ?? nil,
                        isSelected: selectedClientIds.contains(client.id),
                        action: { toggleId(&selectedClientIds, client.id) }
                    )

                    if index < visible.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.separator)
                            .padding(.leading, 16)
                    }
                }

                if filteredClients.count > displayedClientCount {
                    Divider().background(OPSStyle.Colors.separator)
                    Button(action: { displayedClientCount += 6 }) {
                        HStack {
                            Spacer()
                            Text("SHOW MORE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Image(systemName: OPSStyle.Icons.chevronDown)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                if visible.isEmpty && !_clientSearchText.isEmpty {
                    emptyRow(text: "No clients match \"\(_clientSearchText)\"")
                } else if availableClients.isEmpty {
                    emptyRow(text: "No clients")
                }
            }
        }
        .onChange(of: _clientSearchText) { _, _ in displayedClientCount = 6 }
    }

    // MARK: - Active filters summary

    private var activeFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ACTIVE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            CalendarFilterFlowLayout(spacing: 8) {
                if !selectedTeamMemberIds.isEmpty {
                    summaryChip(icon: OPSStyle.Icons.crew, count: selectedTeamMemberIds.count, label: "team")
                }
                if !selectedTaskTypeIds.isEmpty {
                    summaryChip(icon: "checkmark.circle.fill", count: selectedTaskTypeIds.count, label: "task type")
                }
                if !selectedStatuses.isEmpty {
                    summaryChip(icon: OPSStyle.Icons.alert, count: selectedStatuses.count, label: "status")
                }
                if !selectedClientIds.isEmpty {
                    summaryChip(icon: "building.2.fill", count: selectedClientIds.count, label: "client")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryChip(icon: String, count: Int, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            Text("\(count) \(label)\(count == 1 ? "" : "s")")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(OPSStyle.Colors.primaryAccent.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Row helpers

    private func allRow(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.text2)
            Spacer()
            if isSelected {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func selectRow(title: String, subtitle: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func emptyRow(text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.smallCaption)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 16)
    }

    // MARK: - Computed summaries (shown in collapsed header)

    private var teamSummary: String {
        if selectedTeamMemberIds.isEmpty { return "All" }
        if selectedTeamMemberIds.count == 1,
           let id = selectedTeamMemberIds.first,
           let member = availableTeamMembers.first(where: { $0.id == id }) {
            return member.fullName
        }
        return "\(selectedTeamMemberIds.count) selected"
    }

    private var taskTypeSummary: String {
        if selectedTaskTypeIds.isEmpty { return "All" }
        return "\(selectedTaskTypeIds.count) selected"
    }

    private var statusSummary: String {
        if selectedStatuses.isEmpty { return "All" }
        if selectedStatuses.count == 1, let status = selectedStatuses.first {
            return status.displayName
        }
        return "\(selectedStatuses.count) selected"
    }

    private var clientSummary: String {
        if selectedClientIds.isEmpty { return "All" }
        return "\(selectedClientIds.count) selected"
    }

    private var sortedTeamMembers: [TeamMember] {
        // Self at top, rest alphabetical — mirrors the legacy ScheduleTeamScopeSheet
        // ordering so muscle memory carries over.
        let currentUserId = dataController.currentUser?.id
        return availableTeamMembers.sorted { a, b in
            let aIsSelf = a.id == currentUserId
            let bIsSelf = b.id == currentUserId
            if aIsSelf != bIsSelf { return aIsSelf }
            return a.fullName < b.fullName
        }
    }

    private var filteredClients: [Client] {
        guard !_clientSearchText.isEmpty else { return availableClients }
        return availableClients.filter { client in
            client.name.localizedCaseInsensitiveContains(_clientSearchText) ||
            (client.email ?? "").localizedCaseInsensitiveContains(_clientSearchText)
        }
    }

    private var displayedClients: [Client] {
        Array(filteredClients.prefix(displayedClientCount))
    }

    private var hasActiveFilters: Bool {
        !selectedTeamMemberIds.isEmpty ||
            !selectedTaskTypeIds.isEmpty ||
            !selectedClientIds.isEmpty ||
            !selectedStatuses.isEmpty
    }

    // MARK: - Actions

    private func toggle(_ section: Section) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Single easing curve per OPS motion spec — no spring.
        withAnimation(.easeOut(duration: 0.22)) {
            expandedSection = (expandedSection == section) ? nil : section
        }
    }

    private func toggleId(_ set: inout Set<String>, _ id: String) {
        if set.contains(id) { set.remove(id) } else { set.insert(id) }
    }

    private func resetAll() {
        selectedTeamMemberIds.removeAll()
        selectedTaskTypeIds.removeAll()
        selectedClientIds.removeAll()
        selectedStatuses.removeAll()
    }

    private func loadAvailableOptions() {
        guard let companyId = dataController.currentUser?.companyId,
              dataController.getCompany(id: companyId) != nil else { return }

        let users = dataController.getTeamMembers(companyId: companyId)
        availableTeamMembers = users.map { TeamMember.fromUser($0) }.sorted { $0.fullName < $1.fullName }

        availableTaskTypes = dataController.getAllTaskTypes(for: companyId).sorted { $0.displayOrder < $1.displayOrder }

        availableClients = dataController.getAllClients(for: companyId).sorted {
            if let date1 = $0.createdAt, let date2 = $1.createdAt { return date1 > date2 }
            if $0.createdAt != nil { return true }
            if $1.createdAt != nil { return false }
            return $0.name < $1.name
        }
    }

    private func loadCurrentFilters() {
        selectedTeamMemberIds = viewModel.selectedTeamMemberIds
        selectedTaskTypeIds = viewModel.selectedTaskTypeIds
        selectedClientIds = viewModel.selectedClientIds
        selectedStatuses = viewModel.selectedStatuses
    }

    private func applyFilters() {
        viewModel.applyFilters(
            teamMemberIds: selectedTeamMemberIds,
            taskTypeIds: selectedTaskTypeIds,
            clientIds: selectedClientIds,
            statuses: selectedStatuses
        )
    }
}

// MARK: - Dropdown Section

/// Collapsible section with a header summary and a body revealed on tap.
/// Used by CalendarFilterView to keep the filter sheet compact.
private struct DropdownSection<Content: View>: View {
    let title: String
    let icon: String
    let summary: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            // Header row — always visible, tappable to expand/collapse
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(width: 20)

                    Text(title)
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Spacer()

                    Text(summary.uppercased())
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(summary == "All" ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryAccent)
                        .lineLimit(1)

                    Image(systemName: "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            // Body — revealed when expanded
            if isExpanded {
                Divider().background(OPSStyle.Colors.separator)
                content()
                    .transition(.opacity)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

// MARK: - Flow Layout (for active-filter chips)

private struct CalendarFilterFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let (size, _) = layout(subviews: subviews, in: width)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let (_, frames) = layout(subviews: subviews, in: bounds.width)
        for (frame, subview) in zip(frames, subviews) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.origin.x, y: bounds.minY + frame.origin.y),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func layout(subviews: Subviews, in maxWidth: CGFloat) -> (CGSize, [CGRect]) {
        var frames: [CGRect] = []
        var rowHeight: CGFloat = 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var maxRowWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            maxRowWidth = max(maxRowWidth, x - spacing)
        }

        return (CGSize(width: maxRowWidth, height: y + rowHeight), frames)
    }
}
