//
//  KnownPlaceSuggestions.swift
//  OPS
//
//  Bug 29b75dce — address fields suggest the addresses OPS already knows (jobs,
//  clients, sub-contacts) above MapKit autocomplete, the way iOS Calendar
//  offers known places before it offers the whole world.
//
//  The operator is almost always typing an address the business has already
//  been to. Making them spell it out for MapKit — and wait 500ms per keystroke
//  to do it — is the app pretending not to know its own customers. Known rows
//  come first, match on the first keystroke with no network, and carry the
//  stored coordinate when the source has one, so an OPS-canonical address never
//  needs a geocode round trip.
//
//  Pure matcher over a snapshot of local SwiftData rows: synchronous, offline,
//  no I/O in the match path.
//

import Foundation
import CoreLocation
import SwiftData

struct KnownPlace: Identifiable, Equatable {
    /// Where the address came from. The tag is the row's leading label, so the
    /// operator can tell an OPS address from a MapKit one at a glance.
    enum Kind: String {
        case job = "JOB"
        case client = "CLIENT"
    }

    let id: String
    let kind: Kind
    /// What selecting the row inserts — the address exactly as stored.
    let address: String
    /// Whose address it is — project title, or client / sub-contact name.
    let context: String
    let latitude: Double?
    let longitude: Double?

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum KnownPlaceSuggestions {

    /// Snapshot every known place once per field mount. Jobs are gathered first
    /// so the dedupe keeps the job-labelled row when a client shares its
    /// address — the job carries the more useful context.
    ///
    /// Trashed rows are excluded: `deletedAt` is a tombstone, and offering an
    /// address the operator already threw away is offering back their own
    /// mistake. Completed and archived jobs stay — returning to a past
    /// customer's address is exactly the case this serves.
    static func candidates(in context: ModelContext) -> [KnownPlace] {
        var places: [KnownPlace] = []

        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        for project in projects where project.deletedAt == nil {
            let address = (project.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            places.append(KnownPlace(
                id: "project-\(project.id)", kind: .job,
                address: address, context: project.title,
                latitude: nil, longitude: nil
            ))
        }

        let clients = (try? context.fetch(FetchDescriptor<Client>())) ?? []
        for client in clients where client.deletedAt == nil {
            let address = (client.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            places.append(KnownPlace(
                id: "client-\(client.id)", kind: .client,
                address: address, context: client.name,
                latitude: client.latitude, longitude: client.longitude
            ))
        }

        let subClients = (try? context.fetch(FetchDescriptor<SubClient>())) ?? []
        for sub in subClients where sub.deletedAt == nil {
            let address = (sub.address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !address.isEmpty else { continue }
            places.append(KnownPlace(
                id: "subclient-\(sub.id)", kind: .client,
                address: address, context: sub.name,
                latitude: nil, longitude: nil
            ))
        }

        // Dedupe on the normalized address; earlier (JOB) wins.
        var seen = Set<String>()
        return places.filter { seen.insert(normalize($0.address)).inserted }
    }

    /// Rank known places against the query. An empty query suggests nothing —
    /// a wall of every address the business has ever visited, on focus, is
    /// noise, and the first keystroke is instant anyway.
    ///
    /// Three tiers, in the order an operator expects: the address they started
    /// typing, an address containing every word they typed, then whose address
    /// it is (typing "Phoebe" surfaces Phoebe's address — the Calendar
    /// behaviour). Ties keep candidate order, which is jobs before clients.
    static func match(_ query: String, in candidates: [KnownPlace], limit: Int = 3) -> [KnownPlace] {
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return [] }
        let tokens = normalizedQuery.split(separator: " ").map(String.init)

        struct Scored {
            let place: KnownPlace
            let score: Int
            let offset: Int
        }

        var scored: [Scored] = []
        for (offset, place) in candidates.enumerated() {
            let address = normalize(place.address)
            let context = normalize(place.context)
            let score: Int
            if address.hasPrefix(normalizedQuery) {
                score = 0
            } else if tokens.allSatisfy({ address.contains($0) }) {
                score = 1
            } else if tokens.allSatisfy({ context.contains($0) }) {
                score = 2
            } else {
                continue
            }
            scored.append(Scored(place: place, score: score, offset: offset))
        }

        return scored
            .sorted { ($0.score, $0.offset) < ($1.score, $1.offset) }
            .prefix(limit)
            .map(\.place)
    }

    /// Lowercased, diacritic-folded, every non-alphanumeric collapsed to a
    /// single space. `"Châteaux-Blvd,  SUITE 4"` and `"chateaux blvd suite 4"`
    /// are the same place, and a comma the operator did or did not type must
    /// never be the reason a match is missed.
    static func normalize(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: nil
        ).lowercased()
        let stripped = folded.map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(stripped).split(separator: " ").joined(separator: " ")
    }
}
