//
//  UserAvatar.swift
//  OPS
//
//  A unified avatar component for displaying user profile images or initials
//

import SwiftUI

// MARK: - Color Extension for Hex Support
extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0

        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }

        let length = hexSanitized.count

        if length == 6 {
            let r = Double((rgb & 0xFF0000) >> 16) / 255.0
            let g = Double((rgb & 0x00FF00) >> 8) / 255.0
            let b = Double(rgb & 0x0000FF) / 255.0

            self.init(red: r, green: g, blue: b)
        } else if length == 8 {
            let r = Double((rgb & 0xFF000000) >> 24) / 255.0
            let g = Double((rgb & 0x00FF0000) >> 16) / 255.0
            let b = Double((rgb & 0x0000FF00) >> 8) / 255.0
            let a = Double(rgb & 0x000000FF) / 255.0

            self.init(red: r, green: g, blue: b, opacity: a)
        } else {
            return nil
        }
    }

    /// Convert SwiftUI Color to hex string
    func toHex() -> String? {
        guard let components = UIColor(self).cgColor.components else { return nil }

        let r = components[0]
        let g = components[1]
        let b = components[2]

        let hex = String(
            format: "#%02lX%02lX%02lX",
            lroundf(Float(r * 255)),
            lroundf(Float(g * 255)),
            lroundf(Float(b * 255))
        )

        return hex
    }
}

struct UserAvatar: View {
    let firstName: String
    let lastName: String
    let imageURL: String?
    let imageData: Data?
    let size: CGFloat
    let backgroundColor: Color
    
    // Convenience initializers
    init(user: User, size: CGFloat = 40) {
        self.firstName = user.firstName
        self.lastName = user.lastName
        self.imageURL = user.profileImageURL
        self.imageData = user.profileImageData
        self.size = size
        self.backgroundColor = Color(hex: user.userColor ?? "#A49577") ?? OPSStyle.Colors.primaryAccent
    }
    
    init(teamMember: TeamMember, size: CGFloat = 40) {
        self.firstName = teamMember.firstName
        self.lastName = teamMember.lastName
        self.imageURL = teamMember.avatarURL
        self.imageData = nil // TeamMember doesn't store image data
        self.size = size
        // TeamMember doesn't have userColor, use default
        self.backgroundColor = OPSStyle.Colors.primaryAccent
    }
    
    init(client: Client, size: CGFloat = 40) {
        // Parse client name into first and last name
        let names = client.name.components(separatedBy: " ")
        self.firstName = names.first ?? client.name
        self.lastName = names.count > 1 ? names.dropFirst().joined(separator: " ") : ""
        self.imageURL = client.profileImageURL
        self.imageData = nil
        self.size = size
        // Use white for client avatars
        self.backgroundColor = .white
    }
    
    init(firstName: String, lastName: String, imageURL: String? = nil, imageData: Data? = nil, size: CGFloat = 40, backgroundColor: Color? = nil) {
        self.firstName = firstName
        self.lastName = lastName
        self.imageURL = imageURL
        self.imageData = imageData
        self.size = size
        self.backgroundColor = backgroundColor ?? OPSStyle.Colors.primaryAccent
    }
    
    private var initials: String {
        let firstInitial = firstName.prefix(1).uppercased()
        let lastInitial = lastName.prefix(1).uppercased()
        return "\(firstInitial)\(lastInitial)"
    }
    
    private var fontSize: CGFloat {
        // Scale font size based on avatar size
        return size * 0.4
    }
    
    @State private var loadedImage: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let imageData = imageData,
               let uiImage = UIImage(data: imageData) {
                // Use local image data if available
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if let loadedImage = loadedImage {
                // Use downloaded image
                Image(uiImage: loadedImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else {
                // Default avatar with initials - no background, just border
                Circle()
                    .stroke(backgroundColor, lineWidth: 2)
                    .frame(width: size, height: size)
                    .overlay(
                        Text(initials)
                            .font(.custom("Mohave-Bold", size: fontSize))
                            .foregroundColor(backgroundColor)
                            .offset(x: 0, y: fontSize/15)
                    )
            }
            
            // Loading indicator
            if isLoading {
                Circle()
                    .fill(OPSStyle.Colors.avatarOverlay)
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
        .onChange(of: imageURL) { _, _ in
            loadImageIfNeeded()
        }
    }
    
    private func loadImageIfNeeded() {
        // Don't load if we already have image data or a loaded image
        guard imageData == nil,
              loadedImage == nil,
              let urlString = imageURL,
              !urlString.isEmpty else {
            return
        }

        // Check if this is a local asset name (no URL scheme, no slashes)
        // Demo team members use asset names like "pete", "nick", etc.
        if !urlString.contains("/") && !urlString.contains(":") {
            if let assetImage = UIImage(named: urlString) {
                self.loadedImage = assetImage
                return
            }
        }

        // Fix URLs that start with // by adding https:
        var fixedURLString = urlString
        if urlString.hasPrefix("//") {
            fixedURLString = "https:" + urlString
        }

        guard let url = URL(string: fixedURLString) else {
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
                await MainActor.run {
                    self.isLoading = false
                }
            }
        }
    }
}

// MARK: - Previews
#Preview("User Avatars") {
    VStack(spacing: 20) {
        // With image
        UserAvatar(
            firstName: "John",
            lastName: "Doe",
            imageURL: "https://example.com/avatar.jpg",
            size: 60
        )
        
        // Without image - default initials
        UserAvatar(
            firstName: "Jane",
            lastName: "Smith",
            size: 60,
            backgroundColor: OPSStyle.Colors.primaryAccent
        )
        
        // Different sizes
        HStack(spacing: 20) {
            UserAvatar(firstName: "A", lastName: "B", size: 30)
            UserAvatar(firstName: "C", lastName: "D", size: 40)
            UserAvatar(firstName: "E", lastName: "F", size: 50)
            UserAvatar(firstName: "G", lastName: "H", size: 60)
        }
    }
    .padding()
    .background(OPSStyle.Colors.background)
}
