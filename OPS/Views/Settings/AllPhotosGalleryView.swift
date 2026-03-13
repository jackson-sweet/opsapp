//
//  AllPhotosGalleryView.swift
//  OPS
//

import SwiftUI
import SwiftData

// MARK: - Photo Metadata

/// Enriched photo data combining URL with annotation metadata
struct PhotoItem: Identifiable {
    let id: String  // url string
    let url: String
    let projectId: String
    let projectTitle: String
    let date: Date
    let authorId: String?
    let note: String?

    private static let monthKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f
    }()

    private static let monthLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    var monthKey: String {
        Self.monthKeyFormatter.string(from: date)
    }

    var monthLabel: String {
        Self.monthLabelFormatter.string(from: date).uppercased()
    }
}

/// Month group for timeline organization
struct PhotoMonthGroup: Identifiable {
    let id: String  // "yyyy-MM"
    let label: String  // "MARCH 2026"
    let photos: [PhotoItem]

    var projectGroups: [(projectId: String, projectTitle: String, photos: [PhotoItem])] {
        let grouped = Dictionary(grouping: photos, by: { $0.projectId })
        return grouped.map { (projectId: $0.key, projectTitle: $0.value.first?.projectTitle ?? "", photos: $0.value) }
            .sorted { $0.projectTitle.localizedCaseInsensitiveCompare($1.projectTitle) == .orderedAscending }
    }
}

// MARK: - Gallery View

