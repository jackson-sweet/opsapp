//
//  ProjectPhotosGrid.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import SwiftUI

struct ProjectPhotosGrid: View {
    let project: Project
    @Environment(\.dismiss) var dismiss
    @State private var selectedPhotoIndex: Int? = nil
    @State private var showingCamera = false
    @State private var cameraImage: UIImage?
    @State private var processingImage = false
    @State private var showingDeleteConfirmation = false
    @State private var photoToDelete: String? = nil
    @State private var longPressingPhotoIndex: Int? = nil
    @State private var showingNetworkError = false
    @State private var networkErrorMessage = ""
    @EnvironmentObject private var dataController: DataController
    
    // Three-column grid with minimal spacing
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background for optimal photo viewing
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    let photos = project.getProjectImages()
                    
                    if photos.isEmpty {
                        emptyStateView
                    } else {
                        // Grid layout of photos
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                    ZStack {
                                        PhotoThumbnail(url: url, project: project)
                                            .aspectRatio(1, contentMode: .fill)
                                            .clipped()
                                            .contentShape(Rectangle())
                                    }
                                    .scaleEffect(longPressingPhotoIndex == index ? 0.9 : 1.0) // Scale down when pressed
                                    .overlay(
                                        // Show a subtle delete icon overlay during long press
                                        ZStack {
                                            if longPressingPhotoIndex == index {
                                                Color.black.opacity(0.5)
                                                
                                                Image(systemName: "trash")
                                                    .font(.system(size: 30))
                                                    .foregroundColor(.white)
                                            }
                                        }
                                    )
                                    .onTapGesture {
                                        // View photo in viewer
                                        selectedPhotoIndex = index
                                    }
                                    .onLongPressGesture(minimumDuration: 0.5) {
                                        // Long press action
                                        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                                        impactFeedback.prepare()
                                        impactFeedback.impactOccurred()
                                        
                                        // Reset visual state
                                        longPressingPhotoIndex = nil
                                        
                                        // Show delete confirmation
                                        photoToDelete = url
                                        showingDeleteConfirmation = true
                                    } onPressingChanged: { isPressing in
                                        // Visual feedback while pressing - happens immediately
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            longPressingPhotoIndex = isPressing ? index : nil
                                        }
                                    }
                                }
                            }
                            .padding(2)
                        }
                    }
                }
                
                // Camera button - fixed at bottom
                VStack {
                    Spacer()
                    
                    Button(action: { showingCamera = true }) {
                        HStack {
                            Image(systemName: "camera.fill")
                            Text("Add Photo")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(height: 56)
                        .frame(maxWidth: .infinity)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(16)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                    .disabled(processingImage)
                }
                
                // Loading overlay when processing image
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
                    .edgesIgnoringSafeArea(.all)
                }
            }
            .navigationBarTitle("Project Photos", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
        }
        .preferredColorScheme(.dark)
        .fullScreenCover(item: Binding<PhotoViewerItem?>(
            get: { selectedPhotoIndex.map { PhotoViewerItem(index: $0) } },
            set: { item in selectedPhotoIndex = item?.index }
        )) { item in
            BasicPhotoViewer(
                photos: project.getProjectImages(),
                initialIndex: item.index,
                onDismiss: { selectedPhotoIndex = nil }
            )
        }
        .sheet(isPresented: $showingCamera) {
            ImagePicker(
                images: Binding<[UIImage]>(
                    get: { cameraImage != nil ? [cameraImage!] : [] },
                    set: { images in
                        if let first = images.first {
                            cameraImage = first
                        }
                    }
                ), 
                selectionLimit: 1,
                onSelectionComplete: {
                    // Close the picker immediately
                    showingCamera = false
                    
                    // Process image when selection is complete
                    if let image = cameraImage {
                        // Use slight delay to ensure UI dismissal completes first
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            addPhotoToProject(image)
                        }
                    }
                }
            )
        }
        // Network error alert
        .alert("Network Error", isPresented: $showingNetworkError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(networkErrorMessage)
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
    
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No Photos")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("Add photos to document this project")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            Button(action: { showingCamera = true }) {
                HStack {
                    Image(systemName: "camera.fill")
                    Text("Add Photo")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(height: 56)
                .frame(width: 220)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(16)
                .padding(.bottom, 40)
            }
        }
    }
}

