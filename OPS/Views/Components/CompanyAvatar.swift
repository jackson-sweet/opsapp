//
//  CompanyAvatar.swift
//  OPS
//
//  A unified avatar component for displaying company logos or initials
//

import SwiftUI

struct CompanyAvatar: View {
    let name: String
    let logoURL: String?
    let logoData: Data?
    let size: CGFloat
    let backgroundColor: Color
    
    // Convenience initializer for Company model
    init(company: Company, size: CGFloat = 40) {
        self.name = company.name
        self.logoURL = company.logoURL
        self.logoData = company.logoData
        self.size = size
        self.backgroundColor = OPSStyle.Colors.primaryText
    }
    
    // Generic initializer
    init(name: String, logoURL: String? = nil, logoData: Data? = nil, size: CGFloat = 40, backgroundColor: Color? = nil) {
        self.name = name
        self.logoURL = logoURL
        self.logoData = logoData
        self.size = size
        self.backgroundColor = backgroundColor ?? OPSStyle.Colors.primaryText
    }
    
    private var initials: String {
        // Get initials from company name (up to 2 characters)
        let words = name.split(separator: " ")
        if words.count >= 2 {
            // Take first letter of first two words
            let firstInitial = words[0].prefix(1).uppercased()
            let secondInitial = words[1].prefix(1).uppercased()
            return "\(firstInitial)\(secondInitial)"
        } else if words.count == 1 {
            // Take first two letters of single word
            return String(words[0].prefix(2).uppercased())
        } else {
            return "CO" // Default for empty names
        }
    }
    
    private var fontSize: CGFloat {
        // Scale font size based on avatar size
        return size * 0.4
    }
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let logoData = logoData,
               let uiImage = UIImage(data: logoData) {
                // Use local logo data if available
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let loadedImage = loadedImage {
                // Use downloaded logo
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Default avatar with initials
                Circle()
                    .fill(backgroundColor)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.custom("Mohave-Bold", size: fontSize))
                            .foregroundColor(.black)
                            .offset(x: 0, y: fontSize/15)
                    )
            }
            
            // Loading indicator
            if isLoading {
                Circle()
                    .fill(Color.black.opacity(0.3))
                    .frame(width: size, height: size)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.5)
                    )
            }
        }
        .onAppear {
            loadImageIfNeeded()
        }
        .onChange(of: logoURL) { _, _ in
            loadImageIfNeeded()
        }
    }
    
    private func loadImageIfNeeded() {
        // Don't load if we already have logo data or a loaded image
        guard logoData == nil,
              loadedImage == nil,
              let urlString = logoURL,
              !urlString.isEmpty else {
            return
        }
        
        // Fix URLs that start with // by adding https:
        var fixedURLString = urlString
        if urlString.hasPrefix("//") {
            fixedURLString = "https:" + urlString
        }
        
        guard let url = URL(string: fixedURLString) else {
            print("Invalid URL: \(fixedURLString)")
            return
        }
        
        // Check cache first (use original URL string as key)
        if let cachedImage = ImageCache.shared.get(forKey: urlString) {
            self.loadedImage = cachedImage
            return
        }
        
        // Download image
        isLoading = true
        
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                if let image = UIImage(data: data) {
                    await MainActor.run {
                        self.loadedImage = image
                        self.isLoading = false
                        // Cache the image using original URL as key
                        ImageCache.shared.set(image, forKey: urlString)
                    }
                }
            } catch {
                print("Failed to load company logo from \(fixedURLString): \(error)")
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Previews
#Preview("Company Avatars") {
    VStack(spacing: 20) {
        // With logo
        CompanyAvatar(
            name: "OPS Company",
            logoURL: "https://example.com/logo.jpg",
            size: 60
        )
        
        // Without logo - default initials
        CompanyAvatar(
            name: "Trade Works Inc",
            size: 60
        )
        
        // Single word company
        CompanyAvatar(
            name: "BuildCorp",
            size: 60
        )
        
        // Different sizes
        HStack(spacing: 20) {
            CompanyAvatar(name: "ABC Corp", size: 30)
            CompanyAvatar(name: "XYZ Inc", size: 40)
            CompanyAvatar(name: "Test Co", size: 50)
            CompanyAvatar(name: "Demo LLC", size: 60)
        }
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
