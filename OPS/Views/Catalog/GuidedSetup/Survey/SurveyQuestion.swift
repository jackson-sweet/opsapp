//
//  SurveyQuestion.swift
//  OPS
//
//  The plain-language diagnostic survey for Guided Catalog Setup. Pure data +
//  branching logic that turns a handful of taps into a BusinessProfile. No UI
//  here — GuidedSetupSurveyView renders these and drives the answer state.
//
//  Copy is in the OPS in-app voice: terse, foreman-plain, no jargon, no
//  exclamation points. Eyebrows are UPPERCASE; questions/options are sentence
//  case.
//

import Foundation

enum SurveyQuestionID: String, CaseIterable, Equatable {
    case sells
    case pricing
    case materials
    case stock
    case trackCost
}

/// The value an option sets when tapped.
enum SurveyAnswerValue: Equatable {
    case sells(BusinessSells)
    case pricing(BusinessPricing)
    case materialUse(BusinessMaterialUse)
    case inventory(BusinessInventoryChoice)
    case trackCost(Bool)
}

/// One tappable answer. Single-select: tapping it applies the value and advances.
struct SurveyOption: Identifiable, Equatable {
    let id: String
    let label: String
    let sublabel: String
    let value: SurveyAnswerValue
}

/// Answers accumulated as the user taps through. Finalized into a BusinessProfile.
struct SurveyAnswers: Equatable {
    var sells: BusinessSells?
    var pricing: BusinessPricing?
    var materialUse: BusinessMaterialUse?
    var inventory: BusinessInventoryChoice?
    var trackCost: Bool?
}

/// Pure survey driver: question content, answer application, branching, finalize.
enum SurveyFlow {

    static let firstQuestion: SurveyQuestionID = .sells

    static func content(_ id: SurveyQuestionID) -> (eyebrow: String, prompt: String, options: [SurveyOption]) {
        switch id {
        case .sells:
            return ("SETUP", "What do customers pay you for?", [
                .init(id: "sells_services", label: "Our time",
                      sublabel: "Labor, service calls, know-how.", value: .sells(.services)),
                .init(id: "sells_goods", label: "Goods we supply",
                      sublabel: "Products, materials, parts we sell or install.", value: .sells(.goods)),
                .init(id: "sells_mix", label: "Both",
                      sublabel: "Our time and the goods to do the job.", value: .sells(.mix))
            ])
        case .pricing:
            return ("PRICING", "How do you price a job?", [
                .init(id: "price_fixed", label: "One price for the whole job",
                      sublabel: "All in. Materials and labor included.", value: .pricing(.fixedJob)),
                .init(id: "price_line", label: "Line by line",
                      sublabel: "Each part and service priced on its own.", value: .pricing(.lineItem)),
                .init(id: "price_hourly", label: "By the hour",
                      sublabel: "Time plus materials.", value: .pricing(.hourly)),
                .init(id: "price_depends", label: "Depends on the job",
                      sublabel: "Some fixed, some hourly.", value: .pricing(.mixed))
            ])
        case .materials:
            return ("MATERIALS", "Do your jobs burn through materials?", [
                .init(id: "mat_heavy", label: "Yes, lots of parts",
                      sublabel: "Fasteners, lumber, fittings, the works.", value: .materialUse(.heavy)),
                .init(id: "mat_some", label: "A few key ones",
                      sublabel: "The big-ticket materials.", value: .materialUse(.some)),
                .init(id: "mat_none", label: "No, I buy per job",
                      sublabel: "Nothing sitting on the shelf to track.", value: .materialUse(.none))
            ])
        case .stock:
            return ("STOCK", "Want OPS to count your stock?", [
                .init(id: "stock_tracked", label: "Count it",
                      sublabel: "Track what's on hand. Warn me to reorder.", value: .inventory(.tracked)),
                .init(id: "stock_cost", label: "Just my costs",
                      sublabel: "Skip the counting. Show me the margins.", value: .inventory(.costOnly))
            ])
        case .trackCost:
            return ("MARGINS", "Track your costs and margins?", [
                .init(id: "cost_yes", label: "Track both",
                      sublabel: "Your sell price and what it costs you.", value: .trackCost(true)),
                .init(id: "cost_no", label: "Just set prices",
                      sublabel: "Add your costs later.", value: .trackCost(false))
            ])
        }
    }

    static func apply(_ value: SurveyAnswerValue, to answers: inout SurveyAnswers) {
        switch value {
        case .sells(let v):       answers.sells = v
        case .pricing(let v):     answers.pricing = v
        case .materialUse(let v): answers.materialUse = v
        case .inventory(let v):   answers.inventory = v
        case .trackCost(let v):   answers.trackCost = v
        }
    }

    /// Branching: pricing only gates nothing here; the survey skips materials for
    /// pure-service businesses and skips stock when no materials are tracked.
    static func next(after id: SurveyQuestionID, answers: SurveyAnswers) -> SurveyQuestionID? {
        switch id {
        case .sells:
            return .pricing
        case .pricing:
            return answers.sells == .services ? .trackCost : .materials
        case .materials:
            return answers.materialUse == BusinessMaterialUse.none ? .trackCost : .stock
        case .stock:
            return .trackCost
        case .trackCost:
            return nil
        }
    }

    /// Build a profile once the survey is complete. Returns nil if a required
    /// answer is still missing.
    static func finalize(_ answers: SurveyAnswers) -> BusinessProfile? {
        guard let sells = answers.sells,
              let pricing = answers.pricing,
              let trackCost = answers.trackCost else { return nil }
        let materialUse = answers.materialUse ?? .none
        let inventory: BusinessInventoryChoice? = (materialUse == .none) ? nil : answers.inventory
        return BusinessProfile(sells: sells, pricing: pricing,
                               materialUse: materialUse, inventory: inventory, trackCost: trackCost)
    }
}
