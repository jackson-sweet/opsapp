//
//  StripeConfiguration.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Stripe SDK configuration and payment sheet appearance

import Foundation
import StripePaymentSheet
import PassKit

class StripeConfiguration {
    static let shared = StripeConfiguration()

    // MARK: - Configuration

    private let publishableKey = "pk_live_51QSBKBEooJoYGoIw8DfnivP6eVBQtjXawuPP9cUO5Oj1m1SNb1M9fiSMDTBwiXGHhPUqfY5hxJudQoDSS9CMpgXb00Y94cBwkX"
    private let merchantIdentifier = "merchant.co.opsapp"

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
            merchantCountryCode: "US"
        )
    }

    // MARK: - Payment Sheet Configuration

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
                ephemeralKeySecret: ""
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

        // Fonts
        appearance.font.base = UIFont(name: "Mohave-Regular", size: 16) ?? UIFont.systemFont(ofSize: 16)
        appearance.font.sizeScaleFactor = 1.0

        // Shapes
        appearance.cornerRadius = CGFloat(OPSStyle.Layout.cornerRadius)
        appearance.borderWidth = 1.0

        return appearance
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
