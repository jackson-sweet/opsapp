//
//  ProjectDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-25.
//

import SwiftUI
import UIKit

struct ProjectDetailsView: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @State private var noteText: String
    @EnvironmentObject private var dataController: DataController
    @State private var showingPhotoViewer = false
    @State private var selectedPhotoIndex: Int = 0
    @State private var showingImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var processingImages = false
    @State private var showingDeleteConfirmation = false
    @State private var photoToDelete: String? = nil
    
    // Initialize with project's existing notes
    init(project: Project) {
        self.project = project
        self._noteText = State(initialValue: project.notes ?? "")
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Status badge
                StatusBadge(status: project.status)
                    .padding(.top, 4)
                
                // Project title
                Text(project.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                // Client info
                clientInfoSection
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Project description
                Text("PROJECT DETAILS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                Text(project.projectDescription ?? "No detailed description provided.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Notes section
                notesSection
                
                Divider()
                    .background(OPSStyle.Colors.secondaryText.opacity(0.3))
                
                // Project Photos Section
                Text("PHOTOS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                // Photo Carousel
                VStack(spacing: 12) {
                    let photos = project.getProjectImages()
                    
                    if photos.isEmpty {
                        // Empty state for no photos
                        VStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 32))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text("No photos added yet")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .frame(height: 180)
                        .frame(maxWidth: .infinity)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                        .cornerRadius(12)
                    } else {
                        // Scrollable carousel of photos
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                    ZStack {
                                        PhotoThumbnail(url: url)
                                            .frame(width: 120, height: 120)
                                            .cornerRadius(12)
                                            .contentShape(Rectangle())
                                            .onTapGesture {
                                                selectedPhotoIndex = index
                                                showingPhotoViewer = true
                                            }
                                            .onLongPressGesture {
                                                // Show delete confirmation
                                                photoToDelete = url
                                                showingDeleteConfirmation = true
                                            }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .frame(height: 120)
                    }
                    
                    // Add Photos Button
                    Button(action: {
                        showingImagePicker = true
                    }) {
                        HStack {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 20))
                            
                            Text("Add Photos")
                                .font(OPSStyle.Typography.body)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(OPSStyle.Colors.primaryAccent)
                        .foregroundColor(.white)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    .disabled(processingImages)
                    
                    // Loading indicator for processing images
                    if processingImages {
                        HStack {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            Text("Processing images...")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.top, 4)
                    }
                }
            }
            .padding()
        }
        .background(OPSStyle.Colors.background.edgesIgnoringSafeArea(.all))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") {
                    dismiss()
                }
                .foregroundColor(OPSStyle.Colors.secondaryAccent)
            }
        }
        // Full-screen photo viewer
        .fullScreenCover(isPresented: $showingPhotoViewer) {
            FullScreenPhotoViewer(
                photos: project.getProjectImages(),
                initialIndex: selectedPhotoIndex,
                onDismiss: { showingPhotoViewer = false }
            )
        }
        // Image picker for adding multiple photos
        .sheet(isPresented: $showingImagePicker) {
            ImagePicker(
                images: $selectedImages, 
                allowsEditing: false, 
                onSelectionComplete: {
                    // Process images immediately when selection is complete
                    if !selectedImages.isEmpty {
                        addPhotosToProject()
                    }
                }
            )
        }
        // Delete confirmation alert
        .alert("Delete Photo?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {
                photoToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let urlToDelete = photoToDelete {
                    deletePhoto(urlToDelete)
                }
            }
        } message: {
            Text("Are you sure you want to delete this photo? This action cannot be undone.")
        }
    }
    
    // Client info section
    private var clientInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CLIENT: \(project.clientName)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text("ADDRESS: \(project.address)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Text("SCHEDULED: \(project.formattedStartDate)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }
    
    // Notes section
    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NOTES")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            TextEditor(text: $noteText)
                .frame(minHeight: 120)
                .padding(8)
                .background(OPSStyle.Colors.cardBackground)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
            
            Button(action: saveNotes) {
                Text("SAVE NOTES")
                    .font(OPSStyle.Typography.bodyBold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(OPSStyle.Colors.secondaryAccent)
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
        }
    }
    
    private func saveNotes() {
        project.notes = noteText
        project.needsSync = true
        
        if let modelContext = dataController.modelContext {
            try? modelContext.save()
        }
    }
    
    // Function to add multiple photos to the project
    private func addPhotosToProject() {
        // Start loading indicator
        processingImages = true
        
        // Debug log
        print("Starting to process \(selectedImages.count) images")
        
        Task {
            do {
                // Use the ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {
                    // Process all images through the ImageSyncManager
                    let urls = await imageSyncManager.saveImages(selectedImages, for: project)
                    
                    if !urls.isEmpty {
                        // Add to project's images
                        var currentImages = project.getProjectImages()
                        print("Current images count before: \(currentImages.count)")
                        currentImages.append(contentsOf: urls)
                        print("Current images count after: \(currentImages.count)")
                        
                        // Use MainActor for UI updates and model changes
                        await MainActor.run {
                            project.setProjectImageURLs(currentImages)
                            print("Updated project image URLs")
                            
                            // Mark project for sync with priority
                            project.needsSync = true
                            project.syncPriority = 2 // Higher priority for image changes
                            
                            if let modelContext = dataController.modelContext {
                                do {
                                    try modelContext.save()
                                    print("✅ Saved to model context successfully")
                                } catch {
                                    print("⚠️ Error saving to model context: \(error.localizedDescription)")
                                }
                            } else {
                                print("⚠️ Model context is nil")
                            }
                            
                            // Clear selected images and hide loading
                            selectedImages.removeAll()
                            processingImages = false
                        }
                    } else {
                        print("⚠️ No valid image URLs were returned from ImageSyncManager")
                        await MainActor.run {
                            processingImages = false
                        }
                    }
                } else {
                    // Fallback to direct processing if ImageSyncManager is not available
                    print("⚠️ ImageSyncManager not available, using direct processing")
                    
                    // Process each image
                    for (index, image) in selectedImages.enumerated() {
                        // Debug log
                        print("Processing image \(index + 1) of \(selectedImages.count)")
                        
                        // Compress image
                        guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                            print("⚠️ Failed to compress image \(index + 1)")
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
                            print("ProjectDetailsView: Stored image data for: \(localURL)")
                            
                            // Add to project's images
                            var currentImages = project.getProjectImages()
                            currentImages.append(localURL)
                            
                            await MainActor.run {
                                project.setProjectImageURLs(currentImages)
                                project.needsSync = true
                            }
                        }
                        
                        // Small delay for UI responsiveness
                        if selectedImages.count > 1 {
                            try await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds per image
                        }
                    }
                    
                    // Save all changes
                    await MainActor.run {
                        if let modelContext = dataController.modelContext {
                            try? modelContext.save()
                        }
                        
                        // Clear selected images and hide loading
                        selectedImages.removeAll()
                        processingImages = false
                    }
                }
            } catch {
                // Handle error
                print("❌ Error processing images: \(error.localizedDescription)")
                await MainActor.run {
                    processingImages = false
                }
            }
        }
    }
    
    /// Delete a single photo from the project
    private func deletePhoto(_ url: String) {
        // Start a background task for deletion
        Task {
            do {
                print("ProjectDetailsView: Deleting photo: \(url)")
                
                // Get current project images
                var currentImages = project.getProjectImages()
                
                // Remove the specified image
                if let index = currentImages.firstIndex(of: url) {
                    currentImages.remove(at: index)
                    print("ProjectDetailsView: Photo removed from project images array")
                    
                    // Update project in database
                    await MainActor.run {
                        // Update project
                        project.setProjectImageURLs(currentImages)
                        project.needsSync = true
                        project.syncPriority = 2 // Higher priority for image changes
                        
                        // Save changes to the database
                        if let modelContext = dataController.modelContext {
                            do {
                                try modelContext.save()
                                print("ProjectDetailsView: ✅ Successfully deleted photo")
                            } catch {
                                print("ProjectDetailsView: ⚠️ Error saving changes after deletion: \(error.localizedDescription)")
                            }
                        } else {
                            print("ProjectDetailsView: ⚠️ ModelContext is nil, can't save changes")
                        }
                    }
                    
                    // Cleanup UserDefaults (optional but good practice)
                    if url.hasPrefix("local://") {
                        UserDefaults.standard.removeObject(forKey: url)
                        print("ProjectDetailsView: Removed image data from local storage")
                    }
                    
                    // Reset state
                    photoToDelete = nil
                } else {
                    print("ProjectDetailsView: ⚠️ Could not find photo in project images")
                }
            } catch {
                print("ProjectDetailsView: ❌ Error deleting photo: \(error.localizedDescription)")
            }
        }
    }
}

