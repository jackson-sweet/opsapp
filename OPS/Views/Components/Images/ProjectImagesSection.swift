//
//  ProjectImagesSection.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-28.
//

import SwiftUI

struct ProjectImagesSection: View {
    let project: Project
    @State private var selectedImageURL: String?
    
    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // Section header - always visible immediately
            Text("PHOTOS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            
            let imageUrls = project.getProjectImages()
            
            if imageUrls.isEmpty {
                // Empty state - shown immediately if no images
                emptyState
            } else {
                // Image grid - images load independently
                imageGrid(urls: imageUrls)
            }
        }
        .fullScreenCover(item: $selectedImageURL) { url in
            // Full screen image view
            ZStack(alignment: .topTrailing) {
                Color.black.edgesIgnoringSafeArea(.all)
                
                ProjectImageView(urlString: url, size: CGSize(width: UIScreen.main.bounds.width - 40, height: 400))
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding()
                
                Button(action: { selectedImageURL = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 30))
                        .foregroundColor(.white)
                        .padding(20)
                }
            }
        }
    }
    
    // Empty state view
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "camera")
                .font(.system(size: 32))
                .foregroundColor(OPSStyle.Colors.secondaryText.opacity(0.7))
            
            Text("No photos added yet")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(OPSStyle.Layout.spacing4)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    // Image grid
    private func imageGrid(urls: [String]) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2),
            GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2)
        ], spacing: OPSStyle.Layout.spacing2) {
            ForEach(urls, id: \.self) { url in
                ProjectImageView(urlString: url)
                    .onTapGesture {
                        selectedImageURL = url
                    }
            }
        }
    }

}
