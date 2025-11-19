//
//  S3UploadService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-30.
//

import Foundation
import SwiftUI
import CryptoKit

/// Service for handling AWS S3 file uploads
@MainActor
class S3UploadService {
    // AWS Configuration
    private let accessKeyId = "AKIA35P7FAPD67GCBP63"
    private let secretAccessKey = "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"
    private let bucketName = "ops-app-files-prod"
    private let region = "us-west-2"
    
    // Singleton instance
    static let shared = S3UploadService()
    
    private init() {}
    
    // MARK: - Public Methods
    
    /// Upload multiple images to S3 for a project
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
            
            // Resize image if needed to prevent upload issues
            let processedImage = resizeImageIfNeeded(image)
            
            // Use adaptive compression based on image size
            let compressionQuality = getAdaptiveCompressionQuality(for: processedImage)
            
            // Compress image
            guard let imageData = processedImage.jpegData(compressionQuality: compressionQuality) else {
                continue
            }
            
            let sizeInMB = Double(imageData.count) / (1024 * 1024)
            
            // Generate filename with street address prefix
            let streetPrefix = extractStreetAddress(from: project.address ?? "")
            let timestamp = Date().timeIntervalSince1970
            var attemptCount = 0
            var filename = ""
            
            // Keep generating filenames until we find a unique one
            repeat {
                let uniqueSuffix = attemptCount > 0 ? "_\(attemptCount)" : ""
                let originalFilename = "IMG_\(timestamp)_\(index)\(uniqueSuffix).jpg"
                filename = "\(streetPrefix)_\(originalFilename)"
                attemptCount += 1
            } while existingFilenames.contains(filename) && attemptCount < 100
            
            if existingFilenames.contains(filename) {
                continue
            }
            
