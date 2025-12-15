//
//  PlanSelectionView+CheckoutSession.swift
//  OPS
//
//  Alternative payment implementation using Stripe Checkout Session
//

import SwiftUI
import SafariServices

extension PlanSelectionView {
    
    /// Alternative payment method using Stripe Checkout hosted page
    func initiateCheckoutSession() {
        guard let selectedPlan = selectedPlan else {
            errorMessage = "Please select a plan"
            showPaymentError = true
            return
        }

        isProcessingPayment = true

        // Get the selected price ID
        let priceId: String? = selectedSchedule == .monthly ?
            selectedPlan.stripePriceIds.monthly :
            selectedPlan.stripePriceIds.annual

        guard let priceId = priceId else {
            errorMessage = "Invalid plan selection"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        // Get user and company information
        guard let user = dataController.currentUser,
              let company = dataController.getCurrentUserCompany() else {
            errorMessage = "Unable to load account information"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        // Create checkout session through Bubble
        createBubbleCheckoutSession(
            userId: user.id,
            companyId: company.id,
            priceId: priceId,
            customerEmail: user.email ?? ""
        )
    }
    
    private func createBubbleCheckoutSession(userId: String, companyId: String, priceId: String, customerEmail: String) {
        // Call your Bubble API to create a checkout session
        let endpoint = "https://opsapp.co/api/1.1/wf/create_checkout_session"
        
        guard let url = URL(string: endpoint) else {
            errorMessage = "Invalid server URL"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Bubble API key authorization
        let apiKey = "f81e9da85b7a12e996ac53e970a52299"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "user_id": userId,
            "company_id": companyId,
            "price_id": priceId,
            "email": customerEmail
        ]
        
        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            errorMessage = "Failed to create request"
            showPaymentError = true
            isProcessingPayment = false
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isProcessingPayment = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    self.showPaymentError = true
                    return
                }
                
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    self.errorMessage = "Invalid response from server"
                    self.showPaymentError = true
                    return
                }
                
                if let checkoutUrl = json["checkout_url"] as? String,
                   let url = URL(string: checkoutUrl) {
                    // Open Stripe Checkout in Safari
                    self.openCheckoutSession(url: url)
                } else if let errorMessage = json["error"] as? String {
                    self.errorMessage = errorMessage
                    self.showPaymentError = true
                } else {
                    self.errorMessage = "Failed to create checkout session"
                    self.showPaymentError = true
                }
            }
        }.resume()
    }
    
    private func openCheckoutSession(url: URL) {
        // Open in Safari View Controller
        let safariVC = SFSafariViewController(url: url)
        
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let rootVC = windowScene.windows.first?.rootViewController {
            rootVC.present(safariVC, animated: true)
        }
    }
}

// MARK: - URL Scheme Handler

extension PlanSelectionView {
    /// Handle return from Stripe Checkout
    static func handleCheckoutReturn(url: URL) {
        if url.absoluteString.contains("payment-success") {
            // Payment successful
            NotificationCenter.default.post(
                name: .paymentSuccessful,
                object: nil
            )
        } else if url.absoluteString.contains("payment-cancelled") {
            // Payment cancelled
            NotificationCenter.default.post(
                name: .paymentCancelled,
                object: nil
            )
        }
    }
}

extension Notification.Name {
    static let paymentSuccessful = Notification.Name("paymentSuccessful")
    static let paymentCancelled = Notification.Name("paymentCancelled")
}