//
//  ProjectDetailsView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-25.
//

import SwiftUI
import UIKit
import MapKit

struct ProjectDetailsView: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @State private var noteText: String
    @EnvironmentObject private var dataController: DataController
    @StateObject private var locationManager = LocationManager()
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
        
        // Debug output to help troubleshoot issues
        print("ProjectDetailsView: Initialized with project ID: \(project.id), title: \(project.title)")
    }
    
    var body: some View {
        ZStack {
            // Background gradient
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)
            
            ScrollView {
                VStack(spacing: 16) {
                    // Header section with status and title
                    headerSection
                    
                    // Sections with consistent styling
                    
                    // Location map
                    locationSection
                    
                    // Client info
                    infoSection
                    
                    // Team members
                    teamSection
                    
                    // Notes (expandable)
                    ExpandableNotesView(
                        notes: project.notes ?? "",
                        editedNotes: $noteText,
                        onSave: saveNotes
                    )
                    .padding(.horizontal)
                    
                    // Photos
                    photosSection
                    
                    // Bottom padding
                    Spacer()
                        .frame(height: 20)
                }
            }
        }
        .navigationTitle("Project Details")
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
        .onAppear {
            // Request location permission when project details are viewed
            locationManager.requestPermissionIfNeeded()
        }
    }
    
    // Header with status and title
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                StatusBadge(status: project.status)
                
                Spacer()
                
                // Date pill
                if let startDate = project.startDate {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12))
                        
                        Text(formatDate(startDate))
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(OPSStyle.Colors.cardBackground.opacity(0.7))
                    .cornerRadius(12)
                }
            }
            
            // Project title
            Text(project.title)
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(.top, 4)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
    
    // Location map
    private var locationSection: some View {
        VStack(spacing: 0) {
            MiniMapView(
                coordinate: project.coordinate,
                address: project.address
            ) {
                openInMaps(coordinate: project.coordinate, address: project.address)
            }
            .padding(.horizontal)
        }
    }
    
    // Project info
    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Section title
            Text("PROJECT INFO")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal)
            
            // Info cards
            VStack(spacing: 2) {
                // Client card
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("CLIENT")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(project.clientName)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.3))
                
                // Address card
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ADDRESS")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        Text(project.address)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                    
                    Spacer()
                }
                .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                
                // Description card
                if let description = project.projectDescription, !description.isEmpty {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("DESCRIPTION")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            
                            Text(description)
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 12)
                        
                        Spacer()
                    }
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
                }
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal)
        }
    }
    
    // Team members section
    private var teamSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            TeamMemberListView(teamMembers: project.teamMembers)
                .padding(.horizontal)
        }
    }
    
    // Photos section
    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section title
            Text("PHOTOS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.horizontal)
            
            // Photo grid/carousel
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
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .padding(.horizontal)
                } else {
                    // Photo grid
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(Array(photos.enumerated()), id: \.0) { index, url in
                                PhotoThumbnail(url: url)
                                    .frame(width: 110, height: 110)
                                    .cornerRadius(8)
                                    .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 2)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedPhotoIndex = index
                                        showingPhotoViewer = true
                                    }
                                    .onLongPressGesture {
                                        photoToDelete = url
                                        showingDeleteConfirmation = true
                                    }
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 2) // For shadow space
                    }
                    .frame(height: 120)
                }
                
                // Add photos button
                Button(action: {
                    showingImagePicker = true
                }) {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 16))
                        
                        Text("ADD PHOTOS")
                            .font(OPSStyle.Typography.bodyBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(OPSStyle.Colors.primaryAccent)
                    .foregroundColor(.white)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(processingImages)
                .padding(.horizontal)
                
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
                    .padding(.horizontal)
                }
            }
        }
    }
    
    // Helper to format date
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: date)
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
                        
                        // Save image data to file system with the key as the URL
                        let localURL = "local://project_images/\(filename)"
                        
                        // Store the image in file system
                        let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
                        if success {
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
                    
                    // Cleanup file storage (optional but good practice)
                    if url.hasPrefix("local://") {
                        let deleted = ImageFileManager.shared.deleteImage(localID: url)
                        print("ProjectDetailsView: Removed image data from local storage: \(deleted ? "success" : "failed")")
                    }
                    
                    // Reset state
                    photoToDelete = nil
                } else {
                    print("ProjectDetailsView: ⚠️ Could not find photo in project images")
                }
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
            
            // Try to load from file system
            if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
                DispatchQueue.main.async {
                    isLoading = false
                    self.image = loadedImage
                    print("ZoomablePhotoView: Successfully loaded image from file system")
                }
            } else {
                print("ZoomablePhotoView: Failed to load image for: \(url)")
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
                    // For remote URLs, we'll still use UserDefaults as these are temporary caches
                    UserDefaults.standard.set(data, forKey: normalizedURL)
                    print("ZoomablePhotoView: Cached remote image locally")
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
