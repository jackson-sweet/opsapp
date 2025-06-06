//
//  ProjectActionBar.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI
import PhotosUI
import UIKit

struct ProjectActionBar: View {
    let project: Project
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var appState: AppState
    
    // State variables for various sheets and actions
    @State private var showCompleteConfirmation = false
    // @State private var showReceiptScanner = false - Removed as part of shelving expense functionality
    @State private var showProjectDetails = false
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImage = false
    
    // Receipt scanner state - Keeping but not using (for future reference)
    // These properties are kept but commented out as they may be needed when expense functionality is added back
    // @State private var receiptAmount: String = ""
    // @State private var receiptDescription: String = ""
    // @State private var receiptImage: UIImage?
    
    var body: some View {
        // Blurred background similar to tab bar
        ZStack {
            // Blur effect
            BlurView(style: .systemThinMaterialDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius * 2)
            
            // Semi-transparent overlay
            Color(OPSStyle.Colors.cardBackgroundDark)
                .opacity(0.3)
                .cornerRadius(OPSStyle.Layout.cornerRadius * 2)
            
            // Actions with dividers
            HStack(spacing: 0) {
                ForEach(Array(ProjectAction.allCases.enumerated()), id: \.element) { index, action in
                    // Action button
                    Button(action: {
                        handleAction(action)
                    }) {
                        VStack(spacing: 4) {
                            Image(systemName: action.iconName)
                                .font(.system(size: 24))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                            
                            Text(action.label.uppercased())
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    // Vertical divider between buttons (not after last one)
                    if index < ProjectAction.allCases.count - 1 {
                        Rectangle()
                            .fill(OPSStyle.Colors.tertiaryText.opacity(0.3))
                            .frame(width: 1, height: 40)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .contentMargins(.bottom, 90)
        // Complete Project Confirmation
        .alert(isPresented: $showCompleteConfirmation) {
            Alert(
                title: Text("Complete Project"),
                message: Text("Are you sure you want to mark this project as complete?"),
                primaryButton: .default(Text("Complete")) {
                    updateProjectStatus(.completed)
                },
                secondaryButton: .cancel()
            )
        }
        // Receipt Scanner Sheet - Removed as part of shelving expense functionality
        // .sheet(isPresented: $showReceiptScanner) {
        //     ReceiptScannerView(project: project)
        // }
        // Project Details Sheet
        .sheet(isPresented: $showProjectDetails) {
            NavigationView {
                ProjectDetailsView(project: project)
            }
        }
        // Photo Picker for project photos - modified to use both camera and library
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(
                images: $selectedImages,
                allowsEditing: true,
                sourceType: .both, // Allow user to choose between camera and library
                selectionLimit: 10, // Allow multiple photos
                onSelectionComplete: {
                    // Process images immediately when selection is complete
                    if !selectedImages.isEmpty {
                        addPhotosToProject()
                    }
                }
            )
        }
        // Loading overlay when processing image
        .overlay(
            Group {
                if processingImage {
                    ZStack {
                        Color.black.opacity(0.7)
                        VStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            Text("Processing image...")
                                .foregroundColor(.white)
                                .padding(.top, 10)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 80)
                    .padding(.horizontal, 20)
                    .cornerRadius(OPSStyle.Layout.cornerRadius * 2)
                }
            }
        )
    }
    
    private func handleAction(_ action: ProjectAction) {
        switch action {
        case .complete:
            // Directly mark the project as completed
            markProjectComplete()
        // case .receipt: - Removed as part of shelving expense functionality
        //    showReceiptScanner = true
        case .details:
            // Show project details
            showProjectDetails = true
        case .photo:
            // Take a photo for the project
            showImagePicker = true
        }
    }
    
    // Mark project as complete
    private func markProjectComplete() {
        // Show a simple confirmation dialog
        showCompleteConfirmation = true
    }
    
    private func updateProjectStatus(_ status: Status) {
        Task {
            // Update project status and exit project mode when completed
            // Always force sync for user-initiated status changes in the UI
            dataController.syncManager.updateProjectStatus(
                projectId: project.id,
                status: status,
                forceSync: true // Always force sync for manual status changes
            )
            
            // If marking as complete, exit project mode after a short delay
            if status == .completed {
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                appState.exitProjectMode()
            }
        }
    }
    
    private func addPhotosToProject() {
        // Start loading indicator
        processingImage = true
        
        // Debug log
        print("ProjectActionBar: Starting to process \(selectedImages.count) images")
        
        Task {
            do {
                // Use ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {
                    print("ProjectActionBar: Using ImageSyncManager for \(selectedImages.count) images")
                    
                    // Process all images through the ImageSyncManager
                    let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                    
                    if !urls.isEmpty {
                        // Add URLs to project
                        await MainActor.run {
                            var currentImages = project.getProjectImages()
                            print("ProjectActionBar: Current images count before: \(currentImages.count)")
                            currentImages.append(contentsOf: urls)
                            print("ProjectActionBar: Current images count after: \(currentImages.count)")
                            
                            project.setProjectImageURLs(currentImages)
                            project.needsSync = true
                            project.syncPriority = 2 // Higher priority for image changes
                            
                            // Save changes
                            if let modelContext = dataController.modelContext {
                                do {
                                    try modelContext.save()
                                    print("ProjectActionBar: ✅ Saved all images to model context")
                                } catch {
                                    print("ProjectActionBar: ⚠️ Error saving to model context: \(error.localizedDescription)")
                                }
                            }
                            
                            // Reset state
                            selectedImages.removeAll()
                            processingImage = false
                        }
                    } else {
                        print("ProjectActionBar: ⚠️ No valid image URLs were returned")
                        await MainActor.run {
                            processingImage = false
                        }
                    }
                } else {
                    // Fallback to direct processing
                    print("ProjectActionBar: ⚠️ ImageSyncManager not available, using direct processing")
                    
                    // Process each image
                    for (index, image) in selectedImages.enumerated() {
                        // Debug log
                        print("ProjectActionBar: Processing image \(index + 1) of \(selectedImages.count)")
                        
                        // Compress image
                        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                            print("ProjectActionBar: ⚠️ Failed to compress image \(index + 1)")
                            continue
                        }
                        
                        // Generate a unique filename
                        let timestamp = Date().timeIntervalSince1970
                        let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                        
                        // Save image data to UserDefaults with the key as the URL
                        let localURL = "local://project_images/\(filename)"
                        
                        // Store the image in UserDefaults
                        if let imageBase64 = imageData.base64EncodedString() as String? {
                            UserDefaults.standard.set(imageBase64, forKey: localURL)
                            print("ProjectActionBar: Stored image data for: \(localURL)")
                            
                            // Add to project's images
                            await MainActor.run {
                                var currentImages = project.getProjectImages()
                                currentImages.append(localURL)
                                project.setProjectImageURLs(currentImages)
                                project.needsSync = true
                            }
                        }
                        
                        // Small delay to simulate upload process
                        if selectedImages.count > 1 {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds per image
                        }
                    }
                    
                    // Simulate upload delay for single image
                    if selectedImages.count == 1 {
                        try await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds
                    }
                    
                    // Save at the end with all changes
                    await MainActor.run {
                        if let modelContext = dataController.modelContext {
                            do {
                                try modelContext.save()
                                print("ProjectActionBar: ✅ Saved all images to model context")
                            } catch {
                                print("ProjectActionBar: ⚠️ Error saving to model context: \(error.localizedDescription)")
                            }
                        }
                        
                        print("ProjectActionBar: ✅ All images processed. Current images: \(project.getProjectImages().count)")
                        selectedImages.removeAll()
                        processingImage = false
                    }
                }
            } catch {
                print("ProjectActionBar: ❌ Error processing images: \(error.localizedDescription)")
                await MainActor.run {
                    processingImage = false
                }
            }
        }
    }
}

// MARK: - Project Actions Enum
enum ProjectAction: CaseIterable {
    case complete
    // case receipt - removed as part of shelving expense functionality
    case details
    case photo
    
    var iconName: String {
        switch self {
        case .complete: return "checkmark.circle"
        // case .receipt: return "doc.text.viewfinder" - removed
        case .details: return "info.circle" // Project details icon
        case .photo: return "camera"
        }
    }
    
    var label: String {
        switch self {
        case .complete: return "Complete"
        // case .receipt: return "Receipt" - removed
        case .details: return "Details"
        case .photo: return "Photo"
        }
    }
}

// MARK: - Receipt Scanner View - Coming Soon
struct ReceiptScannerView: View {
    let project: Project
    @Environment(\.presentationMode) var presentationMode
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                // Coming soon content
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "dollarsign.circle")
                        .font(.system(size: 80))
                        .foregroundColor(OPSStyle.Colors.primaryAccent.opacity(0.6))
                    
                    Text("COMING SOON")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                        .padding(.top, 24)
                    
                    Text("Expense tracking will be available in the next update")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // Feature preview section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PLANNED FEATURES")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        ReceiptFeatureItem(icon: "camera.fill", title: "Receipt scanning")
                        ReceiptFeatureItem(icon: "tag.fill", title: "Expense categorization")
                        ReceiptFeatureItem(icon: "chart.bar.fill", title: "Project expense reports")
                        ReceiptFeatureItem(icon: "arrow.up.arrow.down", title: "Sync with accounting software")
                    }
                    .padding(24)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                    .cornerRadius(12)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    
                    Spacer()
                }
            }
            .navigationTitle("Expense Tracking")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
        }
    }
}

// Helper view for feature items in the coming soon screen
private struct ReceiptFeatureItem: View {
    let icon: String
    let title: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24, height: 24)
            
            Text(title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

