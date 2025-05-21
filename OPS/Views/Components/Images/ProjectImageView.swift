//
//  ProjectImageView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import SwiftUI

struct ProjectImageView: View {
    let urlString: String
    let size: CGSize
    let project: Project
    
    @State private var image: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    
    init(urlString: String, project: Project, size: CGSize = CGSize(width: 150, height: 150)) {
        self.urlString = urlString
        self.project = project
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Background placeholder - shows IMMEDIATELY
            Rectangle()
                .fill(OPSStyle.Colors.cardBackground)
                .frame(width: size.width, height: size.height)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            if let image = image {
                // Image loaded successfully
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                
                // Overlay a cloud with slash icon if image is not synced
                if !project.isImageSynced(urlString) {
                    VStack {
                        HStack {
                            Spacer()
                            
                            // Unsynced indicator
                            Image(systemName: "cloud.slash.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(4)
                                .background(Color.red)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.5), radius: 2, x: 0, y: 1)
                                .padding(6)
                        }
                        
                        Spacer()
                    }
                }
            } else if isLoading {
                // Loading state
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.secondaryAccent))
            } else if loadFailed {
                // Failed state
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        // First check in-memory cache for quick loading
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = cachedImage
                print("ProjectImageView: Using cached image from memory")
            }
            return
        }
        
        // Then try to load from file system using ImageFileManager
        if let loadedImage = ImageFileManager.shared.loadImage(localID: urlString) {
            DispatchQueue.main.async {
                self.isLoading = false
                self.image = loadedImage
                print("ProjectImageView: Successfully loaded image from file system")
                
                // Cache in memory for faster access next time
                ImageCache.shared.set(loadedImage, forKey: urlString)
            }
            return
        }
        
        // For legacy support: try UserDefaults if not found in file system
        if urlString.hasPrefix("local://") {
            if let base64String = UserDefaults.standard.string(forKey: urlString),
               let imageData = Data(base64Encoded: base64String),
               let loadedImage = UIImage(data: imageData) {
                
                // Migrate to file system for future use
                _ = ImageFileManager.shared.saveImage(data: imageData, localID: urlString)
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.image = loadedImage
                    print("ProjectImageView: Loaded image from UserDefaults and migrated to file system")
                    
                    // Cache in memory
                    ImageCache.shared.set(loadedImage, forKey: urlString)
                }
                return
            }
        }
        
        // Handle remote URLs
        var normalizedURLString = urlString
        if urlString.hasPrefix("//") {
            normalizedURLString = "https:" + urlString
        }
        
        guard let url = URL(string: normalizedURLString) else {
            print("ProjectImageView: Invalid URL: \(normalizedURLString)")
            isLoading = false
            loadFailed = true
            return
        }
        
        print("ProjectImageView: Loading remote image: \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let error = error {
                    print("ProjectImageView: Error loading image: \(error.localizedDescription)")
                    self.loadFailed = true
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, 
                   !(200...299).contains(httpResponse.statusCode) {
                    print("ProjectImageView: HTTP Error: \(httpResponse.statusCode)")
                    self.loadFailed = true
                    return
                }
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    print("ProjectImageView: Successfully loaded remote image")
                    
                    // Cache the remote image locally in file system
                    _ = ImageFileManager.shared.saveImage(data: data, localID: normalizedURLString)
                    
                    // Also cache in memory
                    ImageCache.shared.set(loadedImage, forKey: normalizedURLString)
                } else {
                    print("ProjectImageView: Failed to create image from data")
                    self.loadFailed = true
                }
            }
        }.resume()
    }
}