            // Add to our tracking set
            existingFilenames.insert(filename)
            
            
            // Upload to S3
            do {
                let s3URL = try await uploadImageToS3(
                    imageData: imageData,
                    filename: filename,
                    companyId: companyId,
                    projectId: project.id
                )
                
                uploadedImages.append((url: s3URL, filename: filename))
            } catch {
                throw error
            }
        }
        
        
        return uploadedImages
    }
    
    /// Delete an image from S3
    /// For backward compatibility, still accepts companyId and projectId but will use URL if it's a full S3 URL
    func deleteImageFromS3(url: String, companyId: String, projectId: String) async throws {
        // Extract object key from the URL
        // URL format: https://bucket.s3.region.amazonaws.com/objectKey
        guard let urlComponents = URL(string: url) else {
            throw S3Error.invalidURL
        }

        let objectKey: String

        // Check if this is a full S3 URL
        if url.contains("s3.") && url.contains(".amazonaws.com/") {
            // Extract the object key from the full URL
            // Remove the leading "/" from the path
            objectKey = String(urlComponents.path.dropFirst())
        } else {
            // Legacy path construction for project photos
            let filename = urlComponents.lastPathComponent
            objectKey = "company-\(companyId)/\(projectId)/photos/\(filename)"
        }

        print("[S3_DELETE] Deleting object: \(objectKey)")

        let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"

        // Add AWS authentication headers
        addAWSAuthHeaders(to: &request, method: "DELETE", path: "/\(objectKey)")

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            print("[S3_DELETE] ❌ Delete failed with status: \(statusCode)")
            throw S3Error.deleteFailed
        }

        print("[S3_DELETE] ✅ Successfully deleted from S3")
    }

    /// Upload a user profile image to S3
    func uploadProfileImage(_ image: UIImage, userId: String, companyId: String) async throws -> String {
        print("[S3_UPLOAD] Starting profile image upload for user: \(userId)")

        // Resize to square and compress
        let maxSize: CGFloat = 800
        let resizedImage = resizeImageToSquare(image, maxSize: maxSize)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("[S3_UPLOAD] ❌ Failed to compress profile image")
            throw S3Error.imageConversionFailed
        }

        let sizeInMB = Double(imageData.count) / (1024 * 1024)
        print("[S3_UPLOAD] Profile image size: \(String(format: "%.2f", sizeInMB))MB")

        // Generate filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "profile_\(userId)_\(timestamp).jpg"

        // Upload to S3 at: company-{companyId}/profiles/{filename}
        let objectKey = "company-\(companyId)/profiles/\(filename)"
        let s3URL = try await uploadToS3(imageData: imageData, objectKey: objectKey)

        print("[S3_UPLOAD] ✅ Profile image uploaded: \(s3URL)")
        return s3URL
    }

    /// Upload a company logo to S3
    func uploadCompanyLogo(_ image: UIImage, companyId: String) async throws -> String {
        print("[S3_UPLOAD] Starting logo upload for company: \(companyId)")

        // Resize to square and compress
        let maxSize: CGFloat = 1000
        let resizedImage = resizeImageToSquare(image, maxSize: maxSize)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.85) else {
            print("[S3_UPLOAD] ❌ Failed to compress logo")
            throw S3Error.imageConversionFailed
        }

        let sizeInMB = Double(imageData.count) / (1024 * 1024)
        print("[S3_UPLOAD] Logo size: \(String(format: "%.2f", sizeInMB))MB")

        // Generate filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "logo_\(companyId)_\(timestamp).jpg"

        // Upload to S3 at: company-{companyId}/logos/{filename}
        let objectKey = "company-\(companyId)/logos/\(filename)"
        let s3URL = try await uploadToS3(imageData: imageData, objectKey: objectKey)

        print("[S3_UPLOAD] ✅ Logo uploaded: \(s3URL)")
        return s3URL
    }

    /// Upload a client profile image to S3
    func uploadClientProfileImage(_ image: UIImage, clientId: String, companyId: String) async throws -> String {
        print("[S3_UPLOAD] Starting client profile image upload for client: \(clientId)")

        // Resize to square and compress
        let maxSize: CGFloat = 512
        let resizedImage = resizeImageToSquare(image, maxSize: maxSize)

        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            print("[S3_UPLOAD] ❌ Failed to compress client profile image")
            throw S3Error.imageConversionFailed
        }

        let sizeInMB = Double(imageData.count) / (1024 * 1024)
        print("[S3_UPLOAD] Client profile image size: \(String(format: "%.2f", sizeInMB))MB")

        // Generate filename
        let timestamp = Date().timeIntervalSince1970
        let filename = "client_\(clientId)_\(timestamp).jpg"

        // Upload to S3 at: company-{companyId}/clients/{filename}
        let objectKey = "company-\(companyId)/clients/\(filename)"
        let s3URL = try await uploadToS3(imageData: imageData, objectKey: objectKey)

        print("[S3_UPLOAD] ✅ Client profile image uploaded: \(s3URL)")
        return s3URL
    }

    // MARK: - Private Methods

    /// Generic S3 upload method
    private func uploadToS3(imageData: Data, objectKey: String) async throws -> String {
        let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"

        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PUT"
        request.httpBody = imageData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")

        // Add AWS authentication headers
        addAWSAuthHeaders(to: &request, method: "PUT", path: "/\(objectKey)", payload: imageData)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            print("[S3_UPLOAD] ❌ Upload failed with status: \((response as? HTTPURLResponse)?.statusCode ?? -1)")
            throw S3Error.uploadFailed
        }

        // Return the full S3 URL
        return endpoint
    }

    private func uploadImageToS3(imageData: Data, filename: String, companyId: String, projectId: String) async throws -> String {
        let objectKey = "company-\(companyId)/\(projectId)/photos/\(filename)"
        return try await uploadToS3(imageData: imageData, objectKey: objectKey)
    }
    
    private func addAWSAuthHeaders(to request: inout URLRequest, method: String, path: String, payload: Data? = nil) {
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateTime = dateFormatter.string(from: Date())
        
        let dateStamp = String(dateTime.prefix(8))
        
        
        // Create canonical request
        let canonicalHeaders = "host:\(bucketName).s3.\(region).amazonaws.com\nx-amz-date:\(dateTime)\n"
        let signedHeaders = "host;x-amz-date"
        
        let payloadHash = payload?.sha256Hash() ?? "UNSIGNED-PAYLOAD"
        
        let canonicalRequest = """
        \(method)
        \(path)
        
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHash)
        """
        
        
        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let canonicalRequestHash = canonicalRequest.sha256Hash()
        
        
        let stringToSign = """
        \(algorithm)
        \(dateTime)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        
        // Calculate signature
        let signature = calculateSignature(
            stringToSign: stringToSign,
            dateStamp: dateStamp,
            region: region,
            service: "s3"
        )
        
        
        // Create authorization header
        let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        
        // Set headers
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(dateTime, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-SHA256")
        request.setValue("\(bucketName).s3.\(region).amazonaws.com", forHTTPHeaderField: "Host")
        
    }
    
    private func calculateSignature(stringToSign: String, dateStamp: String, region: String, service: String) -> String {
        let kSecret = "AWS4\(secretAccessKey)".data(using: .utf8)!
        let kDate = HMAC<SHA256>.authenticationCode(for: dateStamp.data(using: .utf8)!, using: SymmetricKey(data: kSecret))
        let kRegion = HMAC<SHA256>.authenticationCode(for: region.data(using: .utf8)!, using: SymmetricKey(data: kDate))
        let kService = HMAC<SHA256>.authenticationCode(for: service.data(using: .utf8)!, using: SymmetricKey(data: kRegion))
        let kSigning = HMAC<SHA256>.authenticationCode(for: "aws4_request".data(using: .utf8)!, using: SymmetricKey(data: kService))
        
        let signature = HMAC<SHA256>.authenticationCode(for: stringToSign.data(using: .utf8)!, using: SymmetricKey(data: kSigning))
        
        return signature.map { String(format: "%02x", $0) }.joined()
    }
    
    private func extractStreetAddress(from address: String) -> String {
        // Remove any existing underscores or special characters
        let cleanAddress = address.replacingOccurrences(of: "_", with: " ")
        
        // Split by comma to get the first part (street address)
        let components = cleanAddress.components(separatedBy: ",")
        let streetPart = components.first ?? ""
        
        // Try to parse street number and name
        let words = streetPart.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " ")
        
        // Simple extraction: take first few words that look like street address
        var streetAddress = ""
        for (index, word) in words.enumerated() {
            // Stop at apartment/unit indicators
            if word.lowercased().contains("apt") || word.lowercased().contains("unit") || word.lowercased().contains("#") {
                break
            }
            
            // Add word to street address
            if index == 0 || index == 1 || (index == 2 && !word.isEmpty) {
                streetAddress += word
            }
        }
        
        // If we couldn't parse anything meaningful, use the whole first part
        if streetAddress.isEmpty {
            streetAddress = streetPart
        }
        
        // Clean up: remove spaces and special characters
        streetAddress = streetAddress.replacingOccurrences(of: " ", with: "")
        streetAddress = streetAddress.replacingOccurrences(of: ".", with: "")
        streetAddress = streetAddress.replacingOccurrences(of: ",", with: "")
        
        // If still empty, use a default
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

    /// Resize image to square with maximum dimension (centered crop)
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

enum S3Error: LocalizedError {
    case uploadFailed
    case deleteFailed
    case invalidURL
    case bubbleAPIFailed
    case imageConversionFailed
    
    var errorDescription: String? {
        switch self {
        case .uploadFailed:
            return "Failed to upload image to S3"
        case .deleteFailed:
            return "Failed to delete image from S3"
        case .invalidURL:
            return "Invalid S3 URL"
        case .bubbleAPIFailed:
            return "OPS Web App upload failed, but database succeeded"
        case .imageConversionFailed:
            return "Failed to convert image to JPEG format"
        }
    }
}

// MARK: - Extensions

extension Data {
    func sha256Hash() -> String {
        let hash = SHA256.hash(data: self)
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    func sha256Hash() -> String {
        let data = self.data(using: .utf8)!
        return data.sha256Hash()
    }
}
