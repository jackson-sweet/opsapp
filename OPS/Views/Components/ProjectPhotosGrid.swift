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
    @State private var selectedImageIndex: Int?
    @State private var showingCamera = false
    
    // Column layout for grid - 3 columns for camera roll feel
    private let columns = [
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2),
        GridItem(.flexible(), spacing: 2)
    ]
    
    var body: some View {
        NavigationView {
            ZStack {
                // Black background like Photos app for field visibility
                Color.black.edgesIgnoringSafeArea(.all)
                
                VStack {
                    let images = project.getProjectImages()
                    
                    if images.isEmpty {
                        // Empty state
                        emptyStateView
                    } else {
                        // Images grid
                        ScrollView {
                            LazyVGrid(columns: columns, spacing: 2) {
                                ForEach(Array(images.enumerated()), id: \.element) { index, url in
                                    gridCell(url: url, index: index)
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
            // Fix for the fullScreenCover issue
            .fullScreenCover(item: $selectedImageIndex) { index in
                PhotoBrowser(
                    initialIndex: index,
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
    
    // Grid cell for photo thumbnail
    private func gridCell(url: String, index: Int) -> some View {
        GridImageCell(imageURL: url)
            .aspectRatio(1, contentMode: .fill)
            .clipped()
            .onTapGesture {
                selectedImageIndex = index
            }
    }
}

// Add this extension to make Int conform to Identifiable
extension Int: Identifiable {
    public var id: Int { self }
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

// Horizontal paging photo browser with swipe to dismiss
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
            
            // Paging view for horizontal swipe
            TabView(selection: $currentIndex) {
                ForEach(0..<imageURLs.count, id: \.self) { index in
                    ZoomablePhotoView(
                        imageURL: imageURLs[index],
                        onDismiss: { dismiss() }
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            
            // Counter display (e.g., "2 of 5")
            VStack {
                HStack {
                    Spacer()
                    
                    Text("\(currentIndex + 1) of \(imageURLs.count)")
                        .font(.caption)
                        .padding(8)
                        .background(Color.black.opacity(0.6))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding(.top, 50)
                        .padding(.trailing, 16)
                        .shadow(radius: 2)
                }
                
                Spacer()
            }
            
            // Close button
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                            .padding(12)
                            .background(Color.black.opacity(0.6))
                            .clipShape(Circle())
                            .shadow(radius: 2)
                    }
                    .padding(.top, 50)
                    .padding(.leading, 16)
                    
                    Spacer()
                }
                
                Spacer()
            }
        }
        .edgesIgnoringSafeArea(.all)
    }
}

// Single photo view with zoom and vertical dismiss
struct ZoomablePhotoView: View {
    let imageURL: String
    let onDismiss: () -> Void
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @GestureState private var dragState = CGSize.zero
    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(x: offset.width + dragState.width, y: offset.height + dragState.height)
                        .gesture(dragGesture(proxy: proxy))
                        .gesture(magnificationGesture())
                        .gesture(doubleTapGesture())
                } else if isLoading {
                    VStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Loading...")
                            .foregroundColor(.gray)
                            .padding(.top, 12)
                    }
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
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle()) // Make the entire view tappable
        }
        .onAppear(perform: loadImage)
    }
    
    // Vertical drag gesture for dismiss
    private func dragGesture(proxy: GeometryProxy) -> some Gesture {
        DragGesture()
            .updating($dragState) { value, state, _ in
                // Only update state while dragging
                state = value.translation
            }
            .onEnded { value in
                // If scaled, just move the image
                if scale > 1.0 {
                    offset = CGSize(
                        width: lastOffset.width + value.translation.width,
                        height: lastOffset.height + value.translation.height
                    )
                    lastOffset = offset
                } else {
                    // If vertical drag is significant, dismiss
                    if abs(value.translation.height) > 150 {
                        onDismiss()
                    } else {
                        // Snap back to position
                        withAnimation(.spring()) {
                            offset = lastOffset
                        }
                    }
                }
            }
    }
    
    // Pinch to zoom
    private func magnificationGesture() -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                lastScale = value
                
                // Limit minimum scale to 0.5 and maximum to 4
                scale = min(max(scale * delta, 0.5), 4.0)
            }
            .onEnded { _ in
                lastScale = 1.0
                
                // If scaled down below 1, reset to 1
                if scale < 1.0 {
                    withAnimation {
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    // Double tap to zoom in/out
    private func doubleTapGesture() -> some Gesture {
        TapGesture(count: 2)
            .onEnded {
                withAnimation(.spring()) {
                    if scale > 1.0 {
                        // Reset to normal
                        scale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        // Zoom in to 2x
                        scale = 2.0
                    }
                }
            }
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
        
        // Use URLCache for better performance in the field
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