// Simple wrapper to make an index Identifiable
struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

// Clean thumbnail with loading state
struct PhotoThumbnail: View {
    let url: String
    let project: Project? // Optional to maintain backward compatibility
    @State private var image: UIImage?
    @State private var isLoading = true
    private let id = UUID() // Unique identifier to prevent view reuse
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                
                // Overlay a cloud with slash icon if image is not synced
                if let project = project, !project.isImageSynced(url) {
                    VStack {
                        HStack {
                            Spacer()
                            
                            // Unsynced indicator
                            Image(systemName: "icloud.slash")
                                .font(.system(size: 12))
                                .foregroundColor(.white)
                                .padding(2)
                                .background(Color.red)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.5), radius: 1, x: 0, y: 1)
                                .padding(4)
                        }
                        
                        Spacer()
                    }
                }
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }
        }
        .onAppear(perform: loadImage)
        .id("\(url)-\(id)") // Force unique view identity with URL and UUID
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        
        // First check in-memory cache
        if let cachedImage = ImageCache.shared.get(forKey: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
            }
            return
        }
        
        // Then try to load from file system using ImageFileManager
        if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage
                
                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: url)
            }
            return
        }
        
        // For legacy support: try UserDefaults if not found in file system
        if url.hasPrefix("local://") {
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: url)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage
                    
                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: url)
                }
                return
            }
        }
        
        // Handle Bubble URL format (https://opsapp.co/version-test/img/...)
        var normalizedURL = url
        
        // Handle // prefix by adding https:
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            isLoading = false
            return
        }
        
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("PhotoThumbnail: Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("PhotoThumbnail: HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    
                    // Cache the remote image locally in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: normalizedURL)
                    
                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: normalizedURL)
                } else {
                    print("PhotoThumbnail: Failed to create image from data")
                }
            }
        }.resume()
    }
}

// Super simple photo viewer with no fancy animations - just works
struct BasicPhotoViewer: View {
    let photos: [String]
    let initialIndex: Int
    let onDismiss: () -> Void
    
    @State private var currentIndex: Int
    
    init(photos: [String], initialIndex: Int, onDismiss: @escaping () -> Void) {
        self.photos = photos
        self.initialIndex = initialIndex
        self.onDismiss = onDismiss
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        TabView(selection: $currentIndex) {
            ForEach(0..<photos.count, id: \.self) { index in
                SinglePhotoView(
                    url: photos[index],
                    onDismiss: onDismiss
                )
                .tag(index)
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
        .background(Color.black)
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
        .overlay(
            // Close button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .padding(20)
            }, alignment: .topTrailing
        )
    }
}

// Ultra simple photo view with zoom only
struct SinglePhotoView: View {
    let url: String
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            Color.black
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaleEffect(scale)
                    // Magnification gesture for zooming
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = min(max(value, 1), 3)
                            }
                            .onEnded { _ in
                                if scale < 1 {
                                    withAnimation(.spring()) {
                                        scale = 1
                                    }
                                }
                            }
                    )
                    // Double tap to toggle zoom
                    .onTapGesture(count: 2) {
                        withAnimation(.spring()) {
                            scale = scale > 1 ? 1 : 2
                        }
                    }
            } else if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
            } else {
                Text("Failed to load image")
                    .foregroundColor(.gray)
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        // First check in-memory cache
        if let cachedImage = ImageCache.shared.get(forKey: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
            }
            return
        }
        
        // Then try to load from file system using ImageFileManager
        if let loadedImage = ImageFileManager.shared.loadImage(localID: url) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage
                
                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: url)
            }
            return
        }
        
        // For legacy support: try UserDefaults if not found in file system
        if url.hasPrefix("local://") {
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: url)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage
                    
                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: url)
                }
                return
            }
        }
        
        // Handle Bubble URL format (https://opsapp.co/version-test/img/...)
        var normalizedURL = url
        
        // Handle // prefix by adding https:
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            isLoading = false
            return
        }
        
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("SinglePhotoView: Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("SinglePhotoView: HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    
                    // Cache the remote image locally in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: normalizedURL)
                    
                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: normalizedURL)
                } else {
                    print("SinglePhotoView: Failed to create image from data")
                }
            }
        }.resume()
    }
}

