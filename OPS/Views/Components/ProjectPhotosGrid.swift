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
    @State private var selectedPhotoIndex: Int?
    @State private var showingCamera = false
    
    // Three-column grid with minimal spacing
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background for photos visibility
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    let photos = project.getProjectImages()
                    
                    if photos.isEmpty {
                        // Empty state
                        emptyStateView
                    } else {
                        // Simple grid of square photos
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(photos.enumerated()), id: \.element) { index, url in
                                    GridImageCell(imageURL: url)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        .contentShape(Rectangle()) // Make entire cell tappable
                                        .onTapGesture {
                                            selectedPhotoIndex = index
                                        }
                                }
                            }
                            .padding(.horizontal, 2)
                        }
                    }
                }
                
                // Add photo button - fixed at bottom for easy access
                VStack {
                    Spacer()
                    
                    Button(action: {
                        showingCamera = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 18))
                            Text("Add Photo")
                                .font(.headline)
                        }
                        .foregroundColor(.white)
                        .frame(height: 52) // Larger height for gloved hands
                        .frame(maxWidth: .infinity)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(15)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationBarTitle("Project Photos", displayMode: .inline)
            .navigationBarItems(trailing: Button("Done") { dismiss() })
            .preferredColorScheme(.dark) // Force dark mode for photo viewing
            .fullScreenCover(item: Binding<PhotoViewerItem?>(
                get: { selectedPhotoIndex.map { PhotoViewerItem(index: $0) } },
                set: { item in selectedPhotoIndex = item?.index }
            )) { item in
                PhotoBrowser(
                    initialIndex: item.index,
                    imageURLs: project.getProjectImages()
                )
            }
            .sheet(isPresented: $showingCamera) {
                CameraPlaceholder()
            }
        }
    }
    
    // Empty state view - simple and clear
    private var emptyStateView: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            
            Text("No Photos")
                .font(.title2)
                .foregroundColor(.white)
            
            Text("Add photos to document this project.")
                .font(.body)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Spacer()
            
            // Empty state also has add button
            Button(action: {
                showingCamera = true
            }) {
                HStack {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 18))
                    Text("Add Photo")
                        .font(.headline)
                }
                .foregroundColor(.white)
                .frame(height: 52)
                .frame(width: 200)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(15)
            }
            .padding(.bottom, 50)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// Simple wrapper to make an index Identifiable
struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let index: Int
}

// Simple grid cell component - focus on reliability
struct GridImageCell: View {
    let imageURL: String
    @State private var image: UIImage?
    @State private var isLoading = true
    
    var body: some View {
        ZStack {
            // Background shows immediately
            Rectangle()
                .fill(Color.gray.opacity(0.3))
            
            if let image = image {
                // Image displays when loaded
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                // Loading indicator
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
            } else {
                // Error state
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
        
        // Handle Bubble URL format
        var normalizedURLString = imageURL
        if imageURL.hasPrefix("//") {
            normalizedURLString = "https:" + imageURL
        }
        
        guard let url = URL(string: normalizedURLString) else {
            isLoading = false
            return
        }
        
        // Use URLCache for better field performance
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                }
            }
        }.resume()
    }
}

// Revised photo browser with simplified gesture handling
struct PhotoBrowser: View {
    @Environment(\.dismiss) var dismiss
    let initialIndex: Int
    let imageURLs: [String]
    
    @State private var currentIndex: Int
    
    init(initialIndex: Int, imageURLs: [String]) {
        self.initialIndex = initialIndex
        self.imageURLs = imageURLs
        self._currentIndex = State(initialValue: initialIndex)
    }
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.edgesIgnoringSafeArea(.all)
            
            // Simplified photo carousel with standard paging behavior
            TabView(selection: $currentIndex) {
                ForEach(0..<imageURLs.count, id: \.self) { index in
                    PhotoPage(
                        imageURL: imageURLs[index],
                        onDismiss: { dismiss() }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // UI overlay - counter and close button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                    }
                    .padding(.top, 50)
                    .padding(.leading, 16)
                    
                    Spacer()
                    
                    Text("\(currentIndex + 1) of \(imageURLs.count)")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top, 50)
                        .padding(.trailing, 16)
                }
                
                Spacer()
            }
        }
        .edgesIgnoringSafeArea(.all)
        .statusBar(hidden: true)
    }
}

// Individual photo page with zoom and dismiss functionality
struct PhotoPage: View {
    let imageURL: String
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var verticalOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(y: verticalOffset)
                        // Only handle vertical drag for dismiss
                        .gesture(
                            DragGesture(minimumDistance: 10)
                                .onChanged { value in
                                    // Only process vertical drags (for dismiss)
                                    // and only when not zoomed in
                                    if scale <= 1.0 && abs(value.translation.height) > abs(value.translation.width) {
                                        verticalOffset = value.translation.height
                                    }
                                }
                                .onEnded { value in
                                    if scale <= 1.0 && value.translation.height > 100 {
                                        onDismiss()
                                    } else {
                                        // Spring back to position
                                        withAnimation(.spring()) {
                                            verticalOffset = 0
                                        }
                                    }
                                }
                        )
                        // Pinch to zoom
                        .gesture(
                            MagnificationGesture()
                                .onChanged { value in
                                    scale = min(max(value, 1.0), 4.0)
                                }
                                .onEnded { _ in
                                    if scale < 1.0 {
                                        withAnimation {
                                            scale = 1.0
                                        }
                                    }
                                }
                        )
                        // Double tap to toggle zoom
                        .onTapGesture(count: 2) {
                            withAnimation(.spring()) {
                                if scale > 1.0 {
                                    scale = 1.0
                                } else {
                                    scale = 2.0
                                }
                            }
                        }
                } else if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(1.5)
                } else {
                    VStack {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 40))
                            .foregroundColor(.gray)
                        
                        Text("Unable to load photo")
                            .foregroundColor(.gray)
                            .padding(.top, 8)
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
        
        // Handle Bubble URL format
        var normalizedURLString = imageURL
        if imageURL.hasPrefix("//") {
            normalizedURLString = "https:" + imageURL
        }
        
        guard let url = URL(string: normalizedURLString) else {
            isLoading = false
            return
        }
        
        // Use URLCache for better field performance
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                }
            }
        }.resume()
    }
}

// Placeholder for camera view - will be replaced with actual implementation
struct CameraPlaceholder: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack {
                Spacer()
                
                Text("Camera access will be implemented in the next update")
                    .font(.headline)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding()
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.gray)
                    .padding()
                
                Spacer()
                
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(.white)
                .frame(height: 52)
                .frame(width: 200)
                .background(Color.gray.opacity(0.5))
                .cornerRadius(15)
                .padding(.bottom, 50)
            }
        }
    }
}
