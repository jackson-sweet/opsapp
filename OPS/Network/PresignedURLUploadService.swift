//
//  PresignedURLUploadService.swift
//  OPS
//
//  Created by Assistant on 2025-06-03.
//

import Foundation
import SwiftUI

/// Service for handling image uploads using presigned URLs from AWS Lambda
@MainActor
class PresignedURLUploadService {
    // Singleton instance
    static let shared = PresignedURLUploadService()
    
    private init() {}
    
    // MARK: - Data Models
    
    /// Response from Lambda function for presigned URL
    struct PresignedURLResponse: Codable {
        let uploadUrl: String
        let fileUrl: String
        let fields: [String: String]?
    }
    
    /// Request to Lambda for presigned URL (project images)
    struct PresignedURLRequest: Codable {
        let filename: String
        let contentType: String
        let projectId: String
        let companyId: String
    }

    /// Request to Lambda for presigned URL (profile/logo images)
    struct ProfilePresignedURLRequest: Codable {
        let filename: String
        let contentType: String
        let imageType: String  // "profile" or "logo"
        let companyId: String
    }
    
    // MARK: - Public Methods
    
    /// Upload multiple images using presigned URLs
    func uploadProjectImages(_ images: [UIImage], for project: Project, companyId: String) async throws -> [(url: String, filename: String)] {
        
        var uploadedImages: [(url: String, filename: String)] = []
        
        // Get existing project images to check for duplicates
        let existingImages = project.getProjectImages()
        var existingFilenames = Set<String>()
        
        // Extract filenames from existing URLs
        for imageURL in existingImages {
            if let url = URL(string: imageURL),
               let filename = url.lastPathComponent.removingPercentEncoding {
                existingFilenames.insert(filename)
            }
        }
        
        
        // Process each image
        for (index, image) in images.enumerated() {
            
            // Resize image if needed
            let processedImage = resizeImageIfNeeded(image)
            
            // Use adaptive compression based on image size
            let compressionQuality = getAdaptiveCompressionQuality(for: processedImage)
            
            // Compress image
            guard let imageData = processedImage.jpegData(compressionQuality: compressionQuality) else {
                continue
            }
            
            let sizeInMB = Double(imageData.count) / (1024 * 1024)
            
            // Generate filename with duplicate checking
            let streetPrefix = extractStreetAddress(from: project.address ?? "")
            let timestamp = Date().timeIntervalSince1970
            var attemptCount = 0
            var filename = ""
            
            // Keep generating filenames until we find a unique one
            repeat {
                let uniqueSuffix = attemptCount > 0 ? "_\(attemptCount)" : ""
                filename = "\(streetPrefix)_IMG_\(timestamp)_\(index)\(uniqueSuffix).jpg"
                attemptCount += 1
            } while existingFilenames.contains(filename) && attemptCount < 100
            
            if existingFilenames.contains(filename) {
                continue
            }
            
            // Add to our tracking set
            existingFilenames.insert(filename)
            
            
            do {
                // Step 1: Get presigned URL from Lambda
                let presignedResponse = try await getPresignedURL(
                    filename: filename,
                    projectId: project.id,
                    companyId: companyId
                )
                
                // Step 2: Upload image to S3 using presigned URL
                try await uploadToPresignedURL(
                    presignedResponse: presignedResponse,
                    imageData: imageData
                )
                
                // Step 3: Add to results
                uploadedImages.append((url: presignedResponse.fileUrl, filename: filename))
                
            } catch {
                throw error
            }
        }
        

        return uploadedImages
    }

    /// Upload a user profile image using presigned URL
    func uploadProfileImage(_ image: UIImage, userId: String, companyId: String) async throws -> String {
        print("[PRESIGNED_UPLOAD] Starting profile image upload for user: \(userId)")

        // Resize to maximum 800x800
        let maxSize: CGFloat = 800
        let resizedImage = resizeImageToSquare(image, maxSize: maxSize)

        // Compress to JPEG
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw UploadError.invalidResponse
        }

        let sizeInMB = Double(imageData.count) / (1024 * 1024)
        print("[PRESIGNED_UPLOAD] Image size: \(String(format: "%.2f", sizeInMB))MB")

        // Generate filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "profile_\(userId)_\(timestamp).jpg"

        // Get presigned URL
        let presignedResponse = try await getPresignedURLForProfile(
            filename: filename,
            imageType: "profile",
            companyId: companyId
        )

