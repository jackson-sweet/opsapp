//
//  StripeService.swift
//  OPS
//
//  Wraps ops-web /api/stripe/* routes for subscription management
//

import Foundation
import Supabase

class StripeService {
    static let shared = StripeService()
    private init() {}

    // MARK: - Response Types

    struct SetupIntentResponse: Codable {
        let clientSecret: String
    }

    struct SubscribeResponse: Codable {
        let subscriptionId: String?
        let status: String?
        let clientSecret: String?
    }

    struct InvoiceItem: Codable {
        let id: String
        let amount: Int
        let currency: String
        let status: String
        let created: Int
        let periodStart: Int?
        let periodEnd: Int?
        let invoicePdf: String?

        private enum CodingKeys: String, CodingKey {
            case id, amount, currency, status, created
            case periodStart = "period_start"
            case periodEnd = "period_end"
            case invoicePdf = "invoice_pdf"
        }
    }

    struct PaymentMethodItem: Codable {
        let id: String
        let brand: String?
        let last4: String?
        let expMonth: Int?
        let expYear: Int?
        let isDefault: Bool?

        private enum CodingKeys: String, CodingKey {
            case id, brand, last4
            case expMonth = "exp_month"
            case expYear = "exp_year"
            case isDefault = "is_default"
        }
    }

    struct PromoValidationResponse: Codable {
        let valid: Bool
        let discountPercentage: Double?
        let discountAmount: Int?
        let couponName: String?
        let maxRedemptions: Int?
        let timesRedeemed: Int?
        let error: String?

        private enum CodingKeys: String, CodingKey {
            case valid, error
            case discountPercentage = "discount_percentage"
            case discountAmount = "discount_amount"
            case couponName = "coupon_name"
            case maxRedemptions = "max_redemptions"
            case timesRedeemed = "times_redeemed"
        }
    }

    struct SubscriptionInfoResponse: Codable {
        let subscriptionId: String?
        let status: String?
        let planName: String?
        let priceId: String?
        let currentPeriodStart: String?
        let currentPeriodEnd: String?
        let billingInterval: String?
        let cancelAtPeriodEnd: Bool
        let canceledAt: String?
        let trialEnd: String?
        let defaultPaymentMethod: String?

        private enum CodingKeys: String, CodingKey {
            case subscriptionId = "subscription_id"
            case status
            case planName = "plan_name"
            case priceId = "price_id"
            case currentPeriodStart = "current_period_start"
            case currentPeriodEnd = "current_period_end"
            case billingInterval = "billing_interval"
            case cancelAtPeriodEnd = "cancel_at_period_end"
            case canceledAt = "canceled_at"
            case trialEnd = "trial_end"
            case defaultPaymentMethod = "default_payment_method"
        }

        /// Parse currentPeriodEnd as Date
        var currentPeriodEndDate: Date? {
            guard let str = currentPeriodEnd else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }

        /// Parse currentPeriodStart as Date
        var currentPeriodStartDate: Date? {
            guard let str = currentPeriodStart else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }

        /// Parse canceledAt as Date
        var canceledAtDate: Date? {
            guard let str = canceledAt else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }

        /// Parse trialEnd as Date
        var trialEndDate: Date? {
            guard let str = trialEnd else { return nil }
            return ISO8601DateFormatter().date(from: str)
        }
    }

    // MARK: - API Methods

    /// Create a SetupIntent for payment method collection
    func createSetupIntent(companyId: String) async throws -> SetupIntentResponse {
        let data = try await post(path: "/api/stripe/setup-intent", body: [
            "companyId": companyId
        ])
        return try JSONDecoder().decode(SetupIntentResponse.self, from: data)
    }

    /// Create a subscription
    func subscribe(
        companyId: String,
        plan: String,
        period: String,
        paymentMethodId: String? = nil,
        promoCode: String? = nil
    ) async throws -> SubscribeResponse {
        var body: [String: String] = [
            "companyId": companyId,
            "plan": plan,
            "period": period
        ]
        if let paymentMethodId = paymentMethodId {
            body["paymentMethodId"] = paymentMethodId
        }
        if let promoCode = promoCode {
            body["promoCode"] = promoCode
        }
        let data = try await post(path: "/api/stripe/subscribe", body: body)
        return try JSONDecoder().decode(SubscribeResponse.self, from: data)
    }

    /// Cancel a subscription
    func cancel(companyId: String) async throws {
        _ = try await post(path: "/api/stripe/cancel", body: [
            "companyId": companyId
        ])
    }

    /// Get invoices
    func getInvoices(companyId: String) async throws -> [InvoiceItem] {
        let data = try await get(path: "/api/stripe/invoices", query: [
            "companyId": companyId
        ])
        return try JSONDecoder().decode([InvoiceItem].self, from: data)
    }

    /// Get subscription info for a company
    func getSubscriptionInfo(companyId: String) async throws -> SubscriptionInfoResponse {
        let data = try await get(path: "/api/stripe/subscription-info", query: [
            "companyId": companyId
        ])
        return try JSONDecoder().decode(SubscriptionInfoResponse.self, from: data)
    }

    /// Get payment methods
    func getPaymentMethods(companyId: String) async throws -> [PaymentMethodItem] {
        let data = try await get(path: "/api/stripe/payment-methods", query: [
            "companyId": companyId
        ])
        return try JSONDecoder().decode([PaymentMethodItem].self, from: data)
    }

    /// Validate a promo code via ops-web
    func validatePromoCode(_ code: String) async throws -> PromoValidationResponse {
        let data = try await post(path: "/api/stripe/validate-promo", body: [
            "promoCode": code
        ])
        return try JSONDecoder().decode(PromoValidationResponse.self, from: data)
    }

    // MARK: - Private Helpers

    private func getAuthToken() async throws -> String {
        do {
            let session = try await SupabaseService.shared.client.auth.session
            return session.accessToken
        } catch {
            throw StripeServiceError.notAuthenticated
        }
    }

    private func post(path: String, body: [String: String]) async throws -> Data {
        let token = try await getAuthToken()
        let url = AppConfiguration.apiBaseURL.appendingPathComponent(path)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[STRIPE SERVICE] Error \(httpResponse.statusCode): \(errorMessage)")
            throw StripeServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return data
    }

    private func get(path: String, query: [String: String]) async throws -> Data {
        let token = try await getAuthToken()

        var components = URLComponents(url: AppConfiguration.apiBaseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }

        guard let url = components.url else {
            throw StripeServiceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw StripeServiceError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw StripeServiceError.apiError(statusCode: httpResponse.statusCode, message: errorMessage)
        }

        return data
    }
}

// MARK: - Errors

enum StripeServiceError: LocalizedError {
    case notAuthenticated
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            return "Not authenticated"
        case .invalidResponse:
            return "Invalid response from server"
        case .apiError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        }
    }
}
