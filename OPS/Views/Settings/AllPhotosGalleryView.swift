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
    /// Pre-computed lowercased blob of every project field the user might
    /// search against (title, client name, address, description, notes,
    /// status, task type names). Built once at construction time so the
    /// filter pass is a single substring check instead of N field lookups.
    let searchHaystack: String

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
    @State private var showFirstVisitInfo = false
    @AppStorage("photosGalleryFirstVisitDone") private var firstVisitDone = false

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
                let haystack = Self.buildSearchHaystack(for: project)
                return project.getProjectImages().map { url in
                    let annotation = annotationMap[url]?.first(where: { $0.projectId == project.id }) ?? annotationMap[url]?.first
                    let noteText = annotation?.note.isEmpty == false ? annotation?.note : nil
                    // Fold the photo's annotation note into the haystack
                    // so a comment typed on one specific photo is still
                    // searchable alongside the project-level fields.
                    let perPhotoHaystack: String
                    if let noteText = noteText {
                        perPhotoHaystack = haystack + " " + noteText.lowercased()
                    } else {
                        perPhotoHaystack = haystack
                    }
                    return PhotoItem(
                        id: "\(project.id)-\(url)",
                        url: url,
                        projectId: project.id,
                        projectTitle: project.title,
                        date: annotation?.createdAt ?? project.startDate ?? Date(),
                        authorId: annotation?.authorId,
                        note: noteText,
                        searchHaystack: perPhotoHaystack
                    )
                }
            }
            .sorted { $0.date > $1.date }
    }

    /// Collect every project field worth searching for the photo gallery's
    /// free-text search, lowercased and joined into a single blob. Called
    /// once per project during item construction so each filter pass is
    /// a single `contains` check instead of N field lookups.
    private static func buildSearchHaystack(for project: Project) -> String {
        var parts: [String] = []
        parts.append(project.title)
        parts.append(project.effectiveClientName)
        if let address = project.address, !address.isEmpty { parts.append(address) }
        if let notes = project.notes, !notes.isEmpty { parts.append(notes) }
        if let description = project.projectDescription, !description.isEmpty { parts.append(description) }
        parts.append(project.status.rawValue)
        // Task type display names on the project are a common lookup target
        // (e.g. searching for "rail" to find all projects with rail tasks).
        for task in project.tasks where task.deletedAt == nil {
            if let typeName = task.taskType?.display { parts.append(typeName) }
            if let customTitle = task.customTitle, !customTitle.isEmpty { parts.append(customTitle) }
        }
        return parts.joined(separator: " ").lowercased()
    }

    /// Apply search and filters
    private var filteredPhotoItems: [PhotoItem] {
        var items = allPhotoItems

        // Search filter — matches against the pre-built haystack so any
        // relevant project field (title, client, address, notes, status,
        // task types) or per-photo annotation note can surface results.
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            items = items.filter { $0.searchHaystack.contains(query) }
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

                if allPhotoItems.isEmpty {
                    // No photos at all — no search bar because there's nothing to search
                    emptyState
                } else {
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing3) {
                            // Search + filter row — always visible so the
                            // user can refine or clear their search without
                            // the no-results state hijacking the whole view.
                            searchFilterRow

                            if filteredPhotoItems.isEmpty {
                                // Inline no-results card: keeps the search
                                // field in place and shows the exact query
                                // that came up empty, so the user can just
                                // edit the text instead of bouncing back.
                                inlineNoResultsCard
                            } else {
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

            // Show first-visit info popup explaining defaults
            if !firstVisitDone {
                firstVisitDone = true
                // Slight delay so the view renders before showing the popup
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    showFirstVisitInfo = true
                }
            }
        }
        .alert("Photo Storage Defaults", isPresented: $showFirstVisitInfo) {
            Button("Got It") { }
        } message: {
            Text("Photos from your projects are stored in the cloud. By default, recent photos (last 3 months) are cached on your device for quick access.\n\nYou can pin specific photos to keep them downloaded, or enable \"Keep All Photos Downloaded\" to always have every photo available offline.\n\nManage storage anytime from the bottom of this screen.")
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Group Toggle

    private var groupToggleRow: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack {
                Text("Group by Project")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                Spacer()

                Toggle("", isOn: $groupByProject)
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
            }

            // "Keep All Photos Downloaded" toggle removed — photo caching is
            // now capacity-based. Manage via Settings → Photo Storage.
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Month Section

    private func monthSection(_ group: PhotoMonthGroup) -> some View {
        let isExpanded = expandedMonths.contains(group.id)

        return VStack(spacing: OPSStyle.Layout.spacing2_5) {
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
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OPSStyle.Animation.standard) {
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
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
            HStack(spacing: OPSStyle.Layout.spacing2) {
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
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(OPSStyle.Animation.standard) {
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
        let isPinned = downloadManager.isPinned(item.url)

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

            // Pinned indicator — bottom-leading, only in normal mode
            if isPinned && !isSelectMode {
                Image(systemName: "pin.fill")
                    .font(.system(size: 9))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(OPSStyle.Layout.spacing1)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                    .padding(OPSStyle.Layout.spacing1)
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

        return VStack(spacing: OPSStyle.Layout.spacing2) {
            OPSStyle.Colors.separator
                .frame(height: 1)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)

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
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Select Toolbar

    private var selectToolbar: some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            Button(action: shareSelectedPhotos) {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                    Text("Share")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Button(action: keepSelectedDownloaded) {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                    Text("Keep Downloaded")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)

            Spacer()

            Button(action: saveSelectedToDevice) {
                VStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                    Text("Save to Device")
                        .font(OPSStyle.Typography.smallCaption)
                }
                .foregroundColor(OPSStyle.Colors.primaryText)
            }
            .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    /// Inline no-results card rendered beneath the search bar so the user
    /// never loses the ability to edit their query. Echoes the exact search
    /// term back to them and exposes a Clear action in the same tap target.
    private var inlineNoResultsCard: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            if !searchText.isEmpty {
                Text("NO RESULTS FOR \"\(searchText.uppercased())\"")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("NO MATCHING PHOTOS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            if hasActiveFilters || !searchText.isEmpty {
                Button(action: clearAllFilters) {
                    Text("CLEAR")
                        .font(OPSStyle.Typography.smallCaption)
                        .tracking(0.8)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                        .padding(.horizontal, 14)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 1)
                        )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing4)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
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

    /// Pin selected photos so they stay on-device even after auto-keep policy cleanup.
    /// Also downloads any that are not yet on-device.
    private func keepSelectedDownloaded() {
        let selectedItems = selectedPhotos.compactMap { photoId in
            filteredPhotoItems.first(where: { $0.id == photoId })
        }
        let urls = selectedItems.map { $0.url }

        // Pin all selected URLs
        downloadManager.pinAll(urls)

        // Download any that are not yet on device
        Task {
            for url in urls where !downloadManager.isOnDevice(url) {
                await downloadManager.downloadPhoto(url)
            }
        }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        // Exit select mode
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
