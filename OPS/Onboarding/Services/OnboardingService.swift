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
    /// - Returns: Sign up response with success status
    func signUpUser(email: String, password: String) async throws -> SignUpResponse {
        print("OnboardingService: Making API call to sign_user_up")
        
        // Configure API request
        let url = baseURL.appendingPathComponent("api/1.1/wf/sign_user_up")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        // Create request body with just email and password
        let parameters: [String: String] = [
            "user_email": email,
            "user_password": password
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        do {
            // Execute network request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            // Debug log the response
            print("OnboardingService: API Response - Status: \(httpResponse.statusCode)")
            print("============ API RESPONSE (Sign Up) ============")
            let responseText = String(data: data, encoding: .utf8) ?? "No data"
            print(responseText)
            print("===============================================")
            
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
            print("Response structure: \(Mirror(reflecting: signUpResponse).children.map { "\($0.label ?? "unknown"): \($0.value)" }.joined(separator: ", "))")
            
            if signUpResponse.wasSuccessful {
                if let userId = signUpResponse.extractedUserId {
                    print("Signup SUCCESS: User registered successfully with ID: \(userId)")
                } else {
                    print("Signup WARNING: Success reported but no user_id found in response!")
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
    
    /// Join a company with all user details
    /// - Parameters:
    ///   - email: User's email
    ///   - password: User's password
    ///   - firstName: User's first name
    ///   - lastName: User's last name
    ///   - phoneNumber: User's phone number
    ///   - companyCode: Company code to join
    /// - Returns: Join company response with company data
    func joinCompany(email: String, password: String, firstName: String, lastName: String, 
                     phoneNumber: String, companyCode: String) async throws -> JoinCompanyResponse {
        print("OnboardingService: Making API call to join_company")
        
        // Configure API request
        let url = baseURL.appendingPathComponent("api/1.1/wf/join_company")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppConfiguration.bubbleAPIToken, forHTTPHeaderField: "Authorization")
        
        // Get stored user_id if available
        let userId = UserDefaults.standard.string(forKey: "user_id") ?? ""
        
        // Create request body with all user parameters
        var parameters: [String: String] = [
            "user_email": email,
            "user_password": password,
            "name_first": firstName,
            "name_last": lastName,
            "phone": phoneNumber,
            "company_code": companyCode
        ]
        
        // Include user_id if available (VERY IMPORTANT)
        if !userId.isEmpty {
            parameters["user_id"] = userId
            print("Including user_id in company join request: \(userId)")
        } else {
            print("WARNING: No user_id available for company join request")
        }
        
        request.httpBody = try JSONSerialization.data(withJSONObject: parameters)
        
        do {
            // Execute network request
            let (data, response) = try await URLSession.shared.data(for: request)
            
            // Validate HTTP response
            guard let httpResponse = response as? HTTPURLResponse else {
                throw SignUpError.invalidResponse
            }
            
            // Debug log the response
            print("OnboardingService: Join Company API Response - Status: \(httpResponse.statusCode)")
            print("============ API RESPONSE (Join Company) ============")
            let responseText = String(data: data, encoding: .utf8) ?? "No data"
            print(responseText)
            print("=====================================================")
            
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
            print("Join Company Response structure: \(Mirror(reflecting: joinResponse).children.map { "\($0.label ?? "unknown"): \($0.value)" }.joined(separator: ", "))")
            
            // Print detailed company data for debugging
            if let companyData = joinResponse.extractedCompanyData {
                print("Extracted company data:")
                print("  - Company ID: \(companyData.id)")
                print("  - Company Name: \(companyData.name)")
            } else {
                print("Could not extract company data from response")
            }
            
            // Try to be flexible with successful responses
            if joinResponse.wasSuccessful {
                print("Company join SUCCESS! Company data received:")
                
                if let companyData = joinResponse.extractedCompanyData {
                    print("  - Company Name: \(companyData.name)")
                    print("  - Company ID: \(companyData.id)")
                } else {
                    print("  - Company joined successfully but data incomplete")
                }
                
                // Always return the response for successful join
                return joinResponse
            } else if httpResponse.statusCode >= 200 && httpResponse.statusCode < 300 {
                // We received a 200-range status code, so let's consider this a partial success
                // and let the ViewModel decide how to handle it
                print("Company join NOTE: HTTP success but couldn't find company data in response")
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
    
    // Phone verification methods have been removed
}
