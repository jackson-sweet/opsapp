//
//  FilterSheet.swift
//  OPS
//
//  Generic filter sheet component supporting multiple filter types, sorting, search, and pagination
//  Consolidates: ProjectListFilterSheet, TaskListFilterSheet, CalendarFilterView, ProjectSearchFilterView
//

import SwiftUI

/// Generic filter sheet supporting multiple filter types and sorting
///
/// Filters apply immediately (live filtering) - no Apply button required.
/// Changes to filters update bindings in real-time.
///
/// Usage Example:
/// ```swift
/// FilterSheet(
///     title: "Filter Projects",
///     filters: [
///         .multiSelect(
///             title: "PROJECT STATUS",
///             icon: OPSStyle.Icons.alert,
///             options: Status.allCases,
///             selection: $selectedStatuses,
///             getDisplay: { $0.displayName },
///             getColorIndicator: { .rectangle($0.color) }
///         ),
///         .multiSelect(
///             title: "TEAM MEMBERS",
///             icon: OPSStyle.Icons.crew,
///             options: availableTeamMembers,
///             selection: $selectedTeamMemberIds,
///             getId: { $0.id },
///             getDisplay: { "\($0.firstName) \($0.lastName)" },
///             getSubtitle: { $0.role.rawValue }
///         )
///     ],
///     sortOptions: ProjectSortOption.allCases,
///     selectedSort: $sortOption,
///     getSortDisplay: { $0.rawValue }
/// )
/// ```
struct FilterSheet<SortOption: Hashable & CaseIterable>: View {
    let title: String
    let filters: [FilterSectionConfig]
    let sortOptions: [SortOption]?
    @Binding var selectedSort: SortOption?
    let getSortDisplay: ((SortOption) -> String)?

    @Environment(\.dismiss) private var dismiss

    init(
        title: String,
        filters: [FilterSectionConfig],
        sortOptions: [SortOption]? = nil,
        selectedSort: Binding<SortOption?> = .constant(nil),
        getSortDisplay: ((SortOption) -> String)? = nil
    ) {
        self.title = title
        self.filters = filters
        self.sortOptions = sortOptions
        self._selectedSort = selectedSort
        self.getSortDisplay = getSortDisplay
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Render each filter section
                        ForEach(filters) { filterConfig in
                            filterConfig.render()
                        }

                        // Sort section (if provided)
                        if let sortOptions = sortOptions,
                           let getSortDisplay = getSortDisplay,
                           let selectedSort = selectedSort {
                            sortSection(
                                options: sortOptions,
                                selectedSort: Binding(
                                    get: { selectedSort },
                                    set: { self.selectedSort = $0 }
                                ),
                                getDisplay: getSortDisplay
                            )
                        }

                        // Active filters summary
                        if hasActiveFilters {
                            activeFiltersSummary
                        }
                    }
                    .padding(.vertical, 20)
                }
            }
            .navigationTitle(title.uppercased())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("DONE") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }

                ToolbarItem(placement: .principal) {
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("RESET") {
                        resetFilters()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(!hasActiveFilters)
                }
            }
        }
    }

    // MARK: - Sort Section

    private func sortSection(
        options: [SortOption],
        selectedSort: Binding<SortOption>,
        getDisplay: @escaping (SortOption) -> String
    ) -> some View {
        filterSection(
            title: "SORT BY",
            icon: "arrow.up.arrow.down"
        ) {
            VStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    HStack {
                        Text(getDisplay(option))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Spacer()

                        if selectedSort.wrappedValue == option {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedSort.wrappedValue = option
                    }

                    if index < options.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.cardBackground)
                            .padding(.leading, 40)
                    }
                }
            }
        }
    }

    // MARK: - Active Filters Summary

    private var activeFiltersSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ACTIVE FILTERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 20)

            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    // Show active filter counts
                    ForEach(filters) { filterConfig in
                        filterConfig.renderActiveFilterRow()
                    }

                    // Show sort if not default
                    if sortOptions != nil, let selectedSort = selectedSort, let getSortDisplay = getSortDisplay {
                        HStack {
                            Image(systemName: "arrow.up.arrow.down")
                                .font(.system(size: 12))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(getSortDisplay(selectedSort))
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                )

                Spacer()
            }
            .padding(.horizontal, 20)
        }
    }

    private var hasActiveFilters: Bool {
        filters.contains { $0.hasActiveFilters }
    }

    private func resetFilters() {
        filters.forEach { $0.reset() }
        if let sortOptions = sortOptions, let first = sortOptions.first {
            selectedSort = first
        }
    }

    // MARK: - Helper Views

    private func filterSection<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
        }
    }
}

