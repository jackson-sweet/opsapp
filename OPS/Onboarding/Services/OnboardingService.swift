//
//  OnboardingService.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-05.
//

import Foundation

class OnboardingService {
    
    // API base URL
    private let baseURL: URL
    
    init(baseURL: URL = AppConfiguration.bubbleBaseURL) {
        self.baseURL = baseURL
    }
    
    /// Sign up a new user with Bubble API (email and password only)
    /// - Parameters:
    ///   - email: User's email address
    ///   - password: User's password
    ///   - userType: User type (employee or company) - determines which endpoint to use
    /// - Returns: Sign up response with success status and user_id
    func signUpUser(email: String, password: String, userType: UserType) async throws -> SignUpResponse {
        // Use different endpoints based on user type
        let endpoint = userType == .company ? "sign_company_up" : "sign_employee_up"
        
        // Configure API request
        let url = baseURL.appendingPathComponent("api/1.1/wf/\(endpoint)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        // Create request body with only email and password (removed employee_type parameter)
        let parameters: [String: String] = [
            "email": email,
            "password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        // DEBUG: Log the request
        print("\n🔵 SIGNUP API REQUEST:")
        print("Endpoint: \(endpoint)")
        print("URL: \(url.absoluteString)")
        print("Parameters sent:")
        print("  - email: \(email)")
        print("  - password: [REDACTED]")
        print("  - userType: \(userType.rawValue)")
        
        do {
            // Execute network request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            // Debug log the response
            let responseText = String(data: data, encoding: .utf8) ?? "No data"
            
            // Handle non-success status codes, especially 400
            if httpResponse.statusCode == 400 {
                // Try to extract "message" from response body for 400 errors
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    // Extract error message for display in UI
                    print("HTTP 400 error - Message: \(message)")
                    throw SignUpError.serverError(message)
                }
            }
            
            // Parse response
            let signUpResponse = try JSONDecoder().decode(SignUpResponse.self, from: data)
            
            // For debugging, print the structure of the response
            print("\n🟡 SIGNUP - Decoded Response:")
            print("  - wasSuccessful: \(signUpResponse.wasSuccessful)")
            print("  - user_id: \(signUpResponse.extractedUserId ?? "nil")")
            print("  - error_message: \(signUpResponse.error_message ?? "nil")")
            
            if signUpResponse.wasSuccessful {
                if let userId = signUpResponse.extractedUserId {
                } else {
                    // Continue anyway, will be handled in the ViewModel
                }
                
                // Always return the response for successful HTTP status codes
                return signUpResponse
            } else if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                // We have a successful HTTP response but our API indicates failure
                // For Bubble API, we should return the response anyway and let the ViewModel handle it
                print("Signup NOTE: HTTP success but API indicates failure or incomplete response")
                return signUpResponse
            } else {
                // True API failure with error message
                let errorMsg = signUpResponse.error_message ?? "Unknown error during signup"
                print("Signup FAILED: \(errorMsg)")
                throw SignUpError.serverError(errorMsg)
            }
            
            
        } catch let error as SignUpError {
            throw error
        } catch let decodingError as DecodingError {
            print("JSON Decoding error: \(decodingError)")
            throw SignUpError.serverError("Failed to process server response: \(decodingError.localizedDescription)")
        } catch {
            print("Network error during signup: \(error.localizedDescription)")
            throw SignUpError.networkError(error)
        }
    }
    
