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
    @State private var isLoading = true
    @State private var loadFailed = false
    
    init(urlString: String, size: CGSize = CGSize(width: 150, height: 150)) {
        self.urlString = urlString
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
        // Normalize URL and load image as before
        var normalizedURLString = urlString
        if urlString.hasPrefix("//") {
            normalizedURLString = "https:" + urlString
        }
        
        guard let url = URL(string: normalizedURLString) else {
            isLoading = false
            loadFailed = true
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                isLoading = false
                
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                } else {
                    self.loadFailed = true
                }
            }
        }.resume()
    }
}
