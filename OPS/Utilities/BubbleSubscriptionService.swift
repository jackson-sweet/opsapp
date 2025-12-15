//
//  BubbleSubscriptionService.swift
//  OPS
//
//  Service to handle subscription creation through Bubble backend
//

import Foundation

class BubbleSubscriptionService {
    static let shared = BubbleSubscriptionService()
    private let baseURL = "https://opsapp.co/api/1.1/wf/"
    private let apiKey = "f81e9da85b7a12e996ac53e970a52299"
    
    private init() {}
    
    /// Response from Bubble subscription endpoint
    struct SubscriptionResponse: Codable {
        let status: String
        let subscription_id: String?
        let payment_intent_client_secret: String? // Alternative field name
        let client_secret: String? // Original field name
        let ephemeral_key: String?
        let customer_id: String?
        let error: String?
        let setup_intent_client_secret: String? // For setup intent flow
        let setup_intent_id: String? // The setup intent ID
        let subscription_status: String? // To check if already active
        let amount_due: Int? // To check if payment is needed
        
        // Computed property to get client secret from either field
        var paymentClientSecret: String? {
            return client_secret ?? payment_intent_client_secret ?? setup_intent_client_secret
        }
        
        // Map Bubble's response fields if they're different
        enum CodingKeys: String, CodingKey {
            case status
            case subscription_id = "subscription_id"
            case payment_intent_client_secret = "payment_intent_client_secret"
            case client_secret = "client_secret"
            case ephemeral_key = "ephemeral_key"
            case customer_id = "customer_id"
            case error
            case setup_intent_client_secret = "setup_intent_client_secret"
            case setup_intent_id = "setup_intent_id"
            case subscription_status = "subscription_status"
            case amount_due = "amount_due"
        }
    }
    
    /// Create a setup intent for payment collection
    func createSetupIntent(
        companyId: String,
        priceId: String,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        let endpoint = baseURL + "create_setup_intent?api_token=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        let body: [String: Any] = [
            "company_id": companyId,
            "price_id": priceId
        ]
        