    /// Join a company with user ID and details
    /// - Parameters:
    ///   - userId: User's unique ID from Bubble
    ///   - firstName: User's first name
    ///   - lastName: User's last name
    ///   - phoneNumber: User's phone number
    ///   - companyCode: Company code to join
    /// - Returns: Join company response with company data
    func joinCompany(userId: String, firstName: String, lastName: String, 
                     phoneNumber: String, companyCode: String) async throws -> JoinCompanyResponse {
        
        // Configure API request
        let url = baseURL.appendingPathComponent("api/1.1/wf/join_company")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        // Create request body with user ID as primary identifier
        let parameters: [String: String] = [
            "user": userId,  // Using 'user' field as you specified
            "name_first": firstName,
            "name_last": lastName,
            "phone": phoneNumber,
            "company_code": companyCode
        ]
        
        // DEBUG: Log the request
        print("\n🔵 JOIN COMPANY API REQUEST:")
        print("URL: \(url.absoluteString)")
        print("Parameters sent:")
        print("  - user: \(userId)")
        print("  - name_first: \(firstName)")
        print("  - name_last: \(lastName)")
        print("  - phone: \(phoneNumber)")
        print("  - company_code: \(companyCode)")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        do {
            // Execute network request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            // Debug log the response
            let responseText = String(data: data, encoding: .utf8) ?? "No data"
            
            // Handle non-success status codes, especially 400
            if httpResponse.statusCode == 400 {
                // Try to extract "message" from response body for 400 errors
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let message = json["message"] as? String {
                    // Extract error message for display in UI
                    print("HTTP 400 error - Message: \(message)")
                    throw SignUpError.serverError(message)
                }
            }
            
            // Parse response
            let joinResponse = try JSONDecoder().decode(JoinCompanyResponse.self, from: data)
            
            // For debugging, print the structure of the response
            print("\n🟢 JOIN COMPANY API RESPONSE:")
            print("Status Code: \(httpResponse.statusCode)")
            print("Raw Response: \(responseText)")
            print("\n🟡 JOIN COMPANY - Decoded Response:")
            print("  - wasSuccessful: \(joinResponse.wasSuccessful)")
            
            // Print detailed company data for debugging
            if let companyData = joinResponse.extractedCompanyData {
            } else {
            }
            
            // Try to be flexible with successful responses
            if joinResponse.wasSuccessful {
                
                if let companyData = joinResponse.extractedCompanyData {
                } else {
                }
                
                // Always return the response for successful join
                return joinResponse
            } else if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                // We received a 200-range status code, so let's consider this a partial success
                // and let the ViewModel decide how to handle it
                return joinResponse
            } else {
                // True API failure with error message
                let errorMsg = joinResponse.error_message ?? "Failed to join company"
                print("Company join FAILED: \(errorMsg)")
                throw SignUpError.companyJoinFailed
            }
            
            
        } catch let error as SignUpError {
            throw error
        } catch let decodingError as DecodingError {
            print("JSON Decoding error: \(decodingError)")
            throw SignUpError.serverError("Failed to process server response: \(decodingError.localizedDescription)")
        } catch {
            print("Network error during company join: \(error.localizedDescription)")
            throw SignUpError.networkError(error)
        }
    }
    
    /// Update company information for business owners
    /// - Parameters:
    ///   - companyId: Existing company ID (if updating existing company)
    ///   - name: Company name
    ///   - email: Company email
    ///   - phone: Company phone (optional)
    ///   - industry: Company industry
    ///   - size: Company size
    ///   - age: Company age
    ///   - address: Company address
    ///   - userId: User ID to associate with company
    ///   - firstName: User's first name
    ///   - lastName: User's last name
    ///   - userPhone: User's phone number
    /// - Returns: Company update response
    func updateCompany(companyId: String?, name: String, email: String, phone: String?, industry: String, size: String, age: String, address: String, userId: String, firstName: String, lastName: String, userPhone: String) async throws -> CompanyUpdateResponse {
        
        let url = baseURL.appendingPathComponent("api/1.1/wf/update_company")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        var parameters: [String: Any] = [
            "name": name,
            "email": email,
            "industry": industry,
            "size": size,
            "age": age,
            "address": address,
            "user": userId,
            "name_first": firstName,
            "name_last": lastName,
            "user_phone": userPhone
        ]
        
        // Include company ID if updating existing company
        if let companyId = companyId, !companyId.isEmpty {
            parameters["company_id"] = companyId
            print("🔵 Updating existing company with ID: \(companyId)")
        } else {
            print("🟡 Creating new company (no existing ID provided)")
        }
        
        if let phone = phone, !phone.isEmpty {
            parameters["phone"] = phone
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        // DEBUG: Log the complete request
        print("\n🔵 UPDATE COMPANY API REQUEST:")
        print("URL: \(url.absoluteString)")
        print("Parameters sent:")
        for (key, value) in parameters {
            if key == "user" {
                print("  - \(key): '\(value)' \(userId.isEmpty ? "(EMPTY STRING!)" : "")")
            } else if key == "user_phone" || key == "name_first" || key == "name_last" {
                print("  - \(key): \(value)")
            } else {
                print("  - \(key): \(value)")
            }
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            
            if let responseString = String(data: data, encoding: .utf8) {
                print("\n🟢 UPDATE COMPANY API RESPONSE:")
                print("Status Code: \(httpResponse.statusCode)")
                print("Raw Response: \(responseString)")
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw SignUpError.serverError("Company update failed with status \(httpResponse.statusCode)")
            }
            
            // First try to parse as JSON to see structure
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in json {
                }
            }
            
            // Try to decode the response
            do {
                let updateResponse = try JSONDecoder().decode(CompanyUpdateResponse.self, from: data)
                
                // Debug the parsed response
                
                if let company = updateResponse.extractedCompany {
                }
                
                return updateResponse
            } catch {
                print("ERROR: Failed to decode CompanyUpdateResponse: \(error)")
                
                // Try a simpler response structure
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Create a manual response if we can extract company ID
                    if let companyId = json["company"] as? String {
                        
                        // Create a response with just the ID
                        let companyData = CompanyResponseData(
                            id: companyId,
                            name: nil,
                            email: nil,
                            phone: nil,
                            industry: nil,
                            size: nil,
                            age: nil,
                            address: nil,
                            code: companyId // Use ID as code
                        )
                        
                        return CompanyUpdateResponse(
                            success: "yes",
                            company: companyData,
                            error_message: nil
                        )
                    }
                }
                
                throw error
            }
            
        } catch let error as SignUpError {
            throw error
        } catch {
            throw SignUpError.networkError(error)
        }
    }
    
    /// Send team member invitations
    /// - Parameters:
    ///   - emails: List of email addresses to invite
    ///   - companyId: Company ID to invite them to
    /// - Returns: Invitation response
    func sendInvites(emails: [String], companyId: String) async throws -> InviteResponse {
        
        let url = baseURL.appendingPathComponent("api/1.1/wf/send_invite")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        let parameters: [String: Any] = [
            "emails": emails,
            "company": companyId
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            
            if let responseString = String(data: data, encoding: .utf8) {
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw SignUpError.serverError("Invite sending failed with status \(httpResponse.statusCode)")
            }
            
            let inviteResponse = try JSONDecoder().decode(InviteResponse.self, from: data)
            return inviteResponse
            
        } catch let error as SignUpError {
            throw error
        } catch {
            throw SignUpError.networkError(error)
        }
    }
}