struct AllPhotosGalleryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    @Query private var allProjects: [Project]
    @Query private var allAnnotations: [PhotoAnnotation]
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared

    // UI State
    @State private var groupByProject = false
    @State private var expandedMonths: Set<String> = []
    @State private var expandedProjects: Set<String> = []
    @State private var searchText = ""
    @State private var showFilterSheet = false
    @State private var showStorageManagement = false
    @State private var isSelectMode = false
    @State private var selectedPhotos: Set<String> = []
    @State private var selectedPhotoContext: GalleryPhotoContext? = nil

    // Filter state
    @State private var filterUploaderIds: Set<String> = []
    @State private var filterDateFrom: Date? = nil
    @State private var filterDateTo: Date? = nil
    @State private var filterTaskTypeIds: Set<String> = []
    @State private var filterProjectIds: Set<String> = []

    // MARK: - Grid

    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]

    // MARK: - Computed Data

    /// Build enriched photo items from all projects + annotations
    private var allPhotoItems: [PhotoItem] {
        let annotationMap = Dictionary(grouping: allAnnotations.filter { $0.deletedAt == nil }, by: { $0.photoURL })

        return allProjects
            .filter { $0.deletedAt == nil }
            .flatMap { project -> [PhotoItem] in
                project.getProjectImages().map { url in
                    let annotation = annotationMap[url]?.first(where: { $0.projectId == project.id }) ?? annotationMap[url]?.first
                    return PhotoItem(
                        id: "\(project.id)-\(url)",
                        url: url,
                        projectId: project.id,
                        projectTitle: project.title,
                        date: annotation?.createdAt ?? project.startDate ?? Date(),
                        authorId: annotation?.authorId,
                        note: annotation?.note.isEmpty == false ? annotation?.note : nil
                    )
                }
            }
            .sorted { $0.date > $1.date }
    }

    /// Apply search and filters
    private var filteredPhotoItems: [PhotoItem] {
        var items = allPhotoItems

        // Search filter (project title or note)
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter {
                $0.projectTitle.lowercased().contains(query) ||
                ($0.note?.lowercased().contains(query) ?? false)
            }
        }

        // Uploader filter
        if !filterUploaderIds.isEmpty {
            items = items.filter { item in
                guard let authorId = item.authorId else { return false }
                return filterUploaderIds.contains(authorId)
            }
        }

        // Date range filter
        if let from = filterDateFrom {
            items = items.filter { $0.date >= from }
        }
        if let to = filterDateTo {
            // Use end-of-day so photos from the selected day are included
            let endOfDay = Calendar.current.date(bySettingHour: 23, minute: 59, second: 59, of: to) ?? to
            items = items.filter { $0.date <= endOfDay }
        }

        // Task type filter (project-level: show photos from projects with matching task type)
        if !filterTaskTypeIds.isEmpty {
            let projectIdsWithTaskType = Set(
                allProjects
                    .filter { project in
                        project.tasks.contains { task in
                            filterTaskTypeIds.contains(task.taskTypeId)
                        }
                    }
                    .map { $0.id }
            )
            items = items.filter { projectIdsWithTaskType.contains($0.projectId) }
        }

        // Project filter
        if !filterProjectIds.isEmpty {
            items = items.filter { filterProjectIds.contains($0.projectId) }
        }

        return items
    }

    /// Group filtered items by month
    private var monthGroups: [PhotoMonthGroup] {
        let grouped = Dictionary(grouping: filteredPhotoItems, by: { $0.monthKey })
        return grouped.map { key, photos in
            PhotoMonthGroup(
                id: key,
                label: photos.first?.monthLabel ?? key,
                photos: photos.sorted { $0.date > $1.date }
            )
        }
        .sorted { $0.id > $1.id }  // Most recent month first
    }

    private var hasActiveFilters: Bool {
        !filterUploaderIds.isEmpty || filterDateFrom != nil || filterDateTo != nil ||
        !filterTaskTypeIds.isEmpty || !filterProjectIds.isEmpty
    }

    private var activeFilterCount: Int {
        var count = 0
        if !filterUploaderIds.isEmpty { count += 1 }
        if filterDateFrom != nil || filterDateTo != nil { count += 1 }
        if !filterTaskTypeIds.isEmpty { count += 1 }
        if !filterProjectIds.isEmpty { count += 1 }
        return count
    }

    private var allPhotoURLs: [String] {
        allPhotoItems.map { $0.url }
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                // Header
                if isSelectMode {
                    selectModeHeader
                } else {
                    SettingsHeader(
                        title: "Photos",
                        showEditButton: true,
                        editButtonText: "Select",
                        onBackTapped: { dismiss() },
                        onEditTapped: { isSelectMode = true }
                    )
                }

                if filteredPhotoItems.isEmpty && !allPhotoItems.isEmpty {
                    // Filtered empty state
                    filteredEmptyState
                } else if allPhotoItems.isEmpty {
                    // No photos at all
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing3) {
                            // Search + filter row
                            searchFilterRow

                            // Group toggle
                            groupToggleRow

                            // Summary
                            summaryRow

                            // Month sections
                            ForEach(monthGroups) { monthGroup in
                                monthSection(monthGroup)
                            }

                            // Storage row
                            storageRow
                        }
                        .padding(.vertical, OPSStyle.Layout.spacing3)
                    }
                }

                // Multi-select toolbar
                if isSelectMode && !selectedPhotos.isEmpty {
                    selectToolbar
                }
            }
        }
        .trackScreen("Settings.PhotoGallery")
        .onAppear {
            // Auto-expand the most recent month on first load
            if expandedMonths.isEmpty, let first = monthGroups.first {
                expandedMonths.insert(first.id)
            }
        }
        .sheet(isPresented: $showFilterSheet) {
            PhotoFilterSheet(
                uploaderIds: $filterUploaderIds,
                dateFrom: $filterDateFrom,
                dateTo: $filterDateTo,
                taskTypeIds: $filterTaskTypeIds,
                projectIds: $filterProjectIds,
                allProjects: allProjects.filter { $0.deletedAt == nil },
                allAnnotations: allAnnotations.filter { $0.deletedAt == nil }
            )
            .environmentObject(dataController)
        }
        .sheet(isPresented: $showStorageManagement) {
            PhotoStorageManagementView(
                allPhotoItems: allPhotoItems,
                allProjects: allProjects.filter { $0.deletedAt == nil }
            )
            .environmentObject(dataController)
        }
        .fullScreenCover(item: $selectedPhotoContext) { context in
            PhotoGalleryViewer(
                photos: context.photos,
                initialIndex: context.index,
                onDismiss: { selectedPhotoContext = nil }
            )
            .environmentObject(dataController)
            .environmentObject(appState)
        }
    }

    // MARK: - Search + Filter Row

    private var searchFilterRow: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            // Search field
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: OPSStyle.Icons.search)
                    .font(.system(size: OPSStyle.Layout.SearchField.iconSize))
                    .foregroundColor(OPSStyle.Layout.SearchField.iconColor)

                TextField("Search projects...", text: $searchText)
                    .font(OPSStyle.Layout.SearchField.textFont)
                    .foregroundColor(OPSStyle.Layout.SearchField.textColor)
                    .autocorrectionDisabled(true)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
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

            // Filter button
            Button(action: { showFilterSheet = true }) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: OPSStyle.Icons.filter)
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(hasActiveFilters ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )

                    if activeFilterCount > 0 {
                        Text("\(activeFilterCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .frame(width: 18, height: 18)
                            .background(OPSStyle.Colors.primaryAccent)
                            .clipShape(Circle())
                            .offset(x: 6, y: -6)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Group Toggle

    private var groupToggleRow: some View {
        HStack {
            Text("Group by Project")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            Toggle("", isOn: $groupByProject)
                .labelsHidden()
                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.primaryAccent))
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Summary

    private var summaryRow: some View {
        HStack {
            let projectCount = Set(filteredPhotoItems.map { $0.projectId }).count
            Text("\(filteredPhotoItems.count) PHOTOS \u{00B7} \(projectCount) PROJECTS")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Month Section

    private func monthSection(_ group: PhotoMonthGroup) -> some View {
        let isExpanded = expandedMonths.contains(group.id)

        return VStack(spacing: 12) {
            // Month header — tappable to toggle
            HStack {
                Text(group.label)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Rectangle()
                    .fill(OPSStyle.Colors.separator)
                    .frame(height: 1)

                Text("\(group.photos.count)")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.horizontal, 20)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        expandedMonths.remove(group.id)
                    } else {
                        expandedMonths.insert(group.id)
                    }
                }
            }

            if isExpanded {
                if groupByProject {
                    // Sub-group by project
                    ForEach(group.projectGroups, id: \.projectId) { projectGroup in
                        projectSubSection(
                            projectId: projectGroup.projectId,
                            title: projectGroup.projectTitle,
                            photos: projectGroup.photos
                        )
                    }
                } else {
                    // Flat photo grid
                    photoGrid(group.photos)
                        .padding(.horizontal, 20)
                }
            }
        }
    }

    // MARK: - Project Sub-Section (collapsible)

    private func projectSubSection(projectId: String, title: String, photos: [PhotoItem]) -> some View {
        let isExpanded = expandedProjects.contains(projectId)
        let project = allProjects.first(where: { $0.id == projectId })
        let subtitle = projectCardSubtitle(project)

        return VStack(spacing: 0) {
            // Card header
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("[ \(title.uppercased()) ]")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Text("[ \(photos.count) ]")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Image(systemName: OPSStyle.Icons.chevronDown)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .rotationEffect(.degrees(isExpanded ? 0 : -90))
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if isExpanded {
                        expandedProjects.remove(projectId)
                    } else {
                        expandedProjects.insert(projectId)
                    }
                }
            }

            if isExpanded {
                OPSStyle.Colors.separator
                    .frame(height: 1)
                    .padding(.horizontal, 14)

                photoGrid(photos)
                    .padding(14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
    }

    private func projectCardSubtitle(_ project: Project?) -> String {
        guard let project = project else { return "" }
        var parts: [String] = []
        if let clientName = project.client?.name, !clientName.isEmpty {
            parts.append(clientName)
        }
        if let address = project.address, !address.isEmpty {
            parts.append(address)
        }
        return parts.joined(separator: " \u{00B7} ")
    }

    // MARK: - Photo Grid

    private func photoGrid(_ photos: [PhotoItem]) -> some View {
        LazyVGrid(columns: columns, spacing: 2) {
            ForEach(photos) { item in
                photoCell(item, inGroup: photos)
            }
        }
    }

    private func photoCell(_ item: PhotoItem, inGroup: [PhotoItem]) -> some View {
        let isOnDevice = downloadManager.isOnDevice(item.url)
        let isDownloading = downloadManager.activeDownloads[item.url] != nil
        let isSelected = selectedPhotos.contains(item.id)

        return ZStack(alignment: .bottomTrailing) {
            if isOnDevice {
                // On-device: show real thumbnail
                PhotoThumbnail(url: item.url, project: nil)
            } else if isDownloading {
                // Downloading: placeholder + progress
                ZStack {
                    OPSStyle.Colors.cardBackgroundDark
                    ProgressView()
                        .tint(OPSStyle.Colors.secondaryText)
                }
            } else {
                // Remote: dark placeholder + cloud icon
                ZStack(alignment: .bottomTrailing) {
                    OPSStyle.Colors.cardBackgroundDark

                    Image(systemName: "icloud.and.arrow.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(6)
                }
            }

            // Select mode checkmark
            if isSelectMode {
                ZStack {
                    if isSelected {
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 22, height: 22)

                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Circle()
                            .stroke(OPSStyle.Colors.primaryText.opacity(0.6), lineWidth: 1.5)
                            .frame(width: 22, height: 22)
                            .background(Circle().fill(Color.black.opacity(0.3)))
                    }
                }
                .padding(6)
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectMode {
                if isSelected {
                    selectedPhotos.remove(item.id)
                } else {
                    selectedPhotos.insert(item.id)
                }
            } else {
                // Open viewer with all photos in current filtered set that are on-device
                let viewablePhotos = filteredPhotoItems.filter { downloadManager.isOnDevice($0.url) || $0.id == item.id }
                if let viewerIndex = viewablePhotos.firstIndex(where: { $0.id == item.id }) {
                    selectedPhotoContext = GalleryPhotoContext(
                        photos: viewablePhotos,
                        index: viewerIndex
                    )
                }
            }
        }
        .accessibilityLabel(isOnDevice ? "Photo from \(item.projectTitle)" : "Photo not downloaded")
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Storage Row

    private var storageRow: some View {
        let onDevice = downloadManager.onDeviceCount(from: allPhotoURLs)
        let total = allPhotoURLs.count
        let bytes = downloadManager.estimateStorageBytes(urls: allPhotoURLs.filter { downloadManager.isOnDevice($0) })

        return VStack(spacing: 8) {
            OPSStyle.Colors.separator
                .frame(height: 1)
                .padding(.horizontal, 20)

            Button(action: { showStorageManagement = true }) {
                HStack {
                    Text("\(onDevice)/\(total) on device \u{00B7} \(PhotoDownloadManager.formatBytes(bytes))")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    Spacer()

                    Text("Manage")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
    }

    // MARK: - Select Mode Header

    private var selectModeHeader: some View {
        HStack {
            Button(action: {
                isSelectMode = false
                selectedPhotos.removeAll()
            }) {
                Text("Cancel")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Text("\(selectedPhotos.count) Selected")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Spacer()

            // Balance spacer
            Spacer().frame(width: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Select Toolbar

    private var selectToolbar: some View {
        HStack(spacing: OPSStyle.Layout.spacing4) {
            Button(action: shareSelectedPhotos) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                    Text("Share")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
            }

            Spacer()

            Button(action: saveSelectedToDevice) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                    Text("Save to Device")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: 1),
            alignment: .top
        )
    }

    // MARK: - Empty States

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO PHOTOS YET")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Text("Photos from your projects will appear here.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    private var filteredEmptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO MATCHING PHOTOS")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Button(action: clearAllFilters) {
                Text("Clear Filters")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
    }

    // MARK: - Actions

    private func clearAllFilters() {
        searchText = ""
        filterUploaderIds.removeAll()
        filterDateFrom = nil
        filterDateTo = nil
        filterTaskTypeIds.removeAll()
        filterProjectIds.removeAll()
    }

    private func shareSelectedPhotos() {
        let images: [UIImage] = selectedPhotos.compactMap { photoId in
            guard let item = filteredPhotoItems.first(where: { $0.id == photoId }) else { return nil }
            return ImageFileManager.shared.loadImage(localID: item.url) ??
                   ImageFileManager.shared.loadImage(localID: item.url.hasPrefix("//") ? "https:" + item.url : item.url)
        }
        guard !images.isEmpty else { return }

        let activityVC = UIActivityViewController(activityItems: images, applicationActivities: nil)
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            var topController = window.rootViewController
            while let presented = topController?.presentedViewController {
                topController = presented
            }
            topController?.present(activityVC, animated: true)
        }
    }

    private func saveSelectedToDevice() {
        for photoId in selectedPhotos {
            guard let item = filteredPhotoItems.first(where: { $0.id == photoId }) else { continue }
            if let image = ImageFileManager.shared.loadImage(localID: item.url) ??
                          ImageFileManager.shared.loadImage(localID: item.url.hasPrefix("//") ? "https:" + item.url : item.url) {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            }
        }
        // Exit select mode after save
        isSelectMode = false
        selectedPhotos.removeAll()
    }
}

// MARK: - Gallery Photo Context

struct GalleryPhotoContext: Identifiable {
    let id = UUID()
    let photos: [PhotoItem]
    let index: Int
}
