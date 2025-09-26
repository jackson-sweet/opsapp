//
//  SubscriptionEnums.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  Enums for subscription management matching Bubble's option sets

import Foundation

/// Subscription status matching Bubble's subscriptionStatus option set
enum SubscriptionStatus: String, Codable, CaseIterable {
    case trial = "trial"
    case active = "active"
    case grace = "grace"
    case expired = "expired"
    case cancelled = "cancelled"
    
    /// User-friendly display name
    var displayName: String {
        switch self {
        case .trial:
            return "Trial"
        case .active:
            return "Active"
        case .grace:
            return "Grace Period"
        case .expired:
            return "Expired"
        case .cancelled:
            return "Cancelled"
        }
    }
    
    /// Whether the subscription allows app access
    var allowsAccess: Bool {
        switch self {
        case .trial, .active, .grace:
            return true
        case .expired, .cancelled:
            return false
        }
    }
    
    /// Whether to show warning banner
    var showsWarning: Bool {
        switch self {
        case .grace:
            return true
        case .trial, .active, .expired, .cancelled:
            return false
        }
    }
}

/// Subscription plan matching Bubble's subscriptionPlan option set
enum SubscriptionPlan: String, Codable, CaseIterable {
    case trial = "trial"
    case starter = "starter"
    case team = "team"
    case business = "business"
    // Note: priority and setup exist in Bubble but are not company plans
    
    /// User-friendly display name
    var displayName: String {
        switch self {
        case .trial:
            return "Trial"
        case .starter:
            return "Starter"
        case .team:
            return "Team"
        case .business:
            return "Business"
        }
    }
    
    /// Maximum seats for this plan
    var maxSeats: Int {
        switch self {
        case .trial:
            return 10
        case .starter:
            return 3
        case .team:
            return 5
        case .business:
            return 10
        }
    }
    
    /// Monthly price in cents
    var monthlyPrice: Int {
        switch self {
        case .trial:
            return 0
        case .starter:
            return 9000 // $90.00
        case .team:
            return 14000 // $140.00
        case .business:
            return 19000 // $190.00
        }
    }
    
    /// Annual price in cents (20% discount)
    var annualPrice: Int {
        switch self {
        case .trial:
            return 0
        case .starter:
            return 86400 // $864.00
        case .team:
            return 134400 // $1,344.00
        case .business:
            return 182400 // $1,824.00
        }
    }
    
    /// Features list for display
    var features: [String] {
        switch self {
        case .trial:
            return [
                "30 days free",
                "10 team members",
                "All features included",
                "No credit card required"
            ]
        case .starter:
            return [
                "3 team members",
                "Unlimited projects",
                "Full app functionality",
                "Email support"
            ]
        case .team:
            return [
                "5 team members",
                "Unlimited projects",
                "Full app functionality",
                "Priority email support"
            ]
        case .business:
            return [
                "10 team members",
                "Unlimited projects",
                "Full app functionality",
                "Priority support"
            ]
        }
    }
    
    /// Stripe price IDs
    var stripePriceIds: (monthly: String?, annual: String?) {
        // ALWAYS use live price IDs since Bubble is in live mode
        // If you need to test with test price IDs, switch Bubble to test mode
        switch self {
        case .trial:
            return (nil, nil)
        case .starter:
            return ("price_1S6Jz1EooJoYGoIwDwx7dQHJ", "price_1S6Jz1EooJoYGoIwiGXZJ2a7")
        case .team:
            return ("price_1S6Jz6EooJoYGoIwRoQIstPk", "price_1S6Jz6EooJoYGoIwQSRdxhRs")
        case .business:
            return ("price_1S6Jz8EooJoYGoIw9u8cb3lx", "price_1S6Jz8EooJoYGoIwB2IUeC6z")
        }
    }
    
    /// Stripe price IDs for testing (only use when Bubble is in test mode)
    var testStripePriceIds: (monthly: String?, annual: String?) {
        switch self {
        case .trial:
            return (nil, nil)
        case .starter:
            return ("price_1S4UVEEooJoYGoIwIGvWfSd5", "price_1S4UVJEooJoYGoIwm11ItaKw")
        case .team:
            return ("price_1S4UVyEooJoYGoIwydDGa3jG", "price_1S4UVyEooJoYGoIw3aKrVfjQ")
        case .business:
            return ("price_1S4UW4EooJoYGoIwkgk4d8ph", "price_1S4UW4EooJoYGoIwaCxXWwUD")
        }
    }
}

/// Payment schedule options
enum PaymentSchedule: String, Codable {
    case monthly = "Monthly"
    case annual = "Annual"
    
    var displayName: String {
        switch self {
        case .monthly:
            return "Monthly"
        case .annual:
            return "Annual (Save 20%)"
        }
    }
}