// MARK: - Project Photo Management
extension ProjectPhotosGrid {
    
    /// Delete a single photo from the project
    private func deletePhoto(_ url: String) {
        // Start a background task for deletion
        Task {
            
            // Get current project images
            var currentImages = project.getProjectImages()
            
            // Remove the specified image
            if let index = currentImages.firstIndex(of: url) {
                currentImages.remove(at: index)
                
                // Use ImageSyncManager if available
                if let imageSyncManager = dataController.imageSyncManager {
                    
                    // Delete the image through the ImageSyncManager
                    let success = await imageSyncManager.deleteImage(url, from: project)
                    
                    if success {
                    } else {
                        print("ProjectPhotosGrid: ⚠️ ImageSyncManager failed to delete the image, but we'll update the project anyway")
                    }
                } else {
                    // Fallback to direct file deletion if ImageSyncManager is not available
                    
                    // Clean up file storage
                    if url.hasPrefix("local://") {
                        let deleted = ImageFileManager.shared.deleteImage(localID: url)
                        print("ProjectPhotosGrid: Deleted image from FileManager: \(deleted ? "success" : "failed")")
                    }
                    
                    // Also clean up UserDefaults (for legacy support)
                    UserDefaults.standard.removeObject(forKey: url)
                }
                
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
                        } catch {
                            print("ProjectPhotosGrid: ⚠️ Error saving changes after deletion: \(error.localizedDescription)")
                        }
                    } else {
                    }
                    
                    // Reset state
                    photoToDelete = nil
                }
            } else {
            }
        }
    }
    private func addPhotoToProject(_ image: UIImage) {
        // Start loading indicator
        processingImage = true
        
        
        Task {
            // Use the ImageSyncManager if available
            if let imageSyncManager = dataController.imageSyncManager {
                
                // Process the image through the ImageSyncManager
                let urls = await imageSyncManager.saveImages([image], for: project)
                
                if let url = urls.first, !url.isEmpty {
                    // ImageSyncManager already added the image to the project
                    
                    await MainActor.run {
                        // Clear selected image and hide loading
                        cameraImage = nil
                        processingImage = false
                    }
                } else {
                    await MainActor.run {
                        processingImage = false
                        showingNetworkError = true
                        networkErrorMessage = "Failed to upload image to the server. Please check your network connection and try again."
                    }
                }
            } else {
                // Fallback to ImageFileManager if ImageSyncManager is not available
                
                // Compress image for storage
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    print("ProjectPhotosGrid: ⚠️ Failed to compress image")
                    await MainActor.run {
                        processingImage = false
                    }
                    return
                }
                
                // Generate a unique filename
                let timestamp = Date().timeIntervalSince1970
                let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                let localURL = "local://project_images/\(filename)"
                
                // Store the image in file system
                let success = ImageFileManager.shared.saveImage(data: imageData, localID: localURL)
                
                if success {
                    
                    // Add to project's images
                    await MainActor.run {
                        var currentImages = project.getProjectImages()
                        currentImages.append(localURL)
                        
                        project.setProjectImageURLs(currentImages)
                        project.needsSync = true
                        project.syncPriority = 2
                        
                        if let modelContext = dataController.modelContext {
                            do {
                                try modelContext.save()
                            } catch {
                                print("ProjectPhotosGrid: ⚠️ Error saving to model context: \(error.localizedDescription)")
                            }
                        }
                        
                        // Clear selected image and hide loading
                        cameraImage = nil
                        processingImage = false
                    }
                } else {
                    await MainActor.run {
                        print("ProjectPhotosGrid: ❌ Failed to save image with ImageFileManager")
                        processingImage = false
                    }
                }
            }
        }
    }
}
