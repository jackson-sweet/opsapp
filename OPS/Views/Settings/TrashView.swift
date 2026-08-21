//
//  TrashView.swift
//  OPS
//
//  Admin recovery ledger for soft-deleted projects, clients, and tasks.
//  Safe records restore inline. A task whose Project parent is also deleted
//  opens a quick view and restores both together so no orphan is produced.
//

import Foundation
import SwiftData
import SwiftUI
import UIKit

struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    @Query private var allProjects: [Project]
    @Query private var allClients: [Client]
    @Query private var allTasks: [ProjectTask]
    @Query private var allProjectPhotos: [ProjectPhoto]

    @State private var selectedSegment: TrashSegment = .projects
    @State private var selectedDescriptor: TrashRecoveryRowDescriptor?
    @State private var restoringID: String?
    @State private var restoreErrorMessage: String?
    @State private var toastErrorTrigger: String?

    private var deletedProjects: [Project] {
        allProjects
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var deletedClients: [Client] {
        allClients
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var deletedTasks: [ProjectTask] {
        allTasks
            .filter { $0.deletedAt != nil }
            .sorted { ($0.deletedAt ?? .distantPast) > ($1.deletedAt ?? .distantPast) }
    }

    private var descriptors: [TrashRecoveryRowDescriptor] {
        deletedProjects.map {
            .project($0, syncedPhotos: allProjectPhotos)
        } + deletedClients.map {
            .client($0)
        } + deletedTasks.map {
            .task($0, projects: allProjects, syncedPhotos: allProjectPhotos)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Trash",
                    onBackTapped: { dismiss() }
                )

                TrashRecoveryLedgerContent(
                    descriptors: descriptors,
                    selectedSegment: $selectedSegment,
                    restoringID: restoringID,
                    onSelect: select,
                    onRestore: restore
                )
            }
        }
        .trackScreen("Settings.Trash")
        .errorToast($toastErrorTrigger, label: Feedback.Err.restoreFailed)
        .sheet(item: $selectedDescriptor) { descriptor in
            TrashRecoveryQuickView(
                descriptor: descriptor,
                isRestoring: restoringID == descriptor.id,
                errorMessage: restoreErrorMessage,
                onRestore: { restore(descriptor) }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationBackground(OPSStyle.Colors.background)
        }
    }

    private func select(_ descriptor: TrashRecoveryRowDescriptor) {
        restoreErrorMessage = nil
        selectedDescriptor = descriptor
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private func restore(_ descriptor: TrashRecoveryRowDescriptor) {
        guard restoringID == nil else { return }
        restoringID = descriptor.id
        restoreErrorMessage = nil

        Task { @MainActor in
            defer { restoringID = nil }
            do {
                _ = try await dataController.restoreTrash(descriptor.plan)
                if selectedDescriptor?.id == descriptor.id {
                    selectedDescriptor = nil
                }
                ToastCenter.shared.present(Feedback.Settings.itemRestored)
            } catch {
                let message = error.localizedDescription
                if selectedDescriptor?.id == descriptor.id {
                    restoreErrorMessage = message
                } else {
                    toastErrorTrigger = message
                }
            }
        }
    }
}

// MARK: - Ledger content

struct TrashRecoveryLedgerContent: View {
    let descriptors: [TrashRecoveryRowDescriptor]
    @Binding var selectedSegment: TrashSegment
    let restoringID: String?
    let onSelect: (TrashRecoveryRowDescriptor) -> Void
    let onRestore: (TrashRecoveryRowDescriptor) -> Void

    private var visibleDescriptors: [TrashRecoveryRowDescriptor] {
        descriptors.filter { $0.segment == selectedSegment }
    }

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing2_5)

            if descriptors.isEmpty {
                TrashRecoveryEmptyState(segment: nil)
            } else if visibleDescriptors.isEmpty {
                TrashRecoveryEmptyState(segment: selectedSegment)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(visibleDescriptors.enumerated()), id: \.element.id) { index, descriptor in
                            TrashRecoveryRow(
                                descriptor: descriptor,
                                isRestoring: restoringID == descriptor.id,
                                restoreDisabled: restoringID != nil,
                                onSelect: { onSelect(descriptor) },
                                onRestore: { onRestore(descriptor) }
                            )

                            if index < visibleDescriptors.count - 1 {
                                Rectangle()
                                    .fill(OPSStyle.Colors.lineSoft)
                                    .frame(height: OPSStyle.Layout.Border.standard)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                    .glassSurface()
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var segmentPicker: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            ForEach(TrashSegment.allCases, id: \.self) { segment in
                let isSelected = selectedSegment == segment
                let appearance = TrashSegmentAppearance.resolve(isSelected: isSelected)
                Button {
                    selectedSegment = segment
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Text(segment.rawValue)
                            .font(OPSStyle.Typography.category)
                            .foregroundStyle(appearance.labelInk.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text("\(count(for: segment))")
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundStyle(appearance.countInk.color)
                            .padding(.horizontal, OPSStyle.Layout.spacing2)
                            .padding(.vertical, OPSStyle.Layout.spacing1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .fill(appearance.countFill.color)
                            )
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(appearance.segmentFill.color)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .strokeBorder(
                                isSelected ? OPSStyle.Colors.line : .clear,
                                lineWidth: OPSStyle.Layout.Border.standard
                            )
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(segment.rawValue), \(count(for: segment)) deleted")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(OPSStyle.Layout.spacing1)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(
                    OPSStyle.Colors.line,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
        )
    }

    private func count(for segment: TrashSegment) -> Int {
        descriptors.lazy.filter { $0.segment == segment }.count
    }
}

private extension TrashSegmentToken {
    var color: Color {
        switch self {
        case .clear: return .clear
        case .text: return OPSStyle.Colors.text
        case .text2: return OPSStyle.Colors.text2
        case .surfaceActive: return OPSStyle.Colors.surfaceActive
        case .fillNeutral: return OPSStyle.Colors.fillNeutral
        case .fillNeutralDim: return OPSStyle.Colors.fillNeutralDim
        case .opsAccent: return OPSStyle.Colors.opsAccent
        }
    }
}

// MARK: - Ledger row

private struct TrashRecoveryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let descriptor: TrashRecoveryRowDescriptor
    let isRestoring: Bool
    let restoreDisabled: Bool
    let onSelect: () -> Void
    let onRestore: () -> Void

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                    detailButton
                    actionButton
                        .frame(maxWidth: .infinity)
                }
            } else {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    detailButton
                    actionButton
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
    }

    private var detailButton: some View {
        Button(action: onSelect) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                TrashRecoveryThumbnailView(
                    source: descriptor.thumbnail,
                    title: descriptor.title
                )

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(descriptor.title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundStyle(OPSStyle.Colors.text)
                        .multilineTextAlignment(.leading)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 2)

                    ForEach(Array(descriptor.metadataLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(OPSStyle.Typography.metadata)
                            .monospacedDigit()
                            .foregroundStyle(OPSStyle.Colors.text3)
                            .multilineTextAlignment(.leading)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens recovery details")
    }

    private var actionButton: some View {
        let canRestoreInline = descriptor.plan.availability == .ready
        let label = canRestoreInline ? "RESTORE" : "REVIEW"
        return Button {
            if canRestoreInline { onRestore() } else { onSelect() }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isRestoring {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(OPSStyle.Colors.text2)
                } else {
                    Image(systemName: canRestoreInline ? OPSStyle.Icons.undo : OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                }
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
            }
            .foregroundStyle(canRestoreInline ? OPSStyle.Colors.text2 : OPSStyle.Colors.text3)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .padding(.horizontal, OPSStyle.Layout.spacing2_5)
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .strokeBorder(
                        OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(restoreDisabled)
        .accessibilityLabel(
            canRestoreInline
                ? "Restore \(descriptor.kind.rawValue) \(descriptor.title)"
                : "Review restore requirements for \(descriptor.title)"
        )
    }

    private var accessibilityLabel: String {
        ([descriptor.kind.authorityLabel, descriptor.title] + descriptor.metadataLines)
            .joined(separator: ", ")
    }
}

// MARK: - Thumbnail

private struct TrashRecoveryThumbnailView: View {
    let source: TrashRecoveryThumbnailSource
    let title: String
    var size: CGFloat = OPSStyle.Layout.touchTargetMin

    @State private var image: UIImage?

    var body: some View {
        Group {
            if source.isCircular {
                thumbnailContent.clipShape(Circle())
            } else {
                thumbnailContent.clipShape(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                )
            }
        }
        .frame(width: size, height: size)
        .overlay {
            if source.isCircular {
                Circle().strokeBorder(
                    OPSStyle.Colors.nestedBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
            } else {
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .strokeBorder(
                        OPSStyle.Colors.nestedBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            }
        }
        .accessibilityHidden(true)
        .task(id: source.urlString) {
            await loadImage()
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        ZStack {
            OPSStyle.Colors.surfaceActive
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .regular))
                    .foregroundStyle(OPSStyle.Colors.text2)
            }
        }
        .frame(width: size, height: size)
        .clipped()
    }

    private var fallbackIcon: String {
        switch source {
        case .projectPhoto, .fallback(.project): return OPSStyle.Icons.project
        case .clientProfile, .fallback(.client): return OPSStyle.Icons.client
        case .fallback(.task): return OPSStyle.Icons.task
        }
    }

    @MainActor
    private func loadImage() async {
        image = nil
        guard let rawURL = source.urlString else { return }

        if let cached = ImageCache.shared.get(forKey: rawURL) {
            image = cached
            return
        }
        if let local = ImageFileManager.shared.loadImage(localID: rawURL) {
            ImageCache.shared.set(local, forKey: rawURL)
            image = local
            return
        }
        if !rawURL.contains("/"), !rawURL.contains(":"), let asset = UIImage(named: rawURL) {
            image = asset
            return
        }

        let normalized = rawURL.hasPrefix("//") ? "https:\(rawURL)" : rawURL
        guard !normalized.hasPrefix("local://"), let url = URL(string: normalized) else { return }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return
            }
            guard let loaded = UIImage(data: data) else { return }
            ImageCache.shared.set(loaded, forKey: rawURL)
            _ = ImageFileManager.shared.saveImage(data: data, localID: rawURL)
            image = loaded
        } catch {
            // The truthful fallback remains visible; a thumbnail failure never
            // blocks inspection or restore.
        }
    }
}

// MARK: - Empty state

private struct TrashRecoveryEmptyState: View {
    let segment: TrashSegment?

    var body: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Spacer(minLength: 0)
            Text(segment == nil ? "0" : "—")
                .font(OPSStyle.Typography.heroNumberCondensed)
                .monospacedDigit()
                .foregroundStyle(OPSStyle.Colors.text3)
            Text(emptyLabel)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundStyle(OPSStyle.Colors.textMute)
                .multilineTextAlignment(.center)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .accessibilityElement(children: .combine)
    }

    private var emptyLabel: String {
        guard let segment else { return "// NO DELETED RECORDS" }
        return "// NO DELETED \(segment.rawValue)"
    }
}

// MARK: - Quick view

struct TrashRecoveryQuickView: View {
    @Environment(\.dismiss) private var dismiss

    let descriptor: TrashRecoveryRowDescriptor
    let isRestoring: Bool
    let errorMessage: String?
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header
                quickViewMedia
                detailLedger
                dependencyState
                if let errorMessage { restoreError(errorMessage) }
                restoreButton
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing4)
            .padding(.bottom, OPSStyle.Layout.spacing5)
        }
        .scrollIndicators(.hidden)
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .accessibilityAction(.escape) { dismiss() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(descriptor.title.uppercased())
                .font(OPSStyle.Typography.section)
                .foregroundStyle(OPSStyle.Colors.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(descriptor.kind.authorityLabel)
                .font(OPSStyle.Typography.tagLabel)
                .foregroundStyle(OPSStyle.Colors.text2)
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .padding(.vertical, OPSStyle.Layout.spacing1)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .fill(OPSStyle.Colors.fillNeutralDim)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .strokeBorder(
                            OPSStyle.Colors.line,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
    }

    private var quickViewMedia: some View {
        let media = TrashRecoveryQuickViewMedia(descriptor: descriptor)
        return HStack {
            TrashRecoveryThumbnailView(
                source: media.source,
                title: media.title,
                size: OPSStyle.Layout.touchTargetLarge
            )
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Representative image for \(media.title)")
    }

    private var detailLedger: some View {
        VStack(spacing: 0) {
            ForEach(Array(descriptor.details.enumerated()), id: \.element.id) { index, detail in
                HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing3) {
                    Text(detail.label)
                        .font(OPSStyle.Typography.metadata)
                        .foregroundStyle(OPSStyle.Colors.text3)
                        .frame(minWidth: OPSStyle.Layout.touchTargetLarge, alignment: .leading)

                    Text(detail.value)
                        .font(OPSStyle.Typography.body)
                        .foregroundStyle(OPSStyle.Colors.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)

                if index < descriptor.details.count - 1 {
                    Rectangle()
                        .fill(OPSStyle.Colors.lineSoft)
                        .frame(height: OPSStyle.Layout.Border.standard)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                }
            }
        }
        .glassSurface()
    }

    @ViewBuilder
    private var dependencyState: some View {
        switch descriptor.plan.availability {
        case .ready:
            EmptyView()
        case .parentRequired(let parent):
            recoveryNotice(
                label: "// PARENT ALSO DELETED",
                message: "\(descriptor.title) belongs to deleted \(parent.kind.rawValue) \(parent.title). Restore both to keep the link intact.",
                tone: .warning
            )
        case .unsupported(.projectNotOnDevice):
            recoveryNotice(
                label: "// PROJECT NOT ON DEVICE",
                message: "Sync this account before restoring the task. The project link stays protected.",
                tone: .error
            )
        }
    }

    private func restoreError(_ message: String) -> some View {
        recoveryNotice(
            label: Feedback.Err.restoreFailed,
            message: message,
            tone: .error
        )
    }

    private enum NoticeTone {
        case warning
        case error

        var text: Color {
            switch self {
            case .warning: return OPSStyle.Colors.tanTextM
            case .error: return OPSStyle.Colors.roseTextM
            }
        }

        var fill: Color {
            switch self {
            case .warning: return OPSStyle.Colors.tanFillM
            case .error: return OPSStyle.Colors.roseFillM
            }
        }

        var line: Color {
            switch self {
            case .warning: return OPSStyle.Colors.tanLineM
            case .error: return OPSStyle.Colors.roseLineM
            }
        }
    }

    private func recoveryNotice(label: String, message: String, tone: NoticeTone) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.panelTitle)
                .foregroundStyle(tone.text)
            Text(message)
                .font(OPSStyle.Typography.body)
                .foregroundStyle(OPSStyle.Colors.text2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .fill(tone.fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                .strokeBorder(tone.line, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var restoreButton: some View {
        let canRestore = descriptor.plan.isRestorable
        return Button(action: onRestore) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                if isRestoring {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(OPSStyle.Colors.invertedText)
                }
                Text(descriptor.plan.actionLabel)
                    .font(OPSStyle.Typography.buttonLabel)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(canRestore ? OPSStyle.Colors.invertedText : OPSStyle.Colors.text3)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.bottomCTAHeight)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .fill(canRestore ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.surfaceActive)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                    .strokeBorder(
                        canRestore ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(.plain)
        .disabled(!canRestore || isRestoring)
    }
}
