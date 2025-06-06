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
        print("🚀 S3UploadService: Starting upload of \(images.count) images")
        print("  - Project: \(project.id) - \(project.title)")
        print("  - Company ID: \(companyId)")
        print("  - Project Address: \(project.address)")
        
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
            print("  - Original size: \(image.size.width)x\(image.size.height)")
            
            // Compress image
            guard let imageData = image.jpegData(compressionQuality: 0.7) else {
                print("❌ Failed to compress image at index \(index)")
                continue
            }
            
            print("  - Compressed size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
            
            // Generate filename with street address prefix
            let streetPrefix = extractStreetAddress(from: project.address)
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
                print("⚠️ Warning: Could not generate unique filename after 100 attempts, skipping image")
                continue
            }
            
            // Add to our tracking set
            existingFilenames.insert(filename)
            
            print("  - Generated filename: \(filename)")
            print("  - Street prefix: \(streetPrefix)")
            
            // Upload to S3
            do {
                let s3URL = try await uploadImageToS3(
                    imageData: imageData,
                    filename: filename,
                    companyId: companyId,
                    projectId: project.id
                )
                
                uploadedImages.append((url: s3URL, filename: filename))
                print("✅ Successfully uploaded image \(index + 1)/\(images.count)")
                print("  - S3 URL: \(s3URL)")
            } catch {
                print("❌ Failed to upload image \(index + 1): \(error)")
                print("  - Error type: \(type(of: error))")
                print("  - Error description: \(error.localizedDescription)")
                throw error
            }
        }
        
        print("\n📊 Upload Summary:")
        print("  - Total images: \(images.count)")
        print("  - Successfully uploaded: \(uploadedImages.count)")
        print("  - Failed: \(images.count - uploadedImages.count)")
        
        return uploadedImages
    }
    
    /// Delete an image from S3
    func deleteImageFromS3(url: String, companyId: String, projectId: String) async throws {
        // Extract filename from URL
        guard let filename = URL(string: url)?.lastPathComponent else {
            throw S3Error.invalidURL
        }
        
        let objectKey = "company-\(companyId)/\(projectId)/photos/\(filename)"
        let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "DELETE"
        
        // Add AWS authentication headers
        addAWSAuthHeaders(to: &request, method: "DELETE", path: "/\(objectKey)")
        
        let (_, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw S3Error.deleteFailed
        }
        
        print("S3UploadService: Successfully deleted image from S3: \(filename)")
    }
    
    // MARK: - Private Methods
    
    private func uploadImageToS3(imageData: Data, filename: String, companyId: String, projectId: String) async throws -> String {
        let objectKey = "company-\(companyId)/\(projectId)/photos/\(filename)"
        let endpoint = "https://\(bucketName).s3.\(region).amazonaws.com/\(objectKey)"
        
        print("🔷 S3 Upload Request:")
        print("  - Endpoint: \(endpoint)")
        print("  - Object Key: \(objectKey)")
        print("  - Image Size: \(imageData.count) bytes (\(imageData.count / 1024)KB)")
        print("  - Company ID: \(companyId)")
        print("  - Project ID: \(projectId)")
        print("  - Filename: \(filename)")
        
        var request = URLRequest(url: URL(string: endpoint)!)
        request.httpMethod = "PUT"
        request.httpBody = imageData
        request.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(imageData.count)", forHTTPHeaderField: "Content-Length")
        
        // Add AWS authentication headers
        addAWSAuthHeaders(to: &request, method: "PUT", path: "/\(objectKey)", payload: imageData)
        
        // Log all headers for debugging
        print("🔷 S3 Request Headers:")
        request.allHTTPHeaderFields?.forEach { key, value in
            if key.lowercased().contains("authorization") {
                // Partially mask sensitive auth header
                let masked = value.prefix(30) + "..." + value.suffix(10)
                print("  - \(key): \(masked)")
            } else {
                print("  - \(key): \(value)")
            }
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                print("❌ S3 Upload Error: Invalid response type")
                throw S3Error.uploadFailed
            }
            
            print("🔶 S3 Response:")
            print("  - Status Code: \(httpResponse.statusCode)")
            print("  - Headers: \(httpResponse.allHeaderFields)")
            
            if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
                print("  - Response Body: \(responseString)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                print("❌ S3 Upload Failed with status: \(httpResponse.statusCode)")
                if let errorBody = String(data: data, encoding: .utf8) {
                    print("❌ Error Response: \(errorBody)")
                }
                throw S3Error.uploadFailed
            }
            
            print("✅ S3 Upload Successful: \(endpoint)")
            return endpoint
            
        } catch {
            print("❌ S3 Upload Error: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func addAWSAuthHeaders(to request: inout URLRequest, method: String, path: String, payload: Data? = nil) {
        print("🔐 AWS Authentication Header Generation:")
        print("  - Method: \(method)")
        print("  - Path: \(path)")
        print("  - Bucket: \(bucketName)")
        print("  - Region: \(region)")
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")
        let dateTime = dateFormatter.string(from: Date())
        
        let dateStamp = String(dateTime.prefix(8))
        
        print("  - DateTime: \(dateTime)")
        print("  - DateStamp: \(dateStamp)")
        
        // Create canonical request
        let canonicalHeaders = "host:\(bucketName).s3.\(region).amazonaws.com\nx-amz-date:\(dateTime)\n"
        let signedHeaders = "host;x-amz-date"
        
        let payloadHash = payload?.sha256Hash() ?? "UNSIGNED-PAYLOAD"
        print("  - Payload Hash: \(payloadHash)")
        
        let canonicalRequest = """
        \(method)
        \(path)
        
        \(canonicalHeaders)
        \(signedHeaders)
        \(payloadHash)
        """
        
        print("  - Canonical Request:")
        print("    \(canonicalRequest.replacingOccurrences(of: "\n", with: "\\n"))")
        
        // Create string to sign
        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = "\(dateStamp)/\(region)/s3/aws4_request"
        let canonicalRequestHash = canonicalRequest.sha256Hash()
        
        print("  - Canonical Request Hash: \(canonicalRequestHash)")
        print("  - Credential Scope: \(credentialScope)")
        
        let stringToSign = """
        \(algorithm)
        \(dateTime)
        \(credentialScope)
        \(canonicalRequestHash)
        """
        
        print("  - String to Sign:")
        print("    \(stringToSign.replacingOccurrences(of: "\n", with: "\\n"))")
        
        // Calculate signature
        let signature = calculateSignature(
            stringToSign: stringToSign,
            dateStamp: dateStamp,
            region: region,
            service: "s3"
        )
        
        print("  - Calculated Signature: \(signature)")
        
        // Create authorization header
        let authorization = "\(algorithm) Credential=\(accessKeyId)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        
        print("  - Authorization Header: \(authorization.prefix(50))...")
        
        // Set headers
        request.setValue(authorization, forHTTPHeaderField: "Authorization")
        request.setValue(dateTime, forHTTPHeaderField: "X-Amz-Date")
        request.setValue(payloadHash, forHTTPHeaderField: "X-Amz-Content-SHA256")
        request.setValue("\(bucketName).s3.\(region).amazonaws.com", forHTTPHeaderField: "Host")
        
        print("  - Headers set successfully")
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
}

// MARK: - Error Types

enum S3Error: LocalizedError {
    case uploadFailed
    case deleteFailed
    case invalidURL
    case bubbleAPIFailed
    
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
