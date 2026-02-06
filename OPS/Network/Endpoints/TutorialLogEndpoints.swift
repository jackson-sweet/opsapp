//
//  TutorialLogEndpoints.swift
//  OPS
//
//  Tutorial analytics logging endpoint
//

import Foundation

/// Extension for tutorial log API endpoints
extension APIService {

    /// Create a tutorial log entry on Bubble
    /// Fire-and-forget — errors are logged but don't propagate
    func createTutorialLog(
        appVersion: String,
        isLoggedIn: Bool,
        flowType: String,
        stepsCompleted: String,
        lastCompletedStep: String,
        completed: Bool,
        skipped: Bool,
        durationSeconds: Int
    ) async {
        let logData: [String: Any] = [
            BubbleFields.TutorialLog.appVersion: appVersion,
            BubbleFields.TutorialLog.isLoggedIn: isLoggedIn,
            BubbleFields.TutorialLog.flowType: flowType,
            BubbleFields.TutorialLog.stepsCompleted: stepsCompleted,
            BubbleFields.TutorialLog.lastCompletedStep: lastCompletedStep,
            BubbleFields.TutorialLog.completed: completed,
            BubbleFields.TutorialLog.skipped: skipped,
            BubbleFields.TutorialLog.durationSeconds: durationSeconds
        ]

        do {
            let bodyData = try JSONSerialization.data(withJSONObject: logData)

            struct CreateResponse: Codable {
                let id: String
            }

            let response: CreateResponse = try await executeRequest(
                endpoint: "api/1.1/obj/\(BubbleFields.Types.tutorialLog)",
                method: "POST",
                body: bodyData,
                requiresAuth: false
            )

            print("[TUTORIAL_LOG] Tutorial log created: \(response.id)")
        } catch {
            print("[TUTORIAL_LOG] Failed to create tutorial log: \(error)")
            // Non-fatal — don't block tutorial flow for analytics
        }
    }
}
