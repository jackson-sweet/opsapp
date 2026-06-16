//
//  PresignedURLUploadService.swift
//  OPS
//
//  Created by Assistant on 2025-06-03.
//

import Foundation
import SwiftUI
// FirebaseAuthService used for token retrieval (Firebase Auth migration)

/// Service for handling image uploads using presigned URLs from ops-web
@MainActor
class PresignedURLUploadService {
    static let shared = PresignedURLUploadService()

    private init() {}

    // MARK: - Data Models

    /// Response from ops-web presign endpoint
    struct PresignedURLResponse: Codable {
        let uploadUrl: String
        let publicUrl: String
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
                    imageData: imageData,
                    contentType: "image/jpeg"
                )
                
                // Step 3: Add to results
                uploadedImages.append((url: presignedResponse.publicUrl, filename: filename))
                
            } catch {
                throw error
            }
        }
        

        return uploadedImages
    }

    /// Upload images for a project note attachment
    func uploadNoteImages(_ images: [UIImage], projectId: String, companyId: String) async throws -> [String] {
        var urls: [String] = []

        for (index, image) in images.enumerated() {
            let processedImage = resizeImageIfNeeded(image)
            let compressionQuality = getAdaptiveCompressionQuality(for: processedImage)

            guard let imageData = processedImage.jpegData(compressionQuality: compressionQuality) else {
                continue
            }

            let timestamp = Date().timeIntervalSince1970
            let filename = "note_\(timestamp)_\(index).jpg"

            let presignedResponse = try await requestPresignedURL(
                filename: filename,
                contentType: "image/jpeg",
                folder: "notes/\(companyId)/\(projectId)"
            )

            try await uploadToPresignedURL(
                presignedResponse: presignedResponse,
                imageData: imageData,
                contentType: "image/jpeg"
            )

            urls.append(presignedResponse.publicUrl)
        }

        return urls
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
            imageData: imageData,
            contentType: "image/jpeg"
        )

        print("[PRESIGNED_UPLOAD] ✅ Profile image uploaded successfully: \(presignedResponse.publicUrl)")
        return presignedResponse.publicUrl
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
            imageData: imageData,
            contentType: "image/jpeg"
        )

        print("[PRESIGNED_UPLOAD] ✅ Logo uploaded successfully: \(presignedResponse.publicUrl)")
        return presignedResponse.publicUrl
    }

    /// Upload a client profile image using a presigned URL. Mirrors the 512px
    /// square crop the legacy direct-S3 path produced.
    func uploadClientProfileImage(_ image: UIImage, clientId: String, companyId: String) async throws -> String {
        let resizedImage = resizeImageToSquare(image, maxSize: 512)
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.8) else {
            throw UploadError.invalidResponse
        }

        let timestamp = Date().timeIntervalSince1970
        let filename = "client_\(clientId)_\(timestamp).jpg"

        // `client-images/*` is the bucket's public-read prefix for client
        // avatars (the legacy direct-S3 path stored these under the public
        // `company-*` prefix). Keep them publicly displayable.
        let presignedResponse = try await requestPresignedURL(
            filename: filename,
            contentType: "image/jpeg",
            folder: "client-images/\(companyId)"
        )
        try await uploadToPresignedURL(
            presignedResponse: presignedResponse,
            imageData: imageData,
            contentType: "image/jpeg"
        )
        return presignedResponse.publicUrl
    }

    /// Upload an expense receipt (full image + thumbnail) using presigned URLs.
    /// Returns (fullUrl, thumbnailUrl); on thumbnail failure the full URL is
    /// returned for both, matching the legacy direct-S3 behavior.
    func uploadExpenseReceipt(_ image: UIImage, expenseId: String, companyId: String) async throws -> (url: String, thumbnailUrl: String) {
        // Full-size receipt (max 2048px, quality 0.85).
        let fullImage = resizeImageIfNeeded(image)
        guard let fullData = fullImage.jpegData(compressionQuality: 0.85) else {
            throw UploadError.invalidResponse
        }

        let timestamp = Date().timeIntervalSince1970
        let filename = "receipt_\(expenseId)_\(timestamp).jpg"
        let thumbFilename = "receipt_\(expenseId)_\(timestamp)_thumb.jpg"

        // Receipts render via their stored public URL, so the bucket must grant
        // public-read on `expenses/*` (the legacy direct-S3 path stored receipts
        // under the public `company-*` prefix). See the AWS bucket-policy step in
        // the credential-removal runbook.
        let fullPresign = try await requestPresignedURL(
            filename: filename,
            contentType: "image/jpeg",
            folder: "expenses/\(companyId)"
        )
        try await uploadToPresignedURL(
            presignedResponse: fullPresign,
            imageData: fullData,
            contentType: "image/jpeg"
        )

        // Thumbnail (512px square, quality 0.7). Best-effort — reuse the full
        // URL for both if thumbnail generation or upload fails.
        guard let thumbData = resizeImageToSquare(image, maxSize: 512)
            .jpegData(compressionQuality: 0.7) else {
            return (url: fullPresign.publicUrl, thumbnailUrl: fullPresign.publicUrl)
        }

        do {
            let thumbPresign = try await requestPresignedURL(
                filename: thumbFilename,
                contentType: "image/jpeg",
                folder: "expenses/\(companyId)"
            )
            try await uploadToPresignedURL(
                presignedResponse: thumbPresign,
                imageData: thumbData,
                contentType: "image/jpeg"
            )
            return (url: fullPresign.publicUrl, thumbnailUrl: thumbPresign.publicUrl)
        } catch {
            return (url: fullPresign.publicUrl, thumbnailUrl: fullPresign.publicUrl)
        }
    }

    // MARK: - Server-Mediated Operations
    //
    // These call dedicated ops-web endpoints rather than the presign flow,
    // because the server does extra work that must not run with client-held
    // credentials: writing the `bug_reports.screenshot_url` row for
    // screenshots, and authorizing the object key against the caller's company
    // before issuing an S3 delete.

    /// Upload a bug-report screenshot via `/api/bug-reports/screenshot`. The
    /// server stores the object and writes `bug_reports.screenshot_url` itself,
    /// so the caller does not persist a URL. Throws on failure (best-effort).
    func uploadBugReportScreenshot(_ image: UIImage, reportId: String, companyId: String) async throws {
        // Max 1024px longest edge, quality 0.7 — matches the legacy sizing and
        // stays well under the endpoint's 8MB cap.
        let processed = resizeToFit(image, maxDimension: 1024)
        guard let imageData = processed.jpegData(compressionQuality: 0.7) else {
            throw UploadError.invalidResponse
        }

        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            throw UploadError.invalidResponse
        }

        let endpoint = AppConfiguration.apiBaseURL.appendingPathComponent("/api/bug-reports/screenshot")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        func appendField(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        appendField("reportId", reportId)
        appendField("companyId", companyId)
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"screenshot.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.s3Error(statusCode: httpResponse.statusCode)
        }
    }

    /// Delete a previously-uploaded object via `/api/uploads/delete`. The
    /// server extracts the object key from the URL and authorizes it against
    /// the caller's company before deleting, so no client AWS credentials are
    /// required. Best-effort: callers swallow errors (orphan cleanup only).
    func deleteImage(url: String) async throws {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            throw UploadError.invalidResponse
        }

        let endpoint = AppConfiguration.apiBaseURL.appendingPathComponent("/api/uploads/delete")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "url", value: url)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.s3Error(statusCode: httpResponse.statusCode)
        }
    }

    /// Resize so the longest edge is at most `maxDimension`, preserving aspect
    /// ratio. Returns the original if already within bounds.
    private func resizeToFit(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        guard image.size.width > maxDimension || image.size.height > maxDimension else {
            return image
        }
        let aspectRatio = image.size.width / image.size.height
        let newSize = image.size.width > image.size.height
            ? CGSize(width: maxDimension, height: maxDimension / aspectRatio)
            : CGSize(width: maxDimension * aspectRatio, height: maxDimension)
        UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resized = UIGraphicsGetImageFromCurrentImageContext() ?? image
        UIGraphicsEndImageContext()
        return resized
    }

    // MARK: - Generic Upload (used by PhotoProcessor)

    /// Upload raw image data to S3 via presigned URL, returning the public URL.
    func uploadImageData(_ data: Data, filename: String, folder: String) async throws -> String {
        let presignedResponse = try await requestPresignedURL(
            filename: filename,
            contentType: "image/jpeg",
            folder: folder
        )
        try await uploadToPresignedURL(
            presignedResponse: presignedResponse,
            imageData: data,
            contentType: "image/jpeg"
        )
        return presignedResponse.publicUrl
    }

    /// Upload arbitrary asset bytes (LiDAR dimensioned-capture pipeline per spec §7).
    /// Content type travels with the presign request AND the S3 PUT so the bucket
    /// stores the correct MIME — `image/heic` for the HEIC photo, `application/json`
    /// for the sidecar metadata, `application/octet-stream` for the FP32 raw depth.
    /// Returns the publicly resolvable S3 URL.
    func uploadAsset(
        _ data: Data,
        filename: String,
        folder: String,
        contentType: String
    ) async throws -> String {
        let presignedResponse = try await requestPresignedURL(
            filename: filename,
            contentType: contentType,
            folder: folder
        )
        try await uploadToPresignedURL(
            presignedResponse: presignedResponse,
            imageData: data,
            contentType: contentType
        )
        return presignedResponse.publicUrl
    }

    // MARK: - Private Methods

    /// Get presigned URL from ops-web
    private func getPresignedURL(filename: String, projectId: String, companyId: String) async throws -> PresignedURLResponse {
        return try await requestPresignedURL(
            filename: filename,
            contentType: "image/jpeg",
            folder: "projects/\(companyId)/\(projectId)"
        )
    }

    /// Get presigned URL for profile or logo image
    private func getPresignedURLForProfile(filename: String, imageType: String, companyId: String) async throws -> PresignedURLResponse {
        print("[PRESIGNED_UPLOAD] Requesting presigned URL for \(imageType): \(filename)")
        return try await requestPresignedURL(
            filename: filename,
            contentType: "image/jpeg",
            folder: "\(imageType)s/\(companyId)"
        )
    }

    /// Shared presigned URL request to ops-web
    private func requestPresignedURL(filename: String, contentType: String, folder: String) async throws -> PresignedURLResponse {
        let idToken: String
        do {
            idToken = try await FirebaseAuthService.shared.getIDToken()
        } catch {
            throw UploadError.invalidResponse
        }
        let url = AppConfiguration.apiBaseURL.appendingPathComponent("/api/uploads/presign")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "filename", value: filename),
            URLQueryItem(name: "contentType", value: contentType),
            URLQueryItem(name: "folder", value: folder)
        ]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw UploadError.presignError(statusCode: httpResponse.statusCode)
        }

        return try JSONDecoder().decode(PresignedURLResponse.self, from: data)
    }

    /// Upload data to S3 using a presigned PUT URL. The `contentType` parameter
    /// matches the one passed to the presign step — required for non-image assets
    /// (HEIC photo, sidecar JSON, FP32 raw depth) introduced by the LiDAR
    /// dimensioned-capture pipeline.
    private func uploadToPresignedURL(
        presignedResponse: PresignedURLResponse,
        imageData: Data,
        contentType: String
    ) async throws {
        guard let url = URL(string: presignedResponse.uploadUrl) else {
            throw UploadError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")
        request.httpBody = imageData

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UploadError.invalidResponse
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
    case presignError(statusCode: Int)
    case s3Error(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .invalidURL:
            return "Invalid upload URL"
        case .presignError(let code):
            return "Presign request error (status: \(code))"
        case .s3Error(let code):
            return "S3 upload error (status: \(code))"
        }
    }
}
