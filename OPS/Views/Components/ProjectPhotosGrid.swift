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
                                            selectedPhotoIndex = index
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
            CameraPlaceholder()
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
        
        // Handle Bubble URL format
        var normalizedURL = url
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        guard let imageURL = URL(string: normalizedURL) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
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
        
        // Handle Bubble URL format
        var normalizedURL = url
        if url.hasPrefix("//") {
            normalizedURL = "https:" + url
        }
        
        guard let imageURL = URL(string: normalizedURL) else {
            isLoading = false
            return
        }
        
        URLSession.shared.dataTask(with: imageURL) { data, _, _ in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                }
            }
        }.resume()
    }
}

// Simple camera placeholder
struct CameraPlaceholder: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack {
            Color.black.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 30) {
                Text("Camera Coming Soon")
                    .font(.title2)
                    .foregroundColor(.white)
                
                Image(systemName: "camera.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.gray)
                
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(.white)
                .frame(height: 56)
                .frame(width: 200)
                .background(Color.gray.opacity(0.5))
                .cornerRadius(16)
                .padding(.top, 20)
            }
        }
    }
}
