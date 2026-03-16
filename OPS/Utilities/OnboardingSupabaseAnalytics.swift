//
//  OnboardingSupabaseAnalytics.swift
//  OPS
//
//  Tracks onboarding funnel events to Supabase onboarding_analytics table.
//  Tracks onboarding funnel events to Supabase.
//

import Foundation
import UIKit
import Supabase

final class OnboardingSupabaseAnalytics {

    static let shared = OnboardingSupabaseAnalytics()

    private var sessionId: String = UUID().uuidString
    private var currentVariant: String?
    private var currentFlowType: String?

    private var deviceId: String {
        UIDevice.current.identifierForVendor?.uuidString ?? storedDeviceId
    }

    private var storedDeviceId: String {
        let key = "onboarding_device_id"
        if let stored = UserDefaults.standard.string(forKey: key) { return stored }
        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private init() {}

    // MARK: - Session Management

    func startSession(variant: String?, flowType: String) {
        sessionId = UUID().uuidString
        currentVariant = variant
        currentFlowType = flowType
        print("[ONBOARDING_ANALYTICS] Started session: \(sessionId), variant: \(variant ?? "none"), flow: \(flowType)")
    }

    // MARK: - Event Tracking

    func trackStepView(_ stepName: String, metadata: [String: String]? = nil) {
        sendEvent(stepName: stepName, action: "view", metadata: metadata)
    }

    func trackStepComplete(_ stepName: String, metadata: [String: String]? = nil) {
        sendEvent(stepName: stepName, action: "complete", metadata: metadata)
    }

    func trackStepSkip(_ stepName: String, metadata: [String: String]? = nil) {
        sendEvent(stepName: stepName, action: "skip", metadata: metadata)
    }

    func trackAbandon(_ stepName: String, metadata: [String: String]? = nil) {
        sendEvent(stepName: stepName, action: "abandon", metadata: metadata)
    }

    // MARK: - API

    private func sendEvent(stepName: String, action: String, metadata: [String: String]?) {
        guard let flowType = currentFlowType else {
            print("[ONBOARDING_ANALYTICS] No flow type set, skipping event")
            return
        }

        let userId = UserDefaults.standard.string(forKey: "user_id")

        Task {
            do {
                var payload: [String: AnyJSON] = [
                    "device_id": .string(deviceId),
                    "session_id": .string(sessionId),
                    "flow_type": .string(flowType),
                    "step_name": .string(stepName),
                    "action": .string(action)
                ]

                if let variant = currentVariant {
                    payload["variant"] = .string(variant)
                }

                if let userId = userId {
                    payload["user_id"] = .string(userId)
                }

                if let metadata = metadata {
                    let jsonData = try JSONSerialization.data(withJSONObject: metadata)
                    if let jsonString = String(data: jsonData, encoding: .utf8) {
                        payload["metadata"] = .string(jsonString)
                    }
                }

                try await SupabaseService.shared.client
                    .from("onboarding_analytics")
                    .insert(payload)
                    .execute()

                print("[ONBOARDING_ANALYTICS] Event: \(action) - \(stepName)")
            } catch {
                print("[ONBOARDING_ANALYTICS] Failed: \(error.localizedDescription)")
            }
        }
    }
}
