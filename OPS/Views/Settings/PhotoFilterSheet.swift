//
//  PhotoFilterSheet.swift
//  OPS
//

import SwiftUI
import SwiftData

struct PhotoFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Binding var uploaderIds: Set<String>
    @Binding var dateFrom: Date?
    @Binding var dateTo: Date?
    @Binding var taskTypeIds: Set<String>
    @Binding var projectIds: Set<String>

    let allProjects: [Project]
    let allAnnotations: [PhotoAnnotation]

    @State private var projectSearchText = ""

    // Derived data
    private var uploaders: [(id: String, name: String)] {
        let authorIds = Set(allAnnotations.compactMap { $0.authorId.isEmpty ? nil : $0.authorId })
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        let teamMembers = dataController.getTeamMembers(companyId: companyId)

        return authorIds.compactMap { authorId in
            if let user = teamMembers.first(where: { $0.id == authorId }) {
                return (id: authorId, name: user.fullName)
            }
            return nil
        }.sorted { $0.name < $1.name }
    }

    private var taskTypes: [TaskType] {
        guard let companyId = dataController.currentUser?.companyId,
              let context = dataController.modelContext else { return [] }
        do {
            let descriptor = FetchDescriptor<Company>(
                predicate: #Predicate<Company> { $0.id == companyId }
            )
            let companies = try context.fetch(descriptor)
            return companies.first?.taskTypes.sorted { $0.displayOrder < $1.displayOrder } ?? []
        } catch {
            return []
        }
    }

    /// Suggestions shown only when search text is non-empty, max 5, excluding already-selected
    private var projectSuggestions: [Project] {
        guard !projectSearchText.isEmpty else { return [] }
        let query = projectSearchText.lowercased()
        return allProjects
            .filter { !projectIds.contains($0.id) }
            .filter {
                $0.title.lowercased().contains(query) ||
                ($0.client?.name.lowercased().contains(query) ?? false) ||
                ($0.address?.lowercased().contains(query) ?? false)
            }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            .prefix(5)
            .map { $0 }
    }

    /// Projects currently selected as filter chips
    private var selectedProjects: [Project] {
        allProjects.filter { projectIds.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var hasAnyFilter: Bool {
        !uploaderIds.isEmpty || dateFrom != nil || dateTo != nil ||
        !taskTypeIds.isEmpty || !projectIds.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Uploader section
                        if !uploaders.isEmpty {
                            filterSection(title: "UPLOADER") {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: OPSStyle.Layout.spacing2) {
                                        filterChip(label: "All", isSelected: uploaderIds.isEmpty) {
                                            uploaderIds.removeAll()
                                        }
                                        ForEach(uploaders, id: \.id) { uploader in
                                            filterChip(
                                                label: uploader.name,
                                                isSelected: uploaderIds.contains(uploader.id)
                                            ) {
                                                if uploaderIds.contains(uploader.id) {
                                                    uploaderIds.remove(uploader.id)
                                                } else {
                                                    uploaderIds.insert(uploader.id)
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Date range section
                        filterSection(title: "DATE RANGE") {
                            HStack(spacing: OPSStyle.Layout.spacing3) {
                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    Text("From")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                                    datePickerButton(date: dateFrom, placeholder: "Start") { date in
                                        dateFrom = date
                                    } onClear: {
                                        dateFrom = nil
                                    }
                                }

                                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                                    Text("To")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                                    datePickerButton(date: dateTo, placeholder: "End") { date in
                                        dateTo = date
                                    } onClear: {
                                        dateTo = nil
                                    }
                                }
                            }
                        }

                        // Task type section
                        if !taskTypes.isEmpty {
                            filterSection(title: "TASK TYPE") {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: OPSStyle.Layout.spacing2)], spacing: OPSStyle.Layout.spacing2) {
                                    ForEach(taskTypes) { taskType in
                                        filterChip(
                                            label: taskType.display,
                                            isSelected: taskTypeIds.contains(taskType.id)
                                        ) {
                                            if taskTypeIds.contains(taskType.id) {
                                                taskTypeIds.remove(taskType.id)
                                            } else {
                                                taskTypeIds.insert(taskType.id)
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Project section
                        filterSection(title: "PROJECT") {
                            VStack(spacing: OPSStyle.Layout.spacing2) {
                                // Selected project chips
                                if !selectedProjects.isEmpty {
                                    FlowLayout(spacing: OPSStyle.Layout.spacing2) {
                                        ForEach(selectedProjects) { project in
                                            selectedProjectChip(project)
                                        }
                                    }
                                }

                                // Search field
                                HStack(spacing: OPSStyle.Layout.spacing2) {
                                    Image(systemName: OPSStyle.Icons.search)
                                        .font(.system(size: OPSStyle.Layout.SearchField.iconSize))
                                        .foregroundColor(OPSStyle.Layout.SearchField.iconColor)

                                    TextField("Search projects...", text: $projectSearchText)
                                        .font(OPSStyle.Layout.SearchField.textFont)
                                        .foregroundColor(OPSStyle.Layout.SearchField.textColor)
                                        .autocorrectionDisabled(true)

                                    if !projectSearchText.isEmpty {
                                        Button(action: { projectSearchText = "" }) {
                                            Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                                                .font(.system(size: OPSStyle.Layout.SearchField.clearButtonSize))
                                                .foregroundColor(OPSStyle.Layout.SearchField.clearButtonColor)
                                        }
                                    }
                                }
                                .padding(OPSStyle.Layout.SearchField.inputPadding)
                                .background(OPSStyle.Layout.SearchField.inputBackground)
                                .cornerRadius(OPSStyle.Layout.SearchField.inputCornerRadius)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.SearchField.inputCornerRadius)
                                        .stroke(OPSStyle.Layout.SearchField.inputBorderColor, lineWidth: OPSStyle.Layout.SearchField.inputBorderWidth)
                                )

                                // Suggestion rows (only when searching)
                                ForEach(projectSuggestions) { project in
                                    Button(action: {
                                        projectIds.insert(project.id)
                                        projectSearchText = ""
                                    }) {
                                        projectSuggestionRow(project)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("FILTERS")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if hasAnyFilter {
                        Button("Reset") {
                            uploaderIds.removeAll()
                            dateFrom = nil
                            dateTo = nil
                            taskTypeIds.removeAll()
                            projectIds.removeAll()
                        }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    // MARK: - Filter Section

    private func filterSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("[ \(title) ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            content()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Filter Chip

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(isSelected ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(isSelected ? Color.clear : OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Selected Project Chip

    private func selectedProjectChip(_ project: Project) -> some View {
        HStack(spacing: 6) {
            Text(project.title.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            Button(action: { projectIds.remove(project.id) }) {
                Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                    .font(.system(size: 12))
                    .foregroundColor(OPSStyle.Colors.primaryText.opacity(0.6))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(OPSStyle.Colors.primaryAccent)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }

    // MARK: - Project Suggestion Row

    private func projectSuggestionRow(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(project.title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)

            let subtitle = projectSubtitle(project)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .contentShape(Rectangle())
    }

    private func projectSubtitle(_ project: Project) -> String {
        var parts: [String] = []
        if let clientName = project.client?.name, !clientName.isEmpty {
            parts.append(clientName)
        }
        if let address = project.address, !address.isEmpty {
            parts.append(address)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Date Picker Button

    private func datePickerButton(date: Date?, placeholder: String, onSelect: @escaping (Date) -> Void, onClear: @escaping () -> Void) -> some View {
        HStack {
            if let date = date {
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Spacer()

                Button(action: onClear) {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            } else {
                Text(placeholder)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer()
            }
        }
        .padding(OPSStyle.Layout.spacing2_5)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .overlay {
            DatePicker("", selection: Binding(
                get: { date ?? Date() },
                set: { onSelect($0) }
            ), displayedComponents: .date)
            .labelsHidden()
            .colorScheme(.dark)
            .opacity(0.015)  // Nearly invisible but tappable
        }
    }
}
