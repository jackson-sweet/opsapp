//
//  UIImage+Extensions.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-03.
//

import UIKit

extension UIImage {
    /// Resize the image to a new size while preserving aspect ratio
    func resized(to targetSize: CGSize) -> UIImage {
        let widthRatio  = targetSize.width  / size.width
        let heightRatio = targetSize.height / size.height
        
        // Use the smaller ratio to ensure the image fits within the target size
        let scaleFactor = min(widthRatio, heightRatio)
        let scaledWidth  = size.width * scaleFactor
        let scaledHeight = size.height * scaleFactor
        let scaledSize = CGSize(width: scaledWidth, height: scaledHeight)
        
        UIGraphicsBeginImageContextWithOptions(scaledSize, false, 0.0)
        draw(in: CGRect(origin: .zero, size: scaledSize))
        let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return scaledImage ?? self
    }
    
    /// Compress the image to a target file size in kilobytes
    func compressToFileSize(_ targetSizeKB: Int) -> Data? {
        // Start with high quality
        var compression: CGFloat = 1.0
        let maxCompression: CGFloat = 0.05 // Don't go below 5% quality
        
        // Get initial data
        guard var imageData = self.jpegData(compressionQuality: compression) else {
            return nil
        }
        
        // Target size in bytes
        let targetSizeBytes = targetSizeKB * 1024
        
        // Incrementally lower quality until we reach the target size
        while imageData.count > targetSizeBytes && compression > maxCompression {
            compression -= 0.1
            
            if let data = self.jpegData(compressionQuality: compression) {
                imageData = data
            } else {
                break
            }
        }
        
        return imageData
    }
}