// MARK: - Filter Section Configuration

/// Configuration for a filter section (status, team members, task types, etc.)
struct FilterSectionConfig: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let hasActiveFilters: Bool
    let reset: () -> Void
    let render: () -> AnyView
    let renderActiveFilterRow: () -> AnyView?

    /// Multi-select filter (standard) - value-based selection
    static func multiSelect<T: Hashable>(
        title: String,
        icon: String,
        options: [T],
        selection: Binding<Set<T>>,
        getDisplay: @escaping (T) -> String,
        getSubtitle: ((T) -> String)? = nil,
        getColorIndicator: ((T) -> ColorIndicator)? = nil,
        getIcon: ((T) -> String)? = nil,
        getIconColor: ((T) -> Color)? = nil
    ) -> FilterSectionConfig {
        FilterSectionConfig(
            title: title,
            icon: icon,
            hasActiveFilters: !selection.wrappedValue.isEmpty,
            reset: { selection.wrappedValue.removeAll() },
            render: {
                AnyView(
                    MultiSelectFilterSection(
                        title: title,
                        icon: icon,
                        options: options,
                        selection: selection,
                        getDisplay: getDisplay,
                        getSubtitle: getSubtitle,
                        getColorIndicator: getColorIndicator,
                        getIcon: getIcon,
                        getIconColor: getIconColor,
                        searchable: false,
                        paginated: false
                    )
                )
            },
            renderActiveFilterRow: {
                guard !selection.wrappedValue.isEmpty else { return nil }
                return AnyView(
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("\(selection.wrappedValue.count) \(title.lowercased())\(selection.wrappedValue.count == 1 ? "" : "s") selected")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                )
            }
        )
    }

    /// Multi-select filter - ID-based selection (for objects with IDs)
    static func multiSelectById<T: Identifiable>(
        title: String,
        icon: String,
        options: [T],
        selection: Binding<Set<String>>,
        getId: @escaping (T) -> String,
        getDisplay: @escaping (T) -> String,
        getSubtitle: ((T) -> String)? = nil,
        getIcon: ((T) -> String)? = nil,
        getIconColor: ((T) -> Color)? = nil
    ) -> FilterSectionConfig {
        FilterSectionConfig(
            title: title,
            icon: icon,
            hasActiveFilters: !selection.wrappedValue.isEmpty,
            reset: { selection.wrappedValue.removeAll() },
            render: {
                AnyView(
                    IdBasedMultiSelectSection(
                        title: title,
                        icon: icon,
                        options: options,
                        selection: selection,
                        getId: getId,
                        getDisplay: getDisplay,
                        getSubtitle: getSubtitle,
                        getIcon: getIcon,
                        getIconColor: getIconColor
                    )
                )
            },
            renderActiveFilterRow: {
                guard !selection.wrappedValue.isEmpty else { return nil }
                return AnyView(
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("\(selection.wrappedValue.count) \(title.lowercased())\(selection.wrappedValue.count == 1 ? "" : "s") selected")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                )
            }
        )
    }

    /// Multi-select filter with search and pagination (for clients, etc.)
    static func multiSelectWithSearch<T: Hashable & Identifiable>(
        title: String,
        icon: String,
        options: [T],
        selection: Binding<Set<String>>,
        getId: @escaping (T) -> String,
        getDisplay: @escaping (T) -> String,
        getSubtitle: ((T) -> String)? = nil,
        searchPlaceholder: String = "Search...",
        pageSize: Int = 5
    ) -> FilterSectionConfig {
        FilterSectionConfig(
            title: title,
            icon: icon,
            hasActiveFilters: !selection.wrappedValue.isEmpty,
            reset: { selection.wrappedValue.removeAll() },
            render: {
                AnyView(
                    SearchableMultiSelectSection(
                        title: title,
                        icon: icon,
                        options: options,
                        selection: selection,
                        getId: getId,
                        getDisplay: getDisplay,
                        getSubtitle: getSubtitle,
                        searchPlaceholder: searchPlaceholder,
                        pageSize: pageSize
                    )
                )
            },
            renderActiveFilterRow: {
                guard !selection.wrappedValue.isEmpty else { return nil }
                return AnyView(
                    HStack {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)

                        Text("\(selection.wrappedValue.count) \(title.lowercased())\(selection.wrappedValue.count == 1 ? "" : "s") selected")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                )
            }
        )
    }
}

