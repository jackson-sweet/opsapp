//
//  OnboardingCopy.swift
//  OPS
//
//  Centralized copy/strings for onboarding flows.
//  Update these strings to change messaging across the app.
//

import Foundation

enum OnboardingCopy {

    // MARK: - App Store Links

    static let appStoreURL = "https://apps.apple.com/app/ops-app/id123456789" // TODO: Update with real App Store URL

    // MARK: - Team Invite Messages

    enum TeamInvite {
        static func smsMessage(companyName: String, companyCode: String) -> String {
            """
            \(companyName) added you to OPS.

            Get the app: \(OnboardingCopy.appStoreURL)
            Your code: \(companyCode)
            """
        }

        static func emailSubject(companyName: String) -> String {
            "\(companyName) added you to OPS"
        }

        static func emailBody(companyName: String, companyCode: String) -> String {
            """
            \(companyName) is using OPS for job management. You're in.

            Get started:
            1. Download OPS: \(OnboardingCopy.appStoreURL)
            2. Create your account
            3. Tap "Join a Crew"
            4. Enter code: \(companyCode)

            That's it. See you on the job.
            """
        }
    }
}
