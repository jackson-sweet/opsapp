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
    @State private var loadState: LoadState = .loading
    
    enum LoadState {
        case loading
        case loaded
        case failed
    }
    
    init(urlString: String, size: CGSize = CGSize(width: 150, height: 150)) {
        self.urlString = urlString
        self.size = size
    }
    
    var body: some View {
        ZStack {
            // Background
            Rectangle()
                .fill(OPSStyle.Colors.cardBackground)
                .frame(width: size.width, height: size.height)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            // Content based on load state
            Group {
                if loadState == .loaded, let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: size.width, height: size.height)
                        .clipped()
                } else if loadState == .loading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.secondaryAccent))
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 28))
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
        .onAppear(perform: loadImage)
    }
    
    private func loadImage() {
        // Only try to load once
        if loadState != .loading {
            return
        }
        
        // Normalize the URL string - handle Bubble's format
        var normalizedURLString = urlString
        if urlString.hasPrefix("//") {
            normalizedURLString = "https:" + urlString
        }
        
        guard let url = URL(string: normalizedURLString) else {
            loadState = .failed
            return
        }
        
        // Use URLCache for better performance
        let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let data = data, let loadedImage = UIImage(data: data) {
                    self.image = loadedImage
                    self.loadState = .loaded
                } else {
                    self.loadState = .failed
                }
            }
        }.resume()
    }
}