/// Color indicator style for filter rows
enum ColorIndicator {
    case rectangle(Color)
    case circle(Color)
}

// MARK: - Multi-Select Filter Section

private struct MultiSelectFilterSection<T: Hashable>: View {
    let title: String
    let icon: String
    let options: [T]
    @Binding var selection: Set<T>
    let getDisplay: (T) -> String
    let getSubtitle: ((T) -> String)?
    let getColorIndicator: ((T) -> ColorIndicator)?
    let getIcon: ((T) -> String)?
    let getIconColor: ((T) -> Color)?
    let searchable: Bool
    let paginated: Bool

    var body: some View {
        FilterSectionContainer(title: title, icon: icon) {
            VStack(spacing: 0) {
                // "All" option
                FilterRow(
                    title: "All \(title)",
                    isSelected: selection.isEmpty,
                    isSpecial: true,
                    action: { selection.removeAll() }
                )

                Divider()
                    .background(OPSStyle.Colors.separator)

                // Individual options
                ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                    HStack(spacing: 12) {
                        // Color indicator (if provided)
                        if let getColorIndicator = getColorIndicator {
                            let indicator = getColorIndicator(option)
                            switch indicator {
                            case .rectangle(let color):
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(color)
                                    .frame(width: 2, height: 12)
                            case .circle(let color):
                                Circle()
                                    .fill(color)
                                    .frame(width: 10, height: 10)
                            }
                        }

                        // Icon (if provided)
                        if let getIcon = getIcon, let getIconColor = getIconColor {
                            Image(systemName: getIcon(option))
                                .font(.system(size: 16))
                                .foregroundColor(getIconColor(option))
                                .frame(width: 20)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(getDisplay(option))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            if let getSubtitle = getSubtitle {
                                let subtitle = getSubtitle(option)
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                            }
                        }

                        Spacer()

                        if selection.contains(option) {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(option)
                    }

                    if index < options.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.cardBackground)
                            .padding(.leading, getColorIndicator != nil || getIcon != nil ? 40 : 20)
                    }
                }
            }
        }
    }

    private func toggleSelection(_ item: T) {
        if selection.contains(item) {
            selection.remove(item)
        } else {
            selection.insert(item)
        }
    }
}

// MARK: - ID-Based Multi-Select Section

private struct IdBasedMultiSelectSection<T: Identifiable>: View {
    let title: String
    let icon: String
    let options: [T]
    @Binding var selection: Set<String>
    let getId: (T) -> String
    let getDisplay: (T) -> String
    let getSubtitle: ((T) -> String)?
    let getIcon: ((T) -> String)?
    let getIconColor: ((T) -> Color)?

    var body: some View {
        FilterSectionContainer(title: title, icon: icon) {
            VStack(spacing: 0) {
                // "All" option
                FilterRow(
                    title: "All \(title)",
                    isSelected: selection.isEmpty,
                    isSpecial: true,
                    action: { selection.removeAll() }
                )

                Divider()
                    .background(OPSStyle.Colors.separator)

                // Individual options
                ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                    HStack(spacing: 12) {
                        // Icon (if provided)
                        if let getIcon = getIcon, let getIconColor = getIconColor {
                            Image(systemName: getIcon(option))
                                .font(.system(size: 16))
                                .foregroundColor(getIconColor(option))
                                .frame(width: 20)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(getDisplay(option))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)

                            if let getSubtitle = getSubtitle {
                                let subtitle = getSubtitle(option)
                                if !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                            }
                        }

                        Spacer()

                        if selection.contains(getId(option)) {
                            Image(systemName: OPSStyle.Icons.checkmark)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                        }
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        toggleSelection(getId(option))
                    }

                    if index < options.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.cardBackground)
                            .padding(.leading, getIcon != nil ? 40 : 20)
                    }
                }
            }
        }
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

// MARK: - Searchable Multi-Select Section (for Clients)

