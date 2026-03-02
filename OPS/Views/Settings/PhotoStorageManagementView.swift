//
//  PhotoStorageManagementView.swift
//  OPS
//

import SwiftUI

struct PhotoStorageManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var downloadManager = PhotoDownloadManager.shared

    let allPhotoItems: [PhotoItem]
    let allProjects: [Project]

    @State private var showClearConfirmation = false

    private var projectBreakdown: [(project: Project, photos: [String], onDeviceCount: Int)] {
        allProjects
            .compactMap { project -> (project: Project, photos: [String], onDeviceCount: Int)? in
                let photos = project.getProjectImages()
                guard !photos.isEmpty else { return nil }
                let onDevice = downloadManager.onDeviceCount(from: photos)
                return (project: project, photos: photos, onDeviceCount: onDevice)
            }
            .sorted { $0.project.title.localizedCaseInsensitiveCompare($1.project.title) == .orderedAscending }
    }

    private var totalOnDevice: Int {
        downloadManager.onDeviceCount(from: allPhotoItems.map { $0.url })
    }

    private var totalPhotos: Int {
        allPhotoItems.count
    }

    private var totalBytes: Int64 {
        downloadManager.estimateStorageBytes(urls: allPhotoItems.map { $0.url }.filter { downloadManager.isOnDevice($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        // Summary
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("[ ON DEVICE ]")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("\(totalOnDevice) of \(totalPhotos) photos \u{00B7} \(PhotoDownloadManager.formatBytes(totalBytes))")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)

                        // Auto-keep policy
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("[ AUTO-KEEP ]")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("Automatically keep photos on device from:")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            VStack(spacing: 4) {
                                ForEach(PhotoDownloadManager.KeepPolicy.allCases, id: \.rawValue) { policy in
                                    Button(action: { downloadManager.keepPolicy = policy }) {
                                        HStack {
                                            Text(policy.rawValue)
                                                .font(OPSStyle.Typography.body)
                                                .foregroundColor(OPSStyle.Colors.primaryText)

                                            Spacer()

                                            if downloadManager.keepPolicy == policy {
                                                Image(systemName: OPSStyle.Icons.checkmark)
                                                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                                                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PlainButtonStyle())

                                    if policy != PhotoDownloadManager.KeepPolicy.allCases.last {
                                        OPSStyle.Colors.separator
                                            .frame(height: 1)
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
                        .padding(.horizontal, 20)

                        // Per-project breakdown
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                            Text("[ BY PROJECT ]")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            VStack(spacing: 0) {
                                ForEach(projectBreakdown, id: \.project.id) { item in
                                    VStack(spacing: 8) {
                                        HStack {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(item.project.title)
                                                    .font(OPSStyle.Typography.body)
                                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                                    .lineLimit(1)

                                                let bytes = downloadManager.estimateStorageBytes(urls: item.photos.filter { downloadManager.isOnDevice($0) })
                                                Text("\(item.photos.count) photos \u{00B7} \(item.onDeviceCount) on device \u{00B7} \(PhotoDownloadManager.formatBytes(bytes))")
                                                    .font(OPSStyle.Typography.smallCaption)
                                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                                            }

                                            Spacer()

                                            if item.onDeviceCount == item.photos.count {
                                                Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                                    .foregroundColor(OPSStyle.Colors.successStatus)
                                            } else {
                                                Button(action: {
                                                    Task { await downloadManager.downloadAllForProject(item.photos) }
                                                }) {
                                                    Text("Download")
                                                        .font(OPSStyle.Typography.smallCaption)
                                                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                                                        .padding(.horizontal, 12)
                                                        .padding(.vertical, 6)
                                                        .background(OPSStyle.Colors.cardBackgroundDark)
                                                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                                                        .overlay(
                                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.5), lineWidth: OPSStyle.Layout.Border.standard)
                                                        )
                                                }
                                            }
                                        }
                                        .padding(.vertical, 12)
                                        .padding(.horizontal, 16)
                                    }

                                    if item.project.id != projectBreakdown.last?.project.id {
                                        OPSStyle.Colors.separator
                                            .frame(height: 1)
                                            .padding(.leading, 16)
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
                        .padding(.horizontal, 20)

                        // Clear all
                        Button(action: { showClearConfirmation = true }) {
                            Text("Clear All Local Photos")
                                .font(OPSStyle.Typography.bodyBold)
                                .foregroundColor(OPSStyle.Colors.errorStatus)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .overlay(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
                                )
                        }
                        .padding(.horizontal, 20)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("PHOTO STORAGE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: OPSStyle.Icons.chevronLeft)
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
            .alert("Clear All Photos?", isPresented: $showClearConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Clear All", role: .destructive) {
                    downloadManager.clearAllCachedPhotos()
                }
            } message: {
                Text("This will remove all cached photos from your device. Photos will still be available in the cloud.")
            }
        }
    }
}
