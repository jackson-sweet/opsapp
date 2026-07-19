//
//  LeadQuickTouchLogger.swift
//  OPS
//
//  Do-and-stamp quick contact (Leads redesign spec §3). TEXT / EMAIL on the
//  card open the real conversation AND log a fact-only outbound activity with
//  an UNDO toast — the same contract the around-call auto-log established.
//  CALL is NOT here: it keeps the shipped around-call intent flow (CallLogStore).
//

import Foundation
import UIKit

@MainActor
enum LeadQuickTouchLogger {

    // MARK: - URL composition (pure, unit-tested)

    static func smsURLString(phone: String) -> String {
        "sms:" + phone.filter { "0123456789+".contains($0) }
    }

    static func replySubject(from threadSubject: String) -> String {
        threadSubject.lowercased().hasPrefix("re:") ? threadSubject : "Re: \(threadSubject)"
    }

    static func mailtoURLString(email: String, threadSubject: String?) -> String {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        guard let threadSubject, !threadSubject.isEmpty else { return "mailto:\(encodedEmail)" }
        // Query-reserved characters are encoded explicitly — `.urlQueryAllowed`
        // leaves `:` `&` `=` `?` `+` `/` bare, and a bare `&` or `=` inside the
        // subject would split the mailto query.
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: ":&=?+/")
        let subject = replySubject(from: threadSubject)
            .addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        return "mailto:\(encodedEmail)?subject=\(subject)"
    }

    // MARK: - Do-and-stamp

    enum Mode { case text, email }

    /// Open the conversation and stamp the touch. Fact-only — no note, ever
    /// (spec §3). Fails soft: if the log write fails (offline), the compose
    /// still opened; show the error toast and move on.
    static func touch(_ mode: Mode, lead: Opportunity, companyId: String, userId: String?) {
        let name = lead.displayContactName
        switch mode {
        case .text:
            guard let phone = lead.contactPhone, !phone.isEmpty,
                  let url = URL(string: smsURLString(phone: phone)) else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            UIApplication.shared.open(url)
            log(type: .textMessage, subject: "Text to \(name)", lead: lead, companyId: companyId, userId: userId,
                toastLabel: "// TEXT LOGGED — \(name.uppercased())")
        case .email:
            guard let email = lead.contactEmail, !email.isEmpty else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { @MainActor in
                // Thread-subject fetch, bounded so a dead network can never
                // hold the compose hostage: whatever arrives within 1.5s wins,
                // otherwise open a blank compose (spec: no thread → blank).
                let subject = await boundedThreadSubject(for: lead, companyId: companyId)
                if let url = URL(string: mailtoURLString(email: email, threadSubject: subject)) {
                    _ = await UIApplication.shared.open(url)
                }
                log(type: .email, subject: subject.map(replySubject(from:)) ?? "Email to \(name)",
                    lead: lead, companyId: companyId, userId: userId,
                    toastLabel: "// EMAIL LOGGED — \(name.uppercased())")
            }
        }
    }

    private static func boundedThreadSubject(for lead: Opportunity, companyId: String) async -> String? {
        await withTaskGroup(of: String?.self) { group -> String? in
            group.addTask {
                (try? await OpportunityRepository(companyId: companyId)
                    .latestCorrespondenceSubject(for: lead.id)) ?? nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private static func log(type: ActivityType, subject: String, lead: Opportunity,
                            companyId: String, userId: String?, toastLabel: String) {
        Task { @MainActor in
            do {
                let created = try await ActivityRepository(companyId: companyId).logActivity(
                    target: .opportunity(lead), type: type, subject: subject,
                    direction: "outbound", createdBy: userId)
                NotificationCenter.default.post(name: Notification.Name("LeadActivityLoggedSuccess"),
                                                object: nil, userInfo: ["leadId": lead.id])
                ToastCenter.shared.present(Toast(
                    label: toastLabel, tone: .success, autoDismissAfter: 6,
                    action: ToastAction(label: "UNDO", accessibilityLabel: "Undo logged touch") {
                        Task { @MainActor in
                            try? await OpportunityRepository(companyId: companyId).deleteActivity(created.id)
                            NotificationCenter.default.post(name: Notification.Name("LeadActivityLoggedSuccess"),
                                                            object: nil, userInfo: ["leadId": lead.id])
                            ToastCenter.shared.present(Toast(label: "// TOUCH REMOVED", tone: .warning))
                        }
                    }))
            } catch {
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }
}
