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
    @State private var showReceiptScanner = false
    @State private var showProjectDetails = false
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImage = false
    
    // Receipt scanner state
    @State private var receiptAmount: String = ""
    @State private var receiptDescription: String = ""
    @State private var receiptImage: UIImage?
    
    var body: some View {
        // Semi-transparent background with blur
        ZStack {
            BlurView(style: .dark)
                .cornerRadius(50)
                .frame(width: 362, height: 85)
            
            HStack(spacing: 20) {
                ForEach(ProjectAction.allCases, id: \.self) { action in
                    Button(action: {
                        handleAction(action)
                    }) {
                        Image(systemName: action.iconName)
                            .font(.system(size: 24))
                            .foregroundColor(OPSStyle.Colors.secondaryAccent)
                            .frame(width: 72, height: 72)
                            .background(
                                Circle()
                                    .fill(OPSStyle.Colors.cardBackground)
                            )
                    }
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxHeight: 85)
        .frame(maxWidth: 362)
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
        // Receipt Scanner Sheet
        .sheet(isPresented: $showReceiptScanner) {
            ReceiptScannerView(project: project)
        }
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
                    .frame(width: 362, height: 85)
                    .cornerRadius(50)
                }
            }
        )
    }
    
    private func handleAction(_ action: ProjectAction) {
        switch action {
        case .complete:
            // Directly mark the project as completed
            markProjectComplete()
        case .receipt:
            // Show receipt scanner
            showReceiptScanner = true
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
            dataController.syncManager.updateProjectStatus(
                projectId: project.id,
                status: status
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
    case receipt
    case details
    case photo
    
    var iconName: String {
        switch self {
        case .complete: return "checkmark.circle"
        case .receipt: return "doc.text.viewfinder" // Receipt scanner icon
        case .details: return "info.circle" // Project details icon
        case .photo: return "camera"
        }
    }
    
    var label: String {
        switch self {
        case .complete: return "Complete"
        case .receipt: return "Receipt"
        case .details: return "Details"
        case .photo: return "Photo"
        }
    }
}

// MARK: - Receipt Scanner View
struct ReceiptScannerView: View {
    let project: Project
    @EnvironmentObject private var dataController: DataController
    @Environment(\.presentationMode) var presentationMode
    
    @State private var receiptAmount: String = ""
    @State private var receiptDescription: String = ""
    @State private var receiptDate: Date = Date()
    @State private var receiptImage: UIImage?
    @State private var showImagePicker = false
    @State private var processingReceipt = false
    
    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.backgroundGradient
                    .edgesIgnoringSafeArea(.all)
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Receipt Image Section
                        VStack(alignment: .center) {
                            if let image = receiptImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 200)
                                    .cornerRadius(8)
                                    .padding()
                                    .overlay(
                                        Button(action: {
                                            showImagePicker = true
                                        }) {
                                            Text("Change Photo")
                                                .font(.caption)
                                                .padding(8)
                                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
                                                .cornerRadius(8)
                                        }
                                        .padding(8),
                                        alignment: .bottomTrailing
                                    )
                            } else {
                                Button(action: {
                                    showImagePicker = true
                                }) {
                                    VStack(spacing: 16) {
                                        Image(systemName: "camera.fill")
                                            .font(.system(size: 40))
                                            .padding()
                                        
                                        Text("Take Receipt Photo")
                                            .font(.headline)
                                        
                                        Text("or choose from library")
                                            .font(.caption)
                                            .foregroundColor(Color.gray)
                                    }
                                    .frame(height: 200)
                                    .frame(maxWidth: .infinity)
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(8)
                                    .padding(.horizontal)
                                }
                                .foregroundColor(OPSStyle.Colors.secondaryAccent)
                            }
                        }
                        
                        // Receipt Details Form
                        VStack(alignment: .leading, spacing: 16) {
                            Text("EXPENSE DETAILS")
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .padding(.horizontal)
                            
                            // Amount
                            VStack(alignment: .leading) {
                                Text("Amount")
                                    .font(.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("$0.00", text: $receiptAmount)
                                    .keyboardType(.decimalPad)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal)
                            
                            // Description
                            VStack(alignment: .leading) {
                                Text("Description")
                                    .font(.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                TextField("Enter expense description", text: $receiptDescription)
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal)
                            
                            // Date
                            VStack(alignment: .leading) {
                                Text("Date")
                                    .font(.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                DatePicker("", selection: $receiptDate, displayedComponents: .date)
                                    .datePickerStyle(CompactDatePickerStyle())
                                    .labelsHidden()
                                    .padding()
                                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                    .cornerRadius(8)
                                    .foregroundColor(.white)
                            }
                            .padding(.horizontal)
                            
                            // Project - just show the current project
                            VStack(alignment: .leading) {
                                Text("Project")
                                    .font(.caption)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                
                                HStack {
                                    Text(project.title)
                                        .foregroundColor(.white)
                                    Spacer()
                                    
                                    // Status indicator
                                    Text(project.status.displayName)
                                        .font(.caption)
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(project.statusColor)
                                        .cornerRadius(4)
                                }
                                .padding()
                                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                                .cornerRadius(8)
                            }
                            .padding(.horizontal)
                        }
                        
                        // Submit Button
                        Button(action: {
                            saveReceipt()
                        }) {
                            if processingReceipt {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Text("Save Expense")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                        .padding()
                        .background(receiptImage != nil && !receiptAmount.isEmpty ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.inactiveStatus)
                        .cornerRadius(12)
                        .padding(.horizontal)
                        .disabled(receiptImage == nil || receiptAmount.isEmpty || processingReceipt)
                        .padding(.top, 20)
                    }
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("Add Expense")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            .sheet(isPresented: $showImagePicker) {
                // For receipt scanner, use both camera and library with preference for camera
                ImagePicker(
                    images: Binding<[UIImage]>(
                        get: { receiptImage != nil ? [receiptImage!] : [] },
                        set: { images in
                            if let first = images.first {
                                receiptImage = first
                            }
                        }
                    ), 
                    allowsEditing: true,
                    sourceType: .both, // Allow both camera and photo library
                    selectionLimit: 1, // Only one receipt image at a time
                    onSelectionComplete: {
                        // Nothing extra needed, binding handles updating receiptImage
                    }
                )
            }
        }
    }
    
    private func saveReceipt() {
        guard let image = receiptImage, let _ = Double(receiptAmount.replacingOccurrences(of: "$", with: "")) else {
            return
        }
        
        processingReceipt = true
        
        // Simulate saving the receipt
        Task {
            do {
                // Verify image can be compressed
                guard let _ = image.jpegData(compressionQuality: 0.7) else {
                    return
                }
                
                // Simulate delay for processing the receipt
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Generate a unique filename
                let _ = "receipt_\(project.id)_\(Date().timeIntervalSince1970).jpg"
                
                // In a real app, this would save to the database and sync
                // For this demo, we'll just simulate success
                
                await MainActor.run {
                    processingReceipt = false
                    presentationMode.wrappedValue.dismiss()
                }
            } catch {
                await MainActor.run {
                    processingReceipt = false
                }
            }
        }
    }
}

