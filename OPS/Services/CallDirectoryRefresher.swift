//
//  CallDirectoryRefresher.swift
//  OPS
//
//  App-side driver for the Call Directory caller-ID extension (feature 154cb8a3).
//  Rebuilds the shared lead-number directory from the current pipeline and asks
//  iOS to reload the extension, so a lead's name shows on the incoming-call
//  screen. Gated behind the "showLeadsOnIncomingCalls" setting — a no-op until
//  the operator turns it on (and enables OPS under Settings → Phone → Call
//  Blocking & Identification).
//

import Foundation
import CallKit

enum CallDirectoryRefresher {

    /// Must match the extension target's PRODUCT_BUNDLE_IDENTIFIER.
    static let extensionID = "co.opsapp.ops.OPS.CallDirectory"

    /// Mirrors the Settings toggle (default off — the feature needs the operator
    /// to enable the extension in iOS Settings first, so it stays opt-in).
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: "showLeadsOnIncomingCalls") as? Bool ?? false
    }

    /// Rebuild the directory from the current pipeline and reload the extension.
    /// No-op when the toggle is off.
    static func refresh(from opportunities: [OpportunityDTO]) {
        guard isEnabled else { return }
        let entries: [CallDirectoryStore.Entry] = opportunities.compactMap { opp in
            guard opp.deletedAt == nil,
                  let number = PhoneNumber.e164Int64(opp.contactPhone) else { return nil }
            let name = (opp.contactName?.isEmpty == false) ? opp.contactName! : "lead"
            return .init(number: number, label: "OPS lead: \(name)")
        }
        CallDirectoryStore.save(entries)
        reload()
    }

    /// Fetch the pipeline and rebuild the directory — used when the operator
    /// flips the toggle on (no opportunities in hand at that moment).
    static func refreshFromNetwork(companyId: String) {
        guard isEnabled, !companyId.isEmpty else { return }
        Task {
            let repo = OpportunityRepository(companyId: companyId)
            let dtos = (try? await repo.fetchAll()) ?? []
            refresh(from: dtos)
        }
    }

    /// Clear the directory and reload (Settings toggle turned off).
    static func disable() {
        CallDirectoryStore.save([])
        reload()
    }

    /// Whether the operator has enabled OPS under Settings → Phone → Call
    /// Blocking & Identification. Drive an in-app "turn it on" hint from this.
    static func fetchEnabledStatus(_ completion: @escaping (CXCallDirectoryManager.EnabledStatus) -> Void) {
        CXCallDirectoryManager.sharedInstance.getEnabledStatusForExtension(withIdentifier: extensionID) { status, _ in
            DispatchQueue.main.async { completion(status) }
        }
    }

    private static func reload() {
        CXCallDirectoryManager.sharedInstance.reloadExtension(withIdentifier: extensionID) { error in
            if let error { print("[CALL_DIR] reload failed: \(error)") }
        }
    }
}
