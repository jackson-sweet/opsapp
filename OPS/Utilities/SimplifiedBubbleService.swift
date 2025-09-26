//
//  SimplifiedBubbleService.swift
//  OPS
//
//  Simplified approach using Bubble's native Stripe plugin
//

import Foundation
import StripePaymentSheet

class SimplifiedBubbleService {
    static let shared = SimplifiedBubbleService()
    private let baseURL = "https://opsapp.co/api/1.1/wf/"
    
    /// Simplified approach: Let Bubble handle everything
    func subscribeUserToPlan(
        priceId: String,
        companyId: String,
        completion: @escaping (Result<Bool, Error>) -> Void
    ) {
        let endpoint = baseURL + "subscribe_user_to_plan"
        
        guard let url = URL(string: endpoint) else {
            completion(.failure(BubbleAPIError.invalidURL))
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add authorization
        if let token = KeychainManager().retrieveToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
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
            DispatchQueue.main.async {
                if let error = error {
                    completion(.failure(error))
                    return
                }
                
                // Check if successful
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 200 {
                    completion(.success(true))
                } else {
                    completion(.failure(BubbleAPIError.subscriptionCreationFailed))
                }
            }
        }.resume()
    }
}