private struct SearchableMultiSelectSection<T: Hashable & Identifiable>: View {
    let title: String
    let icon: String
    let options: [T]
    @Binding var selection: Set<String>
    let getId: (T) -> String
    let getDisplay: (T) -> String
    let getSubtitle: ((T) -> String)?
    let searchPlaceholder: String
    let pageSize: Int

    @State private var searchText: String = ""
    @State private var displayedCount: Int

    init(
        title: String,
        icon: String,
        options: [T],
        selection: Binding<Set<String>>,
        getId: @escaping (T) -> String,
        getDisplay: @escaping (T) -> String,
        getSubtitle: ((T) -> String)?,
        searchPlaceholder: String,
        pageSize: Int
    ) {
        self.title = title
        self.icon = icon
        self.options = options
        self._selection = selection
        self.getId = getId
        self.getDisplay = getDisplay
        self.getSubtitle = getSubtitle
        self.searchPlaceholder = searchPlaceholder
        self.pageSize = pageSize
        self._displayedCount = State(initialValue: pageSize)
    }

    private var filteredOptions: [T] {
        if searchText.isEmpty {
            return options
        }
        return options.filter { option in
            let display = getDisplay(option)
            let subtitle = getSubtitle?(option) ?? ""
            return display.localizedCaseInsensitiveContains(searchText) ||
                   subtitle.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var displayedOptions: [T] {
        Array(filteredOptions.prefix(displayedCount))
    }

    private var hasMoreOptions: Bool {
        displayedCount < filteredOptions.count
    }

    var body: some View {
        FilterSectionContainer(title: title, icon: icon) {
            VStack(spacing: 0) {
                // "All" option
                FilterRow(
                    title: "All \(title)",
                    isSelected: selection.isEmpty,
                    isSpecial: true,
                    action: { selection.removeAll() }
                )

                Divider()
                    .background(OPSStyle.Colors.separator)

                // Search field
                HStack(spacing: 8) {
                    Image(systemName: OPSStyle.Icons.search)
                        .font(.system(size: 14))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    TextField(searchPlaceholder, text: $searchText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .autocapitalization(.none)
                        .autocorrectionDisabled(true)

                    if !searchText.isEmpty {
                        Button(action: {
                            searchText = ""
                        }) {
                            Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                .font(.system(size: 14))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(OPSStyle.Colors.background.opacity(0.5))

                Divider()
                    .background(OPSStyle.Colors.separator)

                // Individual options
                ForEach(Array(displayedOptions.enumerated()), id: \.element.id) { index, option in
                    FilterRow(
                        title: getDisplay(option),
                        subtitle: getSubtitle?(option),
                        isSelected: selection.contains(getId(option)),
                        action: {
                            toggleSelection(getId(option))
                        }
                    )

                    if index < displayedOptions.count - 1 {
                        Divider()
                            .background(OPSStyle.Colors.cardBackground)
                            .padding(.leading, 16)
                    }
                }

                // Show More button
                if hasMoreOptions {
                    Divider()
                        .background(OPSStyle.Colors.separator)

                    Button(action: {
                        displayedCount += pageSize
                    }) {
                        HStack {
                            Spacer()
                            Text("SHOW MORE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Image(systemName: OPSStyle.Icons.chevronDown)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            Spacer()
                        }
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                // No results message
                if displayedOptions.isEmpty && !searchText.isEmpty {
                    Text("No \(title.lowercased()) found")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.vertical, 32)
                }
            }
        }
        .onChange(of: searchText) { oldValue, newValue in
            // Reset pagination when search text changes
            displayedCount = pageSize
        }
    }

    private func toggleSelection(_ id: String) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

// MARK: - Reusable Components

private struct FilterSectionContainer<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Text(title)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            .padding(.horizontal, 20)

            VStack(spacing: 0) {
                content()
            }
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(OPSStyle.Colors.cardBackgroundDark.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
                    )
            )
            .padding(.horizontal, 20)
        }
    }
}

private struct FilterRow: View {
    let title: String
    var subtitle: String? = nil
    let isSelected: Bool
    var isSpecial: Bool = false
    let action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(isSpecial ? OPSStyle.Typography.bodyBold : OPSStyle.Typography.body)
                    .foregroundColor(isSpecial ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.primaryText)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()

            if isSelected && !isSpecial {
                Image(systemName: OPSStyle.Icons.checkmark)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            } else if isSpecial && isSelected {
                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                    .font(.system(size: 16))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}
