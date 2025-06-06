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
    
    /// Request to Lambda for presigned URL
    struct PresignedURLRequest: Codable {
        let filename: String
        let contentType: String
        let projectId: String
        let companyId: String
    }
    
    // MARK: - Public Methods
    
    /// Upload multiple images using presigned URLs
    func uploadProjectImages(_ images: [UIImage], for project: Project, companyId: String) async throws -> [(url: String, filename: String)] {
        print("🚀 PresignedURLUploadService: Starting upload of \(images.count) images")
        print("  - Project: \(project.id) - \(project.title)")
        print("  - Company ID: \(companyId)")
        
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
        
        print("🔍 Checking for duplicate images. Existing filenames: \(existingFilenames.count)")
        
        // Process each image
        for (index, image) in images.enumerated() {
            print("\n📸 Processing image \(index + 1)/\(images.count)")
            
            // Compress image
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to compress image at index \(index)")
                continue
            }
            
            print("  - Compressed size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
            
            // Generate filename with duplicate checking
            let streetPrefix = extractStreetAddress(from: project.address)
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
                print("⚠️ Warning: Could not generate unique filename after 100 attempts, skipping image")
                continue
            }
            
            // Add to our tracking set
            existingFilenames.insert(filename)
            
            print("  - Generated filename: \(filename)")
            
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
                print("✅ Successfully uploaded image \(index + 1)/\(images.count)")
                print("  - Final URL: \(presignedResponse.fileUrl)")
                
            } catch {
                print("❌ Failed to upload image \(index + 1): \(error)")
                throw error
            }
        }
        
        print("\n📊 Upload Summary:")
        print("  - Total images: \(images.count)")
        print("  - Successfully uploaded: \(uploadedImages.count)")
        
        return uploadedImages
    }
    
    // MARK: - Private Methods
    
    /// Get presigned URL from Lambda function
    private func getPresignedURL(filename: String, projectId: String, companyId: String) async throws -> PresignedURLResponse {
        print("🔷 Requesting presigned URL from Lambda")
        print("  - Filename: \(filename)")
        
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
            print("  - Request body: \(bodyString)")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response from Lambda")
            throw UploadError.invalidResponse
        }
        
        print("🔶 Lambda Response:")
        print("  - Status Code: \(httpResponse.statusCode)")
        
        if let responseString = String(data: data, encoding: .utf8) {
            print("  - Response Body: \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ Lambda request failed with status: \(httpResponse.statusCode)")
            throw UploadError.lambdaError(statusCode: httpResponse.statusCode)
        }
        
        let presignedResponse = try JSONDecoder().decode(PresignedURLResponse.self, from: data)
        print("✅ Got presigned URL: \(presignedResponse.uploadUrl)")
        
        return presignedResponse
    }
    
    /// Upload image data to S3 using presigned URL
    private func uploadToPresignedURL(presignedResponse: PresignedURLResponse, imageData: Data) async throws {
        print("🔷 Uploading to presigned URL")
        print("  - URL: \(presignedResponse.uploadUrl)")
        print("  - Image size: \(imageData.count) bytes")
        
        guard let url = URL(string: presignedResponse.uploadUrl) else {
            throw UploadError.invalidURL
        }
        
        var request = URLRequest(url: url)
        
        // Check if this is a POST with form fields or a simple PUT
        if let fields = presignedResponse.fields, !fields.isEmpty {
            // POST with multipart form data
            print("  - Using POST with form fields")
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
            print("  - Using PUT request")
            request.httpMethod = "PUT"
            request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            request.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = imageData
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response from S3")
            throw UploadError.invalidResponse
        }
        
        print("🔶 S3 Response:")
        print("  - Status Code: \(httpResponse.statusCode)")
        
        if !data.isEmpty, let responseString = String(data: data, encoding: .utf8) {
            print("  - Response Body: \(responseString)")
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ S3 upload failed with status: \(httpResponse.statusCode)")
            throw UploadError.s3Error(statusCode: httpResponse.statusCode)
        }
        
        print("✅ Successfully uploaded to S3")
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
