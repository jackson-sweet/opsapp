//
//  CallDirectoryHandler.swift
//  OPSCallDirectory
//
//  Call Directory extension principal class. On request, loads the OPS pipeline's
//  lead numbers from the shared App Group store and hands them to CallKit as
//  identification entries, so a lead's name shows on the native incoming-call
//  screen ("OPS lead: <name>"). Display only — writes no data.
//  Around-call lead capture (feature 154cb8a3).
//

import Foundation
import CallKit

final class CallDirectoryHandler: CXCallDirectoryProvider {

    override func beginRequest(with context: CXCallDirectoryExtensionContext) {
        context.delegate = self

        // Full reload of the identification set. For an incremental request,
        // clear first then re-add (entries must be added in ascending order).
        if context.isIncremental {
            context.removeAllIdentificationEntries()
        }

        for entry in CallDirectoryStore.loadEntries() { // already ascending + unique
            context.addIdentificationEntry(
                withNextSequentialPhoneNumber: entry.number,
                label: entry.label
            )
        }

        context.completeRequest()
    }
}

extension CallDirectoryHandler: CXCallDirectoryExtensionContextDelegate {
    func requestFailed(for extensionContext: CXCallDirectoryExtensionContext, withError error: Error) {
        // CallKit will retry the reload later; nothing to recover here.
        print("[CALL_DIR] request failed: \(error)")
    }
}