        // Upload to S3
        try await uploadToPresignedURL(
            presignedResponse: presignedResponse,
            imageData: imageData
        )

        print("[PRESIGNED_UPLOAD] ✅ Profile image uploaded successfully: \(presignedResponse.fileUrl)")
        return presignedResponse.fileUrl
    }

    /// Upload a company logo using presigned URL
    func uploadCompanyLogo(_ image: UIImage, companyId: String) async throws -> String {
        print("[PRESIGNED_UPLOAD] Starting logo upload for company: \(companyId)")

        // Resize to maximum 1000x1000
        let maxSize: CGFloat = 1000
        let resizedImage = resizeImageToSquare(image, maxSize: maxSize)

        // Compress to JPEG
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.85) else {
            throw UploadError.invalidResponse
        }

        let sizeInMB = Double(imageData.count) / (1024 * 1024)
        print("[PRESIGNED_UPLOAD] Logo size: \(String(format: "%.2f", sizeInMB))MB")

        // Generate filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "logo_\(companyId)_\(timestamp).jpg"

        // Get presigned URL
        let presignedResponse = try await getPresignedURLForProfile(
            filename: filename,
            imageType: "logo",
            companyId: companyId
        )

        // Upload to S3
        try await uploadToPresignedURL(
            presignedResponse: presignedResponse,
            imageData: imageData
        )

        print("[PRESIGNED_UPLOAD] ✅ Logo uploaded successfully: \(presignedResponse.fileUrl)")
        return presignedResponse.fileUrl
    }

    // MARK: - Private Methods
    
    /// Get presigned URL from Lambda function
    private func getPresignedURL(filename: String, projectId: String, companyId: String) async throws -> PresignedURLResponse {
        
        // Create request to Lambda
        let lambdaRequest = PresignedURLRequest(
            filename: filename,
            contentType: "image/jpeg",
            projectId: projectId,
            companyId: companyId
        )
        
        // Lambda endpoint for getting presigned URLs
        // TODO: Update this to match your actual Bubble workflow name
        let lambdaURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/get_presigned_url")!
        
        var request = URLRequest(url: lambdaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let requestData = try JSONEncoder().encode(lambdaRequest)
        request.httpBody = requestData
        
        if let bodyString = String(data: requestData, encoding: .utf8) {
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        
        if let responseString = String(data: data, encoding: .utf8) {
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.lambdaError(statusCode: httpResponse.statusCode)
        }
        
        let presignedResponse = try JSONDecoder().decode(PresignedURLResponse.self, from: data)
        
        return presignedResponse
    }

    /// Get presigned URL for profile or logo image
    private func getPresignedURLForProfile(filename: String, imageType: String, companyId: String) async throws -> PresignedURLResponse {
        print("[PRESIGNED_UPLOAD] Requesting presigned URL for \(imageType): \(filename)")

        // Create request to Lambda
        let lambdaRequest = ProfilePresignedURLRequest(
            filename: filename,
            contentType: "image/jpeg",
            imageType: imageType,
            companyId: companyId
        )

        // Lambda endpoint for getting presigned URLs
        let lambdaURL = URL(string: "\(AppConfiguration.bubbleBaseURL)/api/1.1/wf/get_presigned_url_profile")!

        var request = URLRequest(url: lambdaURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let requestData = try JSONEncoder().encode(lambdaRequest)
        request.httpBody = requestData

        if let bodyString = String(data: requestData, encoding: .utf8) {
            print("[PRESIGNED_UPLOAD] Request body: \(bodyString)")
        }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        print("[PRESIGNED_UPLOAD] Response status: \(httpResponse.statusCode)")

        if let responseString = String(data: data, encoding: .utf8) {
            print("[PRESIGNED_UPLOAD] Response body: \(responseString)")
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.lambdaError(statusCode: httpResponse.statusCode)
        }

        let presignedResponse = try JSONDecoder().decode(PresignedURLResponse.self, from: data)

        return presignedResponse
    }

    /// Upload image data to S3 using presigned URL
    private func uploadToPresignedURL(presignedResponse: PresignedURLResponse, imageData: Data) async throws {
        
        guard let url = URL(string: presignedResponse.uploadUrl) else {
            throw UploadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // Check if this is a POST with form fields or a simple PUT
        if let fields = presignedResponse.fields, !fields.isEmpty {
            // POST with multipart form data
            request.httpMethod = "POST"
            
            let boundary = UUID().uuidString
            request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            var body = Data()
            
            // Add form fields
            for (key, value) in fields {
                body.append("--\(boundary)\r\n".data(using: .utf8)!)
                body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                body.append("\(value)\r\n".data(using: .utf8)!)
            }
            
            // Add file data
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"file\"; filename=\"image.jpg\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
            body.append("--\(boundary)--\r\n".data(using: .utf8)!)
            
            request.httpBody = body
            
        } else {
            // Simple PUT request
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = imageData
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        
        
        if !data.isEmpty, let responseString = String(data: data, encoding: .utf8) {
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.s3Error(statusCode: httpResponse.statusCode)
        }
        
    }
    
    /// Extract street address for filename prefix
    private func extractStreetAddress(from address: String) -> String {
        let cleanAddress = address.replacingOccurrences(of: "_", with: " ")
        let components = cleanAddress.components(separatedBy: ",")
        let streetPart = components.first ?? ""
        
        let words = streetPart.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        
        var streetAddress = ""
        for (index, word) in words.enumerated() {
            if word.lowercased().contains("apt") || word.lowercased().contains("unit") || word.lowercased().contains("#") {
                break
            }
            
            if index == 0 || index == 1 || (index == 2 && !word.isEmpty) {
                streetAddress += word
            }
        }
        
        if streetAddress.isEmpty {
            streetAddress = streetPart
        }
        
        streetAddress = streetAddress.replacingOccurrences(of: " ", with: "")
        streetAddress = streetAddress.replacingOccurrences(of: ".", with: "")
        streetAddress = streetAddress.replacingOccurrences(of: ",", with: "")
        
        if streetAddress.isEmpty {
            streetAddress = "NoAddress"
        }
        
        return streetAddress
    }
    
    // MARK: - Image Processing Helpers
    
    /// Resize image if it exceeds maximum dimensions
    private func resizeImageIfNeeded(_ image: UIImage) -> UIImage {
        let maxDimension: CGFloat = 2048 // Maximum width or height
        
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        
        let aspectRatio = image.size.width / image.size.height
        let newSize: CGSize
        
        if image.size.width > image.size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspectRatio)
        } else {
            newSize = CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        }
        
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        
        return resizedImage
    }
    
    /// Get adaptive compression quality based on image size
    private func getAdaptiveCompressionQuality(for image: UIImage) -> CGFloat {
        let pixelCount = image.size.width * image.size.height

        // Higher resolution images get more compression
        if pixelCount > 4_000_000 { // > 4MP
            return 0.5
        } else if pixelCount > 2_000_000 { // > 2MP
            return 0.6
        } else if pixelCount > 1_000_000 { // > 1MP
            return 0.7
        } else {
            return 0.8
        }
    }

    /// Resize image to square with maximum dimension
    private func resizeImageToSquare(_ image: UIImage, maxSize: CGFloat) -> UIImage {
        // If already smaller than maxSize, return as-is
        guard image.size.width > maxSize || image.size.height > maxSize else {
            return image
        }

        // Calculate target size (square, centered crop)
        let dimension = min(image.size.width, image.size.height)
        let scale = maxSize / dimension

        // Calculate target size
        let targetSize = CGSize(width: dimension * scale, height: dimension * scale)

        // Calculate crop rect (center crop)
        let xOffset = (image.size.width - dimension) / 2
        let yOffset = (image.size.height - dimension) / 2
        let cropRect = CGRect(x: xOffset, y: yOffset, width: dimension, height: dimension)

        // Crop and resize
        guard let cgImage = image.cgImage?.cropping(to: cropRect) else {
            return image
        }

        UIGraphicsBeginImageContextWithOptions(targetSize, false, 1.0)
        let context = UIGraphicsGetCurrentContext()
        context?.interpolationQuality = .high

        UIImage(cgImage: cgImage).draw(in: CGRect(origin: .zero, size: targetSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()

        return resizedImage
    }
}

// MARK: - Error Types

enum UploadError: LocalizedError {
    case invalidResponse
    case invalidURL
    case lambdaError(statusCode: Int)
    case s3Error(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid upload URL"
        case .lambdaError(let code):
            return "Lambda function error (status: \(code))"
        case .s3Error(let code):
            return "S3 upload error (status: \(code))"
        }
    }
}
