//
//  CallDirectoryStore.swift
//  Shared between the OPS app and the OPSCallDirectory extension.
//
//  The app writes the pipeline's lead phone numbers (E.164 Int64 + label) into
//  the shared App Group container; the Call Directory extension reads them and
//  hands them to CallKit so a lead's name shows on the incoming-call screen.
//  Around-call lead capture (feature 154cb8a3).
//
//  Compiled into BOTH targets via the `Shared` synchronized group. Entries are
//  kept sorted ascending + unique here (CallKit's contract) so the extension
//  just iterates.
//

import Foundation

enum CallDirectoryStore {

    struct Entry: Codable, Equatable {
        let number: Int64   // E.164 with country code, no '+'
        let label: String   // e.g. "OPS lead: Helen Calloway"
    }

    private static let key = "ops.callDirectory.entries"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: AppGroupConfig.identifier)
    }

    /// APP SIDE — persist the directory. Dedups by number and sorts ascending so
    /// the extension can add entries in CallKit's required order without resorting.
    static func save(_ entries: [Entry]) {
        let deduped = Dictionary(entries.map { ($0.number, $0.label) },
                                 uniquingKeysWith: { first, _ in first })
            .map { Entry(number: $0.key, label: $0.value) }
            .sorted { $0.number < $1.number }
        guard let data = try? JSONEncoder().encode(deduped) else { return }
        defaults?.set(data, forKey: key)
    }

    /// EXTENSION SIDE — already sorted + unique.
    static func loadEntries() -> [Entry] {
        guard let data = defaults?.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data) else { return [] }
        return entries
    }
}