// MARK: - New Response Models

struct CompanyUpdateResponse: Codable {
    let status: String?
    let response: CompanyResponseWrapper?
    let success: String? // Keep for backward compatibility
    let company: CompanyResponseData? // Keep for backward compatibility
    let user: UserDTO? // New field for user object
    let error_message: String?
    
    private enum CodingKeys: String, CodingKey {
        case status
        case response
        case success
        case company
        case user
        case error_message
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // Try new format first
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.response = try container.decodeIfPresent(CompanyResponseWrapper.self, forKey: .response)
        
        // Fallback to old format
        self.success = try container.decodeIfPresent(String.self, forKey: .success)
        self.company = try container.decodeIfPresent(CompanyResponseData.self, forKey: .company)
        self.user = try container.decodeIfPresent(UserDTO.self, forKey: .user)
        
        self.error_message = try container.decodeIfPresent(String.self, forKey: .error_message)
    }
    
    init(success: String? = nil, company: CompanyResponseData? = nil, user: UserDTO? = nil, error_message: String? = nil) {
        self.status = nil
        self.response = nil
        self.success = success
        self.company = company
        self.user = user
        self.error_message = error_message
    }
    
    var wasSuccessful: Bool {
        return status?.lowercased() == "success" || success?.lowercased() == "yes" || response?.company != nil || company != nil
    }
    
    // Helper to get company data from either format
    var extractedCompany: CompanyResponseData? {
        return response?.company ?? company
    }
}

struct CompanyResponseWrapper: Codable {
    let company: CompanyResponseData?
    let user: UserDTO?
}

struct CompanyResponseData: Codable {
    let _id: String?
    let id: String? // Keep for backward compatibility
    let companyId: String? // The company code field
    let companyName: String?
    let name: String? // Keep for backward compatibility
    let officeEmail: String?
    let email: String? // Keep for backward compatibility
    let phone: String?
    let industry: [String]?
    let companySize: String?
    let size: String? // Keep for backward compatibility
    let companyAge: String?
    let age: String? // Keep for backward compatibility
    let address: String?
    let code: String? // Keep for backward compatibility
    
    private enum CodingKeys: String, CodingKey {
        case _id
        case id
        case companyId = "company id"
        case companyName = "Company Name"
        case name
        case officeEmail = "office_email"
        case email
        case phone
        case industry = "Industry"
        case companySize = "company_size"
        case size
        case companyAge = "company_age"
        case age
        case address
        case code
    }
    
    init(id: String? = nil, name: String? = nil, email: String? = nil, 
         phone: String? = nil, industry: String? = nil, size: String? = nil,
         age: String? = nil, address: String? = nil, code: String? = nil) {
        self._id = id
        self.id = id
        self.companyId = code
        self.companyName = name
        self.name = name
        self.officeEmail = email
        self.email = email
        self.phone = phone
        self.industry = industry != nil ? [industry!] : nil
        self.companySize = size
        self.size = size
        self.companyAge = age
        self.age = age
        self.address = address
        self.code = code
    }
    
    // Helper to get the ID regardless of which field it's in
    var extractedId: String? {
        return _id ?? id
    }
    
    // Helper to get the company code
    var extractedCode: String? {
        return companyId ?? code
    }
    
    // Helper to get the company name
    var extractedName: String? {
        return companyName ?? name
    }
}

struct InviteResponse: Codable {
    let success: String?
    let invites_sent: Int?
    let error_message: String?
    
    var wasSuccessful: Bool {
        return success?.lowercased() == "yes" || (invites_sent ?? 0) > 0
    }
}