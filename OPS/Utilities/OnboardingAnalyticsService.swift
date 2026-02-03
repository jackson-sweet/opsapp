//
//  OnboardingAnalyticsService.swift
//  OPS
//
//  Tracks onboarding page views and sends to Bubble for funnel visualization.
//  Designed to be flexible for page additions/removals.
//

import Foundation
import UIKit

/// Service for tracking onboarding analytics and sending to Bubble
final class OnboardingAnalyticsService {

    static let shared = OnboardingAnalyticsService()

    private let baseURL = "https://opsapp.co/api/1.1/wf/"
    private let apiKey = "f81e9da85b7a12e996ac53e970a52299"

    /// Current session ID (new for each onboarding attempt)
    private var sessionId: String = UUID().uuidString

    /// Timestamp when current page was entered
    private var pageEnteredAt: Date?

    /// Current page name for time tracking
    private var currentPageName: String?

    /// Device ID for tracking before user account exists
    private var deviceId: String {
        // Use identifierForVendor or generate/store a UUID
        if let vendorId = UIDevice.current.identifierForVendor?.uuidString {
            return vendorId
        }

        // Fallback to stored UUID
        let key = "onboarding_device_id"
        if let stored = UserDefaults.standard.string(forKey: key) {
            return stored
        }

        let newId = UUID().uuidString
        UserDefaults.standard.set(newId, forKey: key)
        return newId
    }

    private init() {}

    // MARK: - Session Management

    /// Start a new onboarding session (call when onboarding begins)
    func startNewSession() {
        sessionId = UUID().uuidString
        pageEnteredAt = nil
        currentPageName = nil
        print("[ONBOARDING_ANALYTICS] Started new session: \(sessionId)")
    }

    // MARK: - Page Tracking

    /// Track a page view in the onboarding flow
    /// - Parameters:
    ///   - pageName: The screen identifier (e.g., "welcome", "credentials", "profile")
    ///   - pageIndex: The order in the flow (1-based)
    ///   - totalPages: Total pages in this flow
    ///   - flowType: "company_creator" or "employee"
    ///   - userId: Optional user ID if account exists
    func trackPageView(
        pageName: String,
        pageIndex: Int,
        totalPages: Int,
        flowType: String,
        userId: String? = nil
    ) {
        // Calculate time on previous page
        var timeOnPreviousPage: Int? = nil
        if let enteredAt = pageEnteredAt, currentPageName != nil {
            timeOnPreviousPage = Int(Date().timeIntervalSince(enteredAt))
        }

        // Send previous page exit event with time spent (if applicable)
        if let previousPage = currentPageName, let timeSpent = timeOnPreviousPage {
            sendEvent(
                eventType: "page_exit",
                pageName: previousPage,
                pageIndex: max(1, pageIndex - 1),
                totalPages: totalPages,
                flowType: flowType,
                userId: userId,
                timeOnPage: timeSpent
            )
        }

        // Update tracking state
        pageEnteredAt = Date()
        currentPageName = pageName

        // Send page view event
        sendEvent(
            eventType: "page_view",
            pageName: pageName,
            pageIndex: pageIndex,
            totalPages: totalPages,
            flowType: flowType,
            userId: userId,
            timeOnPage: nil
        )
    }

    /// Track onboarding completion
    func trackCompleted(flowType: String, userId: String?) {
        // Send final page exit with time
        if let enteredAt = pageEnteredAt, let previousPage = currentPageName {
            let timeSpent = Int(Date().timeIntervalSince(enteredAt))
            sendEvent(
                eventType: "page_exit",
                pageName: previousPage,
                pageIndex: 0, // Will be set by context
                totalPages: 0,
                flowType: flowType,
                userId: userId,
                timeOnPage: timeSpent
            )
        }

        sendEvent(
            eventType: "completed",
            pageName: "onboarding_complete",
            pageIndex: 0,
            totalPages: 0,
            flowType: flowType,
            userId: userId,
            timeOnPage: nil
        )

        print("[ONBOARDING_ANALYTICS] Tracked completion for session: \(sessionId)")
    }

    /// Track onboarding abandonment (called when user exits without completing)
    func trackAbandoned(flowType: String, userId: String?, lastPageName: String, lastPageIndex: Int, totalPages: Int) {
        // Send page exit with time
        if let enteredAt = pageEnteredAt {
            let timeSpent = Int(Date().timeIntervalSince(enteredAt))
            sendEvent(
                eventType: "page_exit",
                pageName: lastPageName,
                pageIndex: lastPageIndex,
                totalPages: totalPages,
                flowType: flowType,
                userId: userId,
                timeOnPage: timeSpent
            )
        }

        sendEvent(
            eventType: "abandoned",
            pageName: lastPageName,
            pageIndex: lastPageIndex,
            totalPages: totalPages,
            flowType: flowType,
            userId: userId,
            timeOnPage: nil
        )

        print("[ONBOARDING_ANALYTICS] Tracked abandonment at \(lastPageName) for session: \(sessionId)")
    }

    // MARK: - API Communication

    private func sendEvent(
        eventType: String,
        pageName: String,
        pageIndex: Int,
        totalPages: Int,
        flowType: String,
        userId: String?,
        timeOnPage: Int?
    ) {
        let endpoint = baseURL + "track_onboarding_event?api_token=\(apiKey)"

        guard let url = URL(string: endpoint) else {
            print("[ONBOARDING_ANALYTICS] Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Build request body
        var body: [String: Any] = [
            "device_id": deviceId,
            "session_id": sessionId,
            "event_type": eventType,
            "page_name": pageName,
            "page_index": pageIndex,
            "total_pages": totalPages,
            "flow_type": flowType,
            "app_version": AppConfiguration.AppInfo.version,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]

        if let userId = userId {
            body["user_id"] = userId
        }

        if let timeOnPage = timeOnPage {
            body["time_on_page"] = timeOnPage
        }

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        } catch {
            print("[ONBOARDING_ANALYTICS] Failed to serialize body: \(error)")
            return
        }

        // Fire and forget - don't block onboarding for analytics
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("[ONBOARDING_ANALYTICS] Request failed: \(error.localizedDescription)")
                return
            }

            if let httpResponse = response as? HTTPURLResponse {
                if httpResponse.statusCode == 200 {
                    print("[ONBOARDING_ANALYTICS] Event tracked: \(eventType) - \(pageName)")
                } else {
                    print("[ONBOARDING_ANALYTICS] Server returned \(httpResponse.statusCode)")
                }
            }
        }.resume()
    }
}
