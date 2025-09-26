//
//  StripeConfiguration.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Stripe SDK configuration and payment handling

import Foundation
import StripePaymentSheet
import PassKit

class StripeConfiguration {
    static let shared = StripeConfiguration()
    
    // MARK: - Configuration
    
    // Using live keys for both Debug and Release since Bubble is in live mode
    private let publishableKey = "pk_live_51QSBKBEooJoYGoIw8DfnivP6eVBQtjXawuPP9cUO5Oj1m1SNb1M9fiSMDTBwiXGHhPUqfY5hxJudQoDSS9CMpgXb00Y94cBwkX"
    private let merchantIdentifier = "merchant.co.opsapp"
    
    // Backend endpoint for creating payment intents
    private let backendURL = "https://opsapp.co/api/1.1/wf/"
    
    private init() {}
    
    // MARK: - Setup
    
    /// Configure Stripe SDK - call this on app launch
    func configure() {
        StripeAPI.defaultPublishableKey = publishableKey
    }
    
    // MARK: - Apple Pay Support
    
    /// Check if Apple Pay is available on this device
    var isApplePaySupported: Bool {
        return StripeAPI.deviceSupportsApplePay()
    }
    
    /// Get Apple Pay configuration
    func applePayConfiguration() -> PaymentSheet.ApplePayConfiguration {
        return PaymentSheet.ApplePayConfiguration(
            merchantId: merchantIdentifier,
            merchantCountryCode: "US" // or "CA" for Canada
        )
    }
    
    // MARK: - Payment Methods
    
    /// Create a PaymentSheet configuration
    func createPaymentSheetConfiguration(
        for customerId: String?,
        customerEmail: String?,
        companyName: String
    ) -> PaymentSheet.Configuration {
        var configuration = PaymentSheet.Configuration()
        
        // Merchant display name
        configuration.merchantDisplayName = "OPS"
        
        // Customer information
        if let customerId = customerId {
            configuration.customer = .init(
                id: customerId,
                ephemeralKeySecret: "" // Will be set when we create the subscription
            )
        }
        
        // Apple Pay configuration
        if isApplePaySupported {
            configuration.applePay = applePayConfiguration()
        }
        
        // Allow deleting payment methods
        configuration.allowsDelayedPaymentMethods = false
        configuration.allowsPaymentMethodsRequiringShippingAddress = false
        
        // UI Configuration
        configuration.appearance = createAppearance()
        
        // Default billing details
        configuration.defaultBillingDetails.email = customerEmail
        configuration.defaultBillingDetails.name = companyName
        
        // Save payment method for future use
        configuration.savePaymentMethodOptInBehavior = .automatic
        
        return configuration
    }
    
    /// Create custom appearance for payment sheet
    private func createAppearance() -> PaymentSheet.Appearance {
        var appearance = PaymentSheet.Appearance()
        
        // Colors
        appearance.colors.primary = UIColor(OPSStyle.Colors.primaryAccent)
        appearance.colors.background = UIColor(OPSStyle.Colors.cardBackground)
        appearance.colors.componentBackground = UIColor(OPSStyle.Colors.cardBackgroundDark)
        appearance.colors.text = UIColor(OPSStyle.Colors.primaryText)
        appearance.colors.textSecondary = UIColor(OPSStyle.Colors.secondaryText)
        // Note: 'error' color might not be available in all SDK versions
        // appearance.colors.error = UIColor(OPSStyle.Colors.errorStatus)
        
        // Fonts
        appearance.font.base = UIFont(name: "Mohave-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
        appearance.font.sizeScaleFactor = 1.0
        
        // Shapes
        appearance.cornerRadius = CGFloat(OPSStyle.Layout.cornerRadius)
        appearance.borderWidth = 1.0
        
        return appearance
    }
    
    // MARK: - Subscription Creation
    
    /// Parameters for creating a subscription
    struct SubscriptionRequest {
        let customerId: String
        let priceId: String
        let companyId: String
        let userEmail: String
    }
    
    /// Response from subscription creation
    struct SubscriptionResponse: Codable {
        let clientSecret: String
        let ephemeralKey: String
        let customerId: String
        let subscriptionId: String?
    }
    
    /// Create a subscription through your backend
    func createSubscription(
        request: SubscriptionRequest,
        completion: @escaping (Result<SubscriptionResponse, Error>) -> Void
    ) {
        // This should call your Bubble backend endpoint to create a Stripe subscription
        // For now, we'll create a placeholder implementation
        
        // TODO: Implement actual API call to Bubble
        let endpoint = backendURL + "create_stripe_subscription"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(StripeError.invalidURL))
            return
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "customer_id": request.customerId,
            "price_id": request.priceId,
            "company_id": request.companyId,
            "email": request.userEmail
        ]
        
        do {
            urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            completion(.failure(error))
            return
        }
        
        URLSession.shared.dataTask(with: urlRequest) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    completion(.failure(StripeError.noData))
                }
                return
            }
            
            do {
                let response = try JSONDecoder().decode(SubscriptionResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(response))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }.resume()
    }
    
    /// Create a setup intent for adding payment method without immediate payment
    func createSetupIntent(
        customerId: String,
        completion: @escaping (Result<(clientSecret: String, ephemeralKey: String), Error>) -> Void
    ) {
        // This should call your backend to create a setup intent
        // TODO: Implement actual API call
        
        let endpoint = backendURL + "create_setup_intent"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(StripeError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "customer_id": customerId
        ]
        
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
            
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let clientSecret = json["client_secret"] as? String,
                  let ephemeralKey = json["ephemeral_key"] as? String else {
                DispatchQueue.main.async {
                    completion(.failure(StripeError.invalidResponse))
                }
                return
            }
            
            DispatchQueue.main.async {
                completion(.success((clientSecret, ephemeralKey)))
            }
        }.resume()
    }
}

// MARK: - Error Types

enum StripeError: LocalizedError {
    case invalidURL
    case noData
    case invalidResponse
    case paymentFailed(String)
    case subscriptionCreationFailed
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid server URL"
        case .noData:
            return "No data received from server"
        case .invalidResponse:
            return "Invalid response from server"
        case .paymentFailed(let message):
            return "Payment failed: \(message)"
        case .subscriptionCreationFailed:
            return "Failed to create subscription"
        }
    }
}
