//
//  ImageSyncProgressView.swift
//  OPS
//
//  Created by OPS Team.
//

import SwiftUI

struct ImageSyncProgressView: View {
    @ObservedObject var syncManager: ImageSyncProgressManager
    @State private var showingDetails = false
    
    var body: some View {
        if syncManager.isVisible {
            VStack(spacing: 0) {
                // Main progress bar
                HStack(spacing: 12) {
                    // Icon
                    Image(systemName: syncManager.hasError ? "exclamationmark.cloud.fill" : "icloud.and.arrow.up.fill")
                        .font(.system(size: 16))
                        .foregroundColor(syncManager.hasError ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent)
                    
                    // Progress info
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syncManager.statusText)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(.white)
                        
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                // Background
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))
                                    .frame(height: 4)
                                
                                // Progress
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(syncManager.hasError ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryAccent)
                                    .frame(width: geometry.size.width * syncManager.progress, height: 4)
                                    .animation(.easeInOut(duration: 0.3), value: syncManager.progress)
                            }
                        }
                        .frame(height: 4)
                    }
                    
                    Spacer()
                    
                    // Action button
                    Button(action: {
                        if syncManager.hasError {
                            syncManager.retrySync()
                        } else {
                            showingDetails.toggle()
                        }
                    }) {
                        Text(syncManager.hasError ? "Retry" : "\(syncManager.completedCount)/\(syncManager.totalCount)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    ZStack {
                        // Background blur
                        BlurView(style: .systemThinMaterialDark)
                        
                        // Overlay color
                        Color(OPSStyle.Colors.cardBackgroundDark)
                            .opacity(0.5)
                    }
                )
                
                // Expanded details (if showing)
                if showingDetails {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(syncManager.projectUploads) { upload in
                            HStack {
                                Image(systemName: upload.isComplete ? "checkmark.circle.fill" : 
                                               upload.hasError ? "xmark.circle.fill" : "circle")
                                    .font(.system(size: 14))
                                    .foregroundColor(upload.isComplete ? OPSStyle.Colors.successStatus :
                                                   upload.hasError ? OPSStyle.Colors.errorStatus :
                                                   OPSStyle.Colors.secondaryText)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(upload.projectName)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(.white)
                                    
                                    Text("\(upload.imageCount) images")
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                
                                Spacer()
                                
                                if upload.isUploading {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                                        .scaleEffect(0.8)
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 4)
                        }
                    }
                    .padding(.bottom, 8)
                    .background(Color(OPSStyle.Colors.cardBackgroundDark).opacity(0.9))
                }
            }
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: syncManager.isVisible)
        }
    }
}

// Progress manager for tracking image sync state
@MainActor
class ImageSyncProgressManager: ObservableObject {
    @Published var isVisible = false
    @Published var progress: Double = 0
    @Published var totalCount = 0
    @Published var completedCount = 0
    @Published var hasError = false
    @Published var statusText = "Syncing images..."
    @Published var projectUploads: [ProjectUploadStatus] = []
    
    private var syncManager: ImageSyncManager?
    
    struct ProjectUploadStatus: Identifiable {
        let id = UUID()
        let projectId: String
        let projectName: String
        let imageCount: Int
        var isComplete = false
        var hasError = false
        var isUploading = false
    }
    
    func startSync(with syncManager: ImageSyncManager, pendingUploads: [PendingImageUpload]) {
        self.syncManager = syncManager
        
        // Group uploads by project
        var uploadsByProject: [String: [PendingImageUpload]] = [:]
        for upload in pendingUploads {
            if uploadsByProject[upload.projectId] == nil {
                uploadsByProject[upload.projectId] = []
            }
            uploadsByProject[upload.projectId]?.append(upload)
        }
        
        // Create project upload status
        projectUploads = uploadsByProject.map { (projectId, uploads) in
            ProjectUploadStatus(
                projectId: projectId,
                projectName: "Project \(projectId.prefix(8))",
                imageCount: uploads.count
            )
        }
        
        totalCount = pendingUploads.count
        completedCount = 0
        progress = 0
        hasError = false
        statusText = "Syncing \(totalCount) images..."
        isVisible = true
        
        // Start the sync
        Task {
            await performSync()
        }
    }
    
    private func performSync() async {
        guard let syncManager = syncManager else { return }
        
        // Simulate progress for now (you'll need to integrate with actual sync progress)
        for i in 0..<projectUploads.count {
            projectUploads[i].isUploading = true
            
            // Simulate upload time
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            projectUploads[i].isUploading = false
            projectUploads[i].isComplete = true
            
            completedCount += projectUploads[i].imageCount
            progress = Double(completedCount) / Double(totalCount)
            
            if completedCount == totalCount {
                statusText = "All images synced"
                
                // Hide after a delay
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                isVisible = false
            } else {
                statusText = "Syncing images... \(completedCount)/\(totalCount)"
            }
        }
    }
    
    func retrySync() {
        hasError = false
        Task {
            await performSync()
        }
    }
    
    func showError(_ message: String) {
        hasError = true
        statusText = message
    }
    
    func hide() {
        isVisible = false
    }
}