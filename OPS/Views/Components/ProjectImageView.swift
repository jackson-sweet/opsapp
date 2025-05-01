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
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var loadFailed = false
    
    init(urlString: String, size: CGSize = CGSize(width: 150, height: 150)) {
        self.urlString = urlString
        self.size = size
    }
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipped()
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            } else {
                placeholderView
            }
        }
        .onAppear(perform: loadImage)
    }
    
    private var placeholderView: some View {
        ZStack {
            Rectangle()
                .fill(OPSStyle.Colors.cardBackground)
                .frame(width: size.width, height: size.height)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.secondaryAccent))
            } else if loadFailed {
                VStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                    
                    Text("Failed to load")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 28))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
        }
    }
    
    private func loadImage() {
        guard !isLoading, image == nil else { return }
        
        // Fix Bubble's URL format if needed
        var normalizedURLString = urlString
        if urlString.hasPrefix("//") {
            normalizedURLString = "https:" + urlString
        }
        
        guard let url = URL(string: normalizedURLString) else {
            loadFailed = true
            return
        }
        
        isLoading = true
        loadFailed = false
        
        // Use URLCache for better performance
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                } else {
                    self.loadFailed = true
                    print("Image load failed: \(error?.localizedDescription ?? "Unknown error")")
                }
            }
        }.resume()
    }
}