// Full screen photo viewer with swipe navigation
struct FullScreenPhotoViewer: View {
    let photos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    @Environment(\.colorScheme) private var colorScheme
    
    init(photos: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            // Background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Photo gallery with swipe
            TabView(selection: $currentIndex) {
                ForEach(0..<photos.count, id: \.self) { index in
                    ZoomablePhotoView(url: photos[index])
                        .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .automatic))
            
            // UI controls overlay
            VStack {
                // Top bar with close button and counter
                HStack {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) of \(photos.count)")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.white)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(20)
                }
                .padding(.horizontal, 16)
                .padding(.top, 48)
                
                Spacer()
            }
        }
        .statusBar(hidden: true)
        .preferredColorScheme(.dark)
    }
}

// Zoomable photo view for individual photos
struct ZoomablePhotoView: View {
    let url: String
    @State private var image: UIImage?
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isLoading = true
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            // Magnification gesture for zoom
                            MagnificationGesture()
                                .onChanged { value in
                                    let delta = value / lastScale
                                    lastScale = value
                                    scale = min(max(scale * delta, 1), 5)
                                }
                                .onEnded { _ in
                                    lastScale = 1.0
                                    
                                    // Reset zoom if scale is below 1
                                    if scale < 1 {
                                        withAnimation(.spring()) {
                                            scale = 1.0
                                        }
                                    }
                                    
                                    // Limit zoom to 5x
                                    if scale > 5 {
                                        withAnimation(.spring()) {
                                            scale = 5.0
                                        }
                                    }
                                }
                        )
                        .gesture(
                            // Drag gesture for panning when zoomed
                            DragGesture()
                                .onChanged { value in
                                    // Only allow panning when zoomed in
                                    if scale > 1 {
                                        offset = CGSize(
                                            width: lastOffset.width + value.translation.width,
                                            height: lastOffset.height + value.translation.height
                                        )
                                    }
                                }
                                .onEnded { _ in
                                    lastOffset = offset
                                    
                                    // If scale is reset to 1, also reset offset
                                    if scale <= 1 {
                                        withAnimation(.spring()) {
                                            offset = .zero
                                            lastOffset = .zero
                                        }
                                    }
                                }
                        )
                        // Double tap to toggle zoom
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1 {
                                    scale = 1.0
                                    offset = .zero
                                    lastOffset = .zero
                                } else {
                                    scale = 3.0
                                }
                            }
                        }
                } else if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Loading image...")
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Failed to load image")
                            .foregroundColor(.gray)
                            .padding(.top, 10)
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        // Handle local URL format for our simulated server
        if url.hasPrefix("local://") {
            print("ZoomablePhotoView: Loading local image: \(url)")
            
            // Try to load from UserDefaults
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                DispatchQueue.main.async {
                    isLoading = false
                    self.image = loadedImage
                    print("ZoomablePhotoView: Successfully loaded image from UserDefaults")
                }
            } else {
                print("ZoomablePhotoView: Failed to load image from UserDefaults for key: \(url)")
                DispatchQueue.main.async {
                    isLoading = false
                }
            }
            return
        }
        
        // Handle Bubble URL format (https://opsapp.co/version-test/img/...)
        var normalizedURL = url
        
        // Handle // prefix by adding https:
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        // Check if it's a Bubble URL but stored locally (for offline access)
        if normalizedURL.contains("opsapp.co/version-test/img/") {
            if let base64String = UserDefaults.standard.string(forKey: normalizedURL),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                DispatchQueue.main.async {
                    isLoading = false
                    self.image = loadedImage
                    print("ZoomablePhotoView: Successfully loaded Bubble image from local cache")
                }
                return
            }
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            print("ZoomablePhotoView: Invalid URL: \(normalizedURL)")
            isLoading = false
            return
        }
        
        print("ZoomablePhotoView: Loading remote image: \(imageURL)")
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("ZoomablePhotoView: Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("ZoomablePhotoView: HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    print("ZoomablePhotoView: Successfully loaded remote image")
                    
                    // Cache the remote image locally
                    if let base64String = data.base64EncodedString() as String? {
                        UserDefaults.standard.set(base64String, forKey: normalizedURL)
                        print("ZoomablePhotoView: Cached remote image locally")
                    }
                } else {
                    print("ZoomablePhotoView: Failed to create image from data")
                }
            }
        }.resume()
    }
}

struct DarkLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            configuration.label
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            configuration.content
                .font(OPSStyle.Typography.body)
        }
    }
}