        // Log the request
        print("📤 SETUP INTENT REQUEST:")
        print("  - Endpoint: \(endpoint)")
        print("  - Company ID: \(companyId)")
        print("  - Price ID: \(priceId)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                print("❌ SETUP INTENT API ERROR \(httpResponse.statusCode):")
                if let data = data, let errorBody = String(data: data, encoding: .utf8) {
                    print("  - Error Response: \(errorBody)")
                }
                
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.httpError(httpResponse.statusCode)))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.noData))
                }
                return
            }
            
            // Debug: Print raw response
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📥 SETUP INTENT RESPONSE: \(jsonString)")
            }
            #endif
            
            do {
                // Parse the response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   status == "success",
                   let responseData = json["response"] as? [String: Any] {
                    
                    // Extract required fields (handle both snake_case and camelCase)
                    let clientSecret = responseData["client_secret"] as? String ?? 
                                     responseData["clientSecret"] as? String
                    let ephemeralKey = responseData["ephemeral_key"] as? String ?? 
                                     responseData["ephemeralKey"] as? String
                    let customerId = responseData["customer_id"] as? String ?? 
                                   responseData["customerId"] as? String
                    let setupIntentId = responseData["setup_intent_id"] as? String ?? 
                                      responseData["setupIntentId"] as? String
                    
                    // Extract optional promo fields (may not be present if no promo code was provided)
                    let promoValid = responseData["promo_valid"] as? Bool
                    let promoDiscount = responseData["promo_discount"] as? Int
                    let paymentRequired = responseData["payment_required"] as? Bool ?? true
                    
                    // Log the response details
                    print("📦 SETUP INTENT CREATED:")
                    print("  - Has Client Secret: \(clientSecret != nil)")
                    print("  - Customer ID: \(customerId ?? "nil")")
                    print("  - Payment Required: \(paymentRequired)")
                    if promoValid != nil {
                        print("  - Promo Valid: \(promoValid!)")
                        print("  - Promo Discount: \(promoDiscount ?? 0)%")
                    }
                    
                    // Determine amount due based on promo discount
                    let amountDue: Int? = (promoDiscount == 100) ? 0 : nil
                    
                    // Create response object
                    let response = SubscriptionResponse(
                        status: "success",
                        subscription_id: nil,
                        payment_intent_client_secret: clientSecret,
                        client_secret: clientSecret,
                        ephemeral_key: ephemeralKey,
                        customer_id: customerId,
                        error: nil,
                        setup_intent_client_secret: clientSecret,
                        setup_intent_id: setupIntentId,
                        subscription_status: "pending_setup",
                        amount_due: amountDue
                    )
                    
                    DispatchQueue.main.async {
                        completion(.success(response))
                    }
                } else {
                    throw BubbleAPIError.invalidResponse
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Complete subscription after successful payment
    func completeSubscription(
        companyId: String,
        priceId: String,
        setupIntentId: String?,
        promoCode: String? = nil,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        let endpoint = baseURL + "complete_subscription?api_token=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var body: [String: Any] = [
            "company_id": companyId,
            "price_id": priceId
        ]
        
        if let setupIntentId = setupIntentId {
            body["setup_intent_id"] = setupIntentId
        }
        
        if let promoCode = promoCode {
            body["promo_code"] = promoCode
        }
        
        // Log the request
        print("📤 COMPLETE SUBSCRIPTION REQUEST:")
        print("  - Company ID: \(companyId)")
        print("  - Price ID: \(priceId)")
        print("  - Setup Intent: \(setupIntentId ?? "none")")
        print("  - Promo Code: \(promoCode ?? "none")")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                print("❌ COMPLETE SUBSCRIPTION ERROR \(httpResponse.statusCode):")
                if let data = data, let errorBody = String(data: data, encoding: .utf8) {
                    print("  - Error Response: \(errorBody)")
                }
                
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.httpError(httpResponse.statusCode)))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.noData))
                }
                return
            }
            
            // Debug: Print raw response
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📥 COMPLETE SUBSCRIPTION RESPONSE: \(jsonString)")
            }
            #endif
            
            do {
                // Parse the response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let status = json["status"] as? String,
                   status == "success",
                   let responseData = json["response"] as? [String: Any] {
                    
                    // Extract response fields
                    let subscriptionActive = responseData["subscription_active"] as? Bool ?? false
                    let subscriptionStatus = subscriptionActive ? "active" : "incomplete"
                    
                    print("✅ SUBSCRIPTION CREATED:")
                    print("  - ID: \(responseData["subscription_id"] as? String ?? "nil")")
                    print("  - Active: \(subscriptionActive)")
                    print("  - Promo Applied: \(responseData["promo_applied"] as? Bool ?? false)")
                    
                    // Create response object
                    let response = SubscriptionResponse(
                        status: "success",
                        subscription_id: responseData["subscription_id"] as? String,
                        payment_intent_client_secret: nil,
                        client_secret: nil,
                        ephemeral_key: nil,
                        customer_id: responseData["customer_id"] as? String,
                        error: nil,
                        setup_intent_client_secret: nil,
                        setup_intent_id: nil,
                        subscription_status: subscriptionStatus,
                        amount_due: 0
                    )
                    
                    DispatchQueue.main.async {
                        completion(.success(response))
                    }
                } else {
                    throw BubbleAPIError.invalidResponse
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Create a subscription through Bubble (which uses Stripe plugin)
    func createSubscriptionWithPayment(
        priceId: String,
        companyId: String,
        promoCode: String? = nil,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        // Choose endpoint based on whether we have a promo code
        let endpointName = (promoCode != nil && !promoCode!.isEmpty) ? 
            "create_subscription_with_payment_with_promo" : 
            "create_subscription_with_payment"
        
        // Include API key as URL parameter instead of header
        let endpoint = baseURL + "\(endpointName)?api_token=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Build request body
        var body: [String: Any] = [
            "price_id": priceId,
            "company_id": companyId,
            "allow_promotion_code": true  // Required by Bubble workflow
        ]
        
        // Add promo code if provided
        if let promoCode = promoCode, !promoCode.isEmpty {
            body["promo_code"] = promoCode
        }
        
        // Log the request
        print("📤 SUBSCRIPTION REQUEST:")
        print("  - Endpoint: \(endpoint)")
        print("  - Price ID: \(priceId)")
        print("  - Company ID: \(companyId)")
        print("  - Promo Code: \(promoCode ?? "none")")
        print("  - Body: \(body)")
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        // Make the request
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            // Check for HTTP errors
            if let httpResponse = response as? HTTPURLResponse,
               httpResponse.statusCode != 200 {
                // Log error details
                print("❌ SUBSCRIPTION API ERROR \(httpResponse.statusCode):")
                if let data = data, let errorBody = String(data: data, encoding: .utf8) {
                    print("  - Error Response: \(errorBody)")
                }
                print("  - URL: \(request.url?.absoluteString ?? "nil")")
                print("  - Headers: \(request.allHTTPHeaderFields ?? [:])")
                
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.httpError(httpResponse.statusCode)))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.noData))
                }
                return
            }
            
            // Debug: Print raw response
            #if DEBUG
            if let jsonString = String(data: data, encoding: .utf8) {
                print("📥 SUBSCRIPTION RESPONSE: \(jsonString)")
            }
            #endif
            
            do {
                // Try to parse the response
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check if it's a successful response
                    if json["status"] as? String == "success" {
                        // First try to get data from nested response object (Option 1)
                        let responseData = json["response"] as? [String: Any]
                        
                        // If response is empty or nil, try flat structure (Option 2)
                        let dataSource = (responseData?.isEmpty == false) ? responseData! : json
                        
                        // Check if we have the required fields in either structure
                        // Handle both snake_case and camelCase field names
                        let ephemeralKey = dataSource["ephemeral_key"] as? String ?? 
                                         dataSource["ephemeralKey"] as? String
                        let customerId = dataSource["customer_id"] as? String ?? 
                                       dataSource["customerId"] as? String
                        
                        // Check if payment is required but no client secret provided
                        let paymentRequired = dataSource["payment_required"] as? Bool ?? false
                        
                        if let ephemeralKey = ephemeralKey,
                           let customerId = customerId {
                            
                            // Get client secret from any available source
                            let clientSecret = dataSource["client_secret"] as? String ?? 
                                             dataSource["clientSecret"] as? String ??
                                             dataSource["payment_intent_client_secret"] as? String ??
                                             dataSource["paymentIntentClientSecret"] as? String ??
                                             dataSource["setup_intent_client_secret"] as? String ??
                                             dataSource["setupIntentClientSecret"] as? String
                            
                            // Get subscription ID (handle both naming conventions)
                            let subscriptionId = dataSource["subscription_id"] as? String ?? 
                                               dataSource["subscriptionId"] as? String
                            
                            // Get subscription status
                            let subscriptionStatus = dataSource["subscription_status"] as? String
                            
                            // Check for special cases
                            let paymentRequired = dataSource["payment_required"] as? Bool ?? false
                            let amountDue = dataSource["amount_due"] as? Int ?? 0
                            
                            // If payment is required but no client secret, this is an error
                            if paymentRequired && clientSecret == nil && amountDue > 0 {
                                print("⚠️ WARNING: Payment required but no client secret provided")
                                print("  - Subscription Status: \(subscriptionStatus ?? "unknown")")
                                print("  - Amount Due: \(amountDue)")
                                DispatchQueue.main.async {
                                    completion(.failure(BubbleAPIError.bubbleError("Payment setup failed: No client_secret returned from Stripe. Bubble workflow must create a SetupIntent or PaymentIntent.")))
                                }
                                return
                            }
                            
                            // Manually create the response object
                            let response = SubscriptionResponse(
                                status: "success",
                                subscription_id: subscriptionId,
                                payment_intent_client_secret: clientSecret,
                                client_secret: clientSecret,
                                ephemeral_key: ephemeralKey,
                                customer_id: customerId,
                                error: nil,
                                setup_intent_client_secret: dataSource["setup_intent_client_secret"] as? String,
                                setup_intent_id: dataSource["setup_intent_id"] as? String ?? dataSource["setupIntentId"] as? String,
                                subscription_status: subscriptionStatus,
                                amount_due: amountDue
                            )
                            DispatchQueue.main.async {
                                completion(.success(response))
                            }
                        } else {
                            // Response is missing required fields
                            let hasEphemeralKey = ephemeralKey != nil
                            let hasCustomerId = customerId != nil
                            let hasClientSecret = (dataSource["client_secret"] != nil || 
                                                 dataSource["clientSecret"] != nil ||
                                                 dataSource["payment_intent_client_secret"] != nil ||
                                                 dataSource["setup_intent_client_secret"] != nil)
                            
                            print("⚠️ SUBSCRIPTION RESPONSE VALIDATION:")
                            print("  - Has ephemeral_key: \(hasEphemeralKey) -> \(ephemeralKey ?? "nil")")
                            print("  - Has customer_id: \(hasCustomerId) -> \(customerId ?? "nil")")
                            print("  - Has client_secret: \(hasClientSecret)")
                            print("  - Available fields: \(dataSource.keys.sorted())")
                            
                            // Check if there's an error message in the response
                            if let errorMsg = dataSource["error"] as? String {
                                DispatchQueue.main.async {
                                    completion(.failure(BubbleAPIError.bubbleError(errorMsg)))
                                }
                            } else {
                                // Build detailed error message
                                var errorDetails = "Payment setup incomplete. "
                                if !hasClientSecret {
                                    errorDetails += "No payment client secret returned. "
                                }
                                if !hasEphemeralKey {
                                    errorDetails += "No ephemeral key returned. "
                                }
                                if !hasCustomerId {
                                    errorDetails += "No customer ID returned. "
                                }
                                errorDetails += "Check Bubble workflow configuration."
                                
                                DispatchQueue.main.async {
                                    completion(.failure(BubbleAPIError.bubbleError(errorDetails)))
                                }
                            }
                        }
                    } else if let errorMessage = json["message"] as? String {
                        // It's an error response
                        DispatchQueue.main.async {
                            completion(.failure(BubbleAPIError.bubbleError(errorMessage)))
                        }
                    } else if let errorMessage = json["error"] as? String {
                        // Alternative error format
                        DispatchQueue.main.async {
                            completion(.failure(BubbleAPIError.bubbleError(errorMessage)))
                        }
                    } else {
                        // Unexpected format
                        DispatchQueue.main.async {
                            completion(.failure(BubbleAPIError.invalidResponse))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(BubbleAPIError.invalidResponse))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Alternative: Create a setup intent for subscription
    func createSubscriptionSetupIntent(
        priceId: String,
        companyId: String,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        let endpoint = baseURL + "create_subscription_setup?api_token=\(apiKey)"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "price_id": priceId,
            "company_id": companyId
        ]
        
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // Same parsing logic as above
            self.handleSubscriptionResponse(data: data, response: response, error: error, completion: completion)
        }.resume()
    }
    
    private func handleSubscriptionResponse(
        data: Data?,
        response: URLResponse?,
        error: Error?,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        if let error = error {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
            return
        }
        
        if let httpResponse = response as? HTTPURLResponse,
           httpResponse.statusCode != 200 {
            if let data = data, let errorBody = String(data: data, encoding: .utf8) {
            }
            DispatchQueue.main.async {
                completion(.failure(BubbleAPIError.httpError(httpResponse.statusCode)))
            }
            return
        }
        
        guard let data = data else {
            DispatchQueue.main.async {
                completion(.failure(BubbleAPIError.noData))
            }
            return
        }
        
        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
        }
        #endif
        
        // Use the same parsing logic
        do {
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if json["status"] as? String == "success" {
                    let responseData = json["response"] as? [String: Any]
                    let dataSource = (responseData?.isEmpty == false) ? responseData! : json
                    
                    if let ephemeralKey = dataSource["ephemeral_key"] as? String,
                       let customerId = dataSource["customer_id"] as? String {
                        
                        let clientSecret = dataSource["client_secret"] as? String ??
                                         dataSource["setup_intent_client_secret"] as? String
                        
                        let response = SubscriptionResponse(
                            status: "success",
                            subscription_id: dataSource["subscription_id"] as? String,
                            payment_intent_client_secret: nil,
                            client_secret: clientSecret,
                            ephemeral_key: ephemeralKey,
                            customer_id: customerId,
                            error: nil,
                            setup_intent_client_secret: dataSource["setup_intent_client_secret"] as? String,
                            setup_intent_id: dataSource["setup_intent_id"] as? String ?? dataSource["setupIntentId"] as? String,
                            subscription_status: dataSource["subscription_status"] as? String,
                            amount_due: dataSource["amount_due"] as? Int
                        )
                        DispatchQueue.main.async {
                            completion(.success(response))
                        }
                    } else {
                        DispatchQueue.main.async {
                            completion(.failure(BubbleAPIError.bubbleError("Missing required fields")))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(BubbleAPIError.invalidResponse))
                    }
                }
            }
        } catch {
            DispatchQueue.main.async {
                completion(.failure(error))
            }
        }
    }

    // MARK: - Cancel Subscription

    /// Cancel subscription through Bubble backend
    /// - Parameters:
    ///   - userId: The user's unique ID
    ///   - companyId: The company ID
    ///   - reason: The cancellation reason
    ///   - cancelPriority: Whether to also cancel priority support
    ///   - plan: The current subscription plan
    func cancelSubscription(
        userId: String,
        companyId: String,
        reason: String,
        cancelPriority: Bool,
        plan: SubscriptionPlan
    ) async throws {
        let endpoint = baseURL + "cancel_subscription?api_token=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            throw BubbleAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "user": userId,
            "company_id": companyId,
            "reason": reason,
            "cancelPriority": cancelPriority,
            "plan": plan.rawValue
        ]

        print("📤 CANCEL SUBSCRIPTION REQUEST:")
        print("  - User: \(userId)")
        print("  - Company: \(companyId)")
        print("  - Reason: \(reason)")
        print("  - Cancel Priority: \(cancelPriority)")
        print("  - Plan: \(plan.rawValue)")

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BubbleAPIError.invalidResponse
        }

        #if DEBUG
        if let jsonString = String(data: data, encoding: .utf8) {
            print("📥 CANCEL SUBSCRIPTION RESPONSE: \(jsonString)")
        }
        #endif

        guard httpResponse.statusCode == 200 else {
            print("❌ CANCEL SUBSCRIPTION ERROR \(httpResponse.statusCode)")
            throw BubbleAPIError.httpError(httpResponse.statusCode)
        }

        // Parse response to check for success
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = json["status"] as? String,
           status == "success" {
            print("✅ SUBSCRIPTION CANCELLED SUCCESSFULLY")
        } else if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let error = json["error"] as? String {
            throw BubbleAPIError.bubbleError(error)
        }
    }

    // MARK: - Fetch Subscription Info

    /// Response from fetching subscription info from Stripe via Bubble
    struct SubscriptionInfoResponse {
        let subscriptionId: String?
        let status: String?              // "active", "trialing", "past_due", "canceled", etc.
        let planName: String?            // e.g., "Starter", "Team", "Business"
        let priceId: String?
        let currentPeriodStart: Date?
        let currentPeriodEnd: Date?      // This is the next billing date
        let billingInterval: String?     // "month" or "year"
        let cancelAtPeriodEnd: Bool
        let canceledAt: Date?
        let trialEnd: Date?
        let defaultPaymentMethod: String? // Last 4 digits or card brand
    }

    /// Fetch current subscription info directly from Stripe via Bubble
    /// - Parameters:
    ///   - stripeCustomerId: The Stripe customer ID
    ///   - completion: Callback with result
    func fetchSubscriptionInfo(
        stripeCustomerId: String,
        completion: @escaping (Result<SubscriptionInfoResponse, Error>) -> Void
    ) {
        let endpoint = baseURL + "get_subscription_info?api_token=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "stripe_customer_id": stripeCustomerId
        ]

        print("📤 FETCH SUBSCRIPTION INFO REQUEST:")
        print("  - Stripe Customer ID: \(stripeCustomerId)")

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.invalidResponse))
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.noData))
                }
                return
            }

            #if DEBUG
            print("📥 SUBSCRIPTION INFO: HTTP \(httpResponse.statusCode), \(data.count) bytes")
            #endif

            guard httpResponse.statusCode == 200 else {
                print("❌ FETCH SUBSCRIPTION INFO ERROR \(httpResponse.statusCode)")
                DispatchQueue.main.async {
                    completion(.failure(BubbleAPIError.httpError(httpResponse.statusCode)))
                }
                return
            }

            // Parse the response - expecting raw Stripe response passed through from Bubble
            do {
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    // Check for Bubble success wrapper
                    let stripeData: [String: Any]?

                    if json["status"] as? String == "success",
                       let response = json["response"] as? [String: Any] {
                        // Bubble wrapped the response
                        stripeData = response
                    } else if json["data"] != nil {
                        // Raw Stripe response (no Bubble wrapper)
                        stripeData = json
                    } else {
                        stripeData = nil
                    }

                    guard let stripeResponse = stripeData,
                          let subscriptions = stripeResponse["data"] as? [[String: Any]] else {
                        DispatchQueue.main.async {
                            completion(.failure(BubbleAPIError.invalidResponse))
                        }
                        return
                    }

                    // Check if there are any subscriptions
                    if let firstSub = subscriptions.first {
                        // Parse the first subscription from Stripe's raw format
                        let info = self.parseStripeSubscription(firstSub)
                        DispatchQueue.main.async {
                            completion(.success(info))
                        }
                    } else {
                        // No subscriptions found - return empty response (valid for trial users)
                        let emptyInfo = SubscriptionInfoResponse(
                            subscriptionId: nil,
                            status: nil,
                            planName: nil,
                            priceId: nil,
                            currentPeriodStart: nil,
                            currentPeriodEnd: nil,
                            billingInterval: nil,
                            cancelAtPeriodEnd: false,
                            canceledAt: nil,
                            trialEnd: nil,
                            defaultPaymentMethod: nil
                        )
                        DispatchQueue.main.async {
                            completion(.success(emptyInfo))
                        }
                    }
                } else {
                    DispatchQueue.main.async {
                        completion(.failure(BubbleAPIError.invalidResponse))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }

    /// Parse a raw Stripe subscription object into our response struct
    private func parseStripeSubscription(_ sub: [String: Any]) -> SubscriptionInfoResponse {
        // Get plan info from nested structure
        let plan = sub["plan"] as? [String: Any]
        let metadata = sub["metadata"] as? [String: Any]
        let planMetadata = plan?["metadata"] as? [String: Any]

        // Plan name from metadata (check both subscription and plan level)
        let planName = metadata?["plan"] as? String ?? planMetadata?["planType"] as? String

        // Parse dates (Stripe returns Unix timestamps as integers)
        let currentPeriodStart = parseStripeTimestamp(sub["current_period_start"])
        let currentPeriodEnd = parseStripeTimestamp(sub["current_period_end"])
        let canceledAt = parseStripeTimestamp(sub["canceled_at"])
        let trialEnd = parseStripeTimestamp(sub["trial_end"])

        return SubscriptionInfoResponse(
            subscriptionId: sub["id"] as? String,
            status: sub["status"] as? String,
            planName: planName,
            priceId: plan?["id"] as? String,
            currentPeriodStart: currentPeriodStart,
            currentPeriodEnd: currentPeriodEnd,
            billingInterval: plan?["interval"] as? String,
            cancelAtPeriodEnd: sub["cancel_at_period_end"] as? Bool ?? false,
            canceledAt: canceledAt,
            trialEnd: trialEnd,
            defaultPaymentMethod: sub["default_payment_method"] as? String
        )
    }

    /// Async version of fetchSubscriptionInfo
    func fetchSubscriptionInfo(stripeCustomerId: String) async throws -> SubscriptionInfoResponse {
        try await withCheckedThrowingContinuation { continuation in
            fetchSubscriptionInfo(stripeCustomerId: stripeCustomerId) { result in
                continuation.resume(with: result)
            }
        }
    }

    /// Parse Stripe timestamp (Unix seconds or milliseconds) to Date
    private func parseStripeTimestamp(_ value: Any?) -> Date? {
        guard let value = value else { return nil }

        if let timestamp = value as? TimeInterval {
            // Stripe uses seconds since epoch
            return Date(timeIntervalSince1970: timestamp)
        } else if let timestampInt = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(timestampInt))
        } else if let timestampString = value as? String, let timestamp = Double(timestampString) {
            return Date(timeIntervalSince1970: timestamp)
        }

        return nil
    }
}

// MARK: - Error Types

enum BubbleAPIError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case httpError(Int)
    case bubbleError(String)
    case subscriptionCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .noData:
            return "No data received from server"
        case .invalidResponse:
            return "Invalid response format"
        case .httpError(let code):
            return "Server error: \(code)"
        case .bubbleError(let message):
            return message
        case .subscriptionCreationFailed:
            return "Failed to create subscription"
        }
    }
}