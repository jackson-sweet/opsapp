//
//  DeferredProfilePrompter.swift
//  OPS
//

import Foundation

enum DeferredPromptType: String, CaseIterable {
    case industry           // First time opening Settings
    case companySize        // After creating 2nd project
    case companyAddress     // When first using map features
    case phone              // Optional, in profile settings
}

@MainActor
final class DeferredProfilePrompter: ObservableObject {
    static let shared = DeferredProfilePrompter()

    @Published var activePrompt: DeferredPromptType?

    private let dismissedKey = "deferred_prompts_dismissed"

    private init() {}

    /// Check if a prompt should be shown based on current user/company state
    func checkForPrompt(trigger: DeferredPromptType, userIndustry: String?, companySize: String?, companyAddress: String?, userPhone: String?) {
        guard !isPromptDismissed(trigger) else { return }

        switch trigger {
        case .industry:
            if userIndustry == nil || userIndustry?.isEmpty == true {
                activePrompt = trigger
            }
        case .companySize:
            if companySize == nil || companySize?.isEmpty == true {
                activePrompt = trigger
            }
        case .companyAddress:
            if companyAddress == nil || companyAddress?.isEmpty == true {
                activePrompt = trigger
            }
        case .phone:
            if userPhone == nil || userPhone?.isEmpty == true {
                activePrompt = trigger
            }
        }
    }

    func dismissPrompt(_ type: DeferredPromptType) {
        var dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        dismissed.append(type.rawValue)
        UserDefaults.standard.set(dismissed, forKey: dismissedKey)
        activePrompt = nil
        print("[DEFERRED_PROMPT] Dismissed prompt: \(type.rawValue)")
    }

    private func isPromptDismissed(_ type: DeferredPromptType) -> Bool {
        let dismissed = UserDefaults.standard.stringArray(forKey: dismissedKey) ?? []
        return dismissed.contains(type.rawValue)
    }
}
