//
//  ProjectImagesSimple.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-01.
//

import SwiftUI

struct ProjectImagesSimple: View {
    let project: Project
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PHOTOS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let images = project.getProjectImages()
            
            if images.isEmpty {
                Text("No photos added yet")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
                    .background(OPSStyle.Colors.cardBackground)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            } else {
                // Super simple grid with minimal layout complexity
                ForEach(0..<images.count, id: \.self) { index in
                    if index < images.count {
                        SimpleImageView(urlString: images[index])
                            .frame(height: 200)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
            }
        }
    }
}

struct SimpleImageView: View {
    let urlString: String
    @State private var image: UIImage?
    
    var body: some View {
        // Always show a background first
        ZStack {
            Rectangle()
                .fill(OPSStyle.Colors.cardBackground)
            
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                // Simple loading indicator
                ProgressView()
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        var normalizedURL = urlString
        if urlString.hasPrefix("//") {
            normalizedURL = "https:" + urlString
        }
        
        guard let url = URL(string: normalizedURL) else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, _ in
            if let data = data, let image = UIImage(data: data) {
                DispatchQueue.main.async {
                    self.image = image
                }
            }
        }.resume()
    }
}
