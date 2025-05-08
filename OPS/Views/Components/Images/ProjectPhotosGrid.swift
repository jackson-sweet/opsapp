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
                                    PhotoThumbnail(url: url)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            // View photo in viewer
                                            selectedPhotoIndex = index
                                        }
                                        .onLongPressGesture {
                                            // Show delete confirmation
                                            photoToDelete = url
                                            showingDeleteConfirmation = true
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
                    // Process image when selection is complete
                    if let image = cameraImage {
                        addPhotoToProject(image)
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
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            Color.gray.opacity(0.2)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                ProgressView()
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.gray)
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        // Handle local URL format for our simulated server
        if url.hasPrefix("local://") {
            print("Loading local image: \(url)")
            
            // Try to load from UserDefaults
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                DispatchQueue.main.async {
                    isLoading = false
                    self.image = loadedImage
                    print("Successfully loaded image from UserDefaults")
                }
            } else {
                print("Failed to load image from UserDefaults for key: \(url)")
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
                    print("Successfully loaded Bubble image from local cache")
                }
                return
            }
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            print("Invalid URL: \(normalizedURL)")
            isLoading = false
            return
        }
        
        print("Loading remote image: \(imageURL)")
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    print("Successfully loaded remote image")
                    
                    // Cache the remote image locally
                    if let base64String = data.base64EncodedString() as String? {
                        UserDefaults.standard.set(base64String, forKey: normalizedURL)
                        print("Cached remote image locally")
                    }
                } else {
                    print("Failed to create image from data")
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
        
        // Handle local URL format for our simulated server
        if url.hasPrefix("local://") {
            print("Loading local image: \(url)")
            
            // Try to load from UserDefaults
            if let base64String = UserDefaults.standard.string(forKey: url),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                DispatchQueue.main.async {
                    isLoading = false
                    self.image = loadedImage
                    print("Successfully loaded image from UserDefaults")
                }
            } else {
                print("Failed to load image from UserDefaults for key: \(url)")
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
                    print("Successfully loaded Bubble image from local cache")
                }
                return
            }
        }
        
        // If not found locally, try to load from network
        guard let imageURL = URL(string: normalizedURL) else {
            print("Invalid URL: \(normalizedURL)")
            isLoading = false
            return
        }
        
        print("Loading remote image: \(imageURL)")
        
        URLSession.shared.dataTask(with: imageURL) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("Error loading image: \(error.localizedDescription)")
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("HTTP Error: \(httpResponse.statusCode)")
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    print("Successfully loaded remote image")
                    
                    // Cache the remote image locally
                    if let base64String = data.base64EncodedString() as String? {
                        UserDefaults.standard.set(base64String, forKey: normalizedURL)
                        print("Cached remote image locally")
                    }
                } else {
                    print("Failed to create image from data")
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
            print("Deleting photo: \(url)")
            
            // Get current project images
            var currentImages = project.getProjectImages()
            
            // Remove the specified image
            if let index = currentImages.firstIndex(of: url) {
                currentImages.remove(at: index)
                print("Photo removed from project images array")
                
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
                            print("✅ Successfully deleted photo")
                        } catch {
                            print("⚠️ Error saving changes after deletion: \(error.localizedDescription)")
                        }
                    } else {
                        print("⚠️ ModelContext is nil, can't save changes")
                    }
                }
                
                // Cleanup UserDefaults (optional but good practice)
                if url.hasPrefix("local://") {
                    UserDefaults.standard.removeObject(forKey: url)
                    print("Removed image data from local storage")
                }
                
                // Reset state
                photoToDelete = nil
            } else {
                print("⚠️ Could not find photo in project images")
            }
        }
    }
    private func addPhotoToProject(_ image: UIImage) {
        // Start loading indicator
        processingImage = true
        
        print("ProjectPhotosGrid: Starting to process image")
        
        Task {
            do {
                // Compress image
                guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                    print("ProjectPhotosGrid: ⚠️ Failed to compress image")
                    await MainActor.run {
                        processingImage = false
                    }
                    return
                }
                
                print("ProjectPhotosGrid: Successfully compressed image: \(imageData.count) bytes")
                
                // Simulate upload delay
                try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                
                // Generate a unique filename
                let timestamp = Date().timeIntervalSince1970
                let filename = "project_\(project.id)_\(timestamp)_\(UUID().uuidString).jpg"
                
                // Save image data to UserDefaults with the key as the URL
                // This simulates a server but keeps the image locally
                let simulatedURL = "local://project_images/\(filename)"
                
                // Store the image in UserDefaults (as a workaround since we have no real server)
                if let imageBase64 = imageData.base64EncodedString() as String? {
                    UserDefaults.standard.set(imageBase64, forKey: simulatedURL)
                    print("ProjectPhotosGrid: Stored image data for: \(simulatedURL)")
                }
                
                print("ProjectPhotosGrid: Generated URL: \(simulatedURL)")
                
                // Add to project's images
                await MainActor.run {
                    var currentImages = project.getProjectImages()
                    print("ProjectPhotosGrid: Current images count before: \(currentImages.count)")
                    currentImages.append(simulatedURL)
                    print("ProjectPhotosGrid: Current images count after: \(currentImages.count)")
                    
                    project.setProjectImageURLs(currentImages)
                    print("ProjectPhotosGrid: Updated project image URLs")
                    
                    // Mark project for sync
                    project.needsSync = true
                    
                    // Save to database
                    if let modelContext = dataController.modelContext {
                        do {
                            try modelContext.save()
                            print("ProjectPhotosGrid: ✅ Saved to model context successfully")
                        } catch {
                            print("ProjectPhotosGrid: ⚠️ Error saving to model context: \(error.localizedDescription)")
                        }
                    } else {
                        print("ProjectPhotosGrid: ⚠️ Model context is nil")
                    }
                    
                    // Clear selected image and hide loading
                    cameraImage = nil
                    processingImage = false
                    
                    print("ProjectPhotosGrid: ✅ Image processing complete. Current project images: \(project.getProjectImages().count)")
                }
            } catch {
                print("ProjectPhotosGrid: ❌ Error processing image: \(error.localizedDescription)")
                await MainActor.run {
                    // Handle error
                    processingImage = false
                }
            }
        }
    }
}
