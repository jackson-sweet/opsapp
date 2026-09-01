//
//  LeadDeckSection.swift
//  OPS
//
//  Deck design on the lead — the quoting artifact for a deck build, drawn
//  before any project exists. Shows the lead's display-candidate design as one
//  compact document row (tap → `LeadDeckScreen`, where the drawing gets the
//  whole display); empty state is one quiet START row, feature-flagged with the
//  builder and gated on pipeline.manage.
//
//  Data flow mirrors DeckTabView: an owner-scoped did-save feed resolves the
//  live local design — NOT a broad `@Query`, which SwiftData invalidates for
//  every DeckDesign save anywhere in the company and which re-fetched the whole
//  table on the main thread while the operator stood on this dossier (bug
//  2fa645a8, the same churn family removed from DeckTabView) — plus a one-shot
//  remote self-repair fetch so a cold device pulls lead decks drawn elsewhere
//  before the next full sync.
//

import SwiftUI
import SwiftData
import Combine

struct LeadDeckSection: View {
    let opportunity: Opportunity
    let canManage: Bool
    var onCreate: () -> Void = {}
    /// Push the deck screen. No design payload — the screen re-resolves the
    /// lead's display candidate live, so a builder save landing while the screen
    /// is up updates it in place instead of stranding a captured object.
    var onOpen: () -> Void = {}

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var permissionStore: PermissionStore

    /// The lead's display-candidate design. A broad `@Query` used to own this
    /// value, but SwiftData invalidates a filtered query for every save of the
    /// entity type — realtime deck traffic elsewhere in the company then
    /// re-fetched the full table and re-evaluated this row on the main thread
    /// while the operator stood on the dossier (the 2fa645a8 churn family;
    /// same repair as DeckTabView). The targeted did-save feed below refreshes
    /// only when a changed persistent identifier is a DeckDesign.
    @State private var candidate: DeckDesign?

    @State private var remoteFetchAttempted = false

    /// Read from the INJECTED store (LeadDetailView provides it), not the
    /// static shared — the shared store fails closed before hydration, which
    /// would blank this section in previews/harnesses and on a cold launch
    /// race. The env store is the surface's source of truth for gating.
    private var featureEnabled: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
    }

    /// Document-row form (Leads redesign spec §5.9): the DECK row's content
    /// region — a compact design line (title + updated stamp + chevron) or
    /// the START affordance; the details document supplies the label column
    /// and gates the row on the feature flag. The drawing itself lives on
    /// `LeadDeckScreen`, one tap away — the dossier is rows, not acreage.
    var body: some View {
        Group {
            if !featureEnabled {
                EmptyView()
            } else if let design = candidate {
                designRow(design)
            } else if canManage {
                startAffordance
            } else {
                Text("—")
                    .font(.custom("Mohave-Medium", size: 14))
                    .foregroundColor(OPSStyle.Colors.textMute)
            }
        }
        .onAppear {
            refreshCandidate()
        }
        .onReceive(
            NotificationCenter.default.publisher(for: ModelContext.didSave, object: modelContext)
                .receive(on: DispatchQueue.main)
        ) { notification in
            refreshCandidate(ifAffectedBy: notification)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: .dataActorMainContextDidRefresh,
                object: modelContext
            )
                .receive(on: DispatchQueue.main)
        ) { notification in
            refreshCandidate(ifAffectedBy: notification)
        }
        .task(id: opportunity.id) {
            // Establish local truth before deciding whether the remote repair
            // fetch is necessary (do not depend on onAppear/task ordering —
            // DeckTabView's rule).
            refreshCandidate()
            await selfRepairFetchIfNeeded()
            // The repair fetch resumes even after SwiftUI cancels this task —
            // the view is gone by then, and in a test harness the captured
            // context's container may already be dead (fetching on it traps).
            // Never touch the context again once cancelled.
            guard !Task.isCancelled else { return }
            refreshCandidate()
        }
    }

    // MARK: - Targeted local design feed (mirrors DeckTabView, bug 2fa645a8)

    @MainActor
    private func refreshCandidate() {
        let candidates: [DeckDesign]
        do {
            let canonical: String? = DeckDesign.canonicalUUIDString(opportunity.id)
            let lowercased: String? = canonical?.lowercased()
            let uppercased: String? = canonical?.uppercased()
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate {
                    $0.opportunityId == canonical
                        || $0.opportunityId == lowercased
                        || $0.opportunityId == uppercased
                }
            )
            candidates = try modelContext.fetch(descriptor)
        } catch {
            print("[LeadDeckSection] Local deck fetch failed for \(opportunity.id): \(error)")
            return
        }

        let resolved = DeckDesign.displayCandidate(
            in: candidates,
            forOpportunityId: opportunity.id
        )

        // Same-identity writes are dropped: even a same-value @State write
        // invalidates the SwiftUI graph. Field mutations on the current
        // @Model are observed by SwiftUI directly.
        guard candidate?.persistentModelID != resolved?.persistentModelID else { return }
        candidate = resolved
    }

    @MainActor
    private func refreshCandidate(ifAffectedBy notification: Notification) {
        let info = notification.userInfo ?? [:]
        let inserted = persistentIdentifiers(in: info, key: .insertedIdentifiers, rebroadcastKey: "inserted")
        let updated = persistentIdentifiers(in: info, key: .updatedIdentifiers, rebroadcastKey: "updated")
        let deleted = persistentIdentifiers(in: info, key: .deletedIdentifiers, rebroadcastKey: "deleted")

        let invalidatedAll =
            (info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue] as? Bool) == true
            || ((info[ModelContext.NotificationKey.invalidatedAllIdentifiers.rawValue]
                as? [PersistentIdentifier])?.isEmpty == false)
        if info.isEmpty || invalidatedAll {
            refreshCandidate()
            return
        }

        let currentIdentifier = candidate?.persistentModelID
        if deleted.contains(where: { $0 == currentIdentifier }) {
            refreshCandidate()
            return
        }

        // Never touch modelContext.model(for:) with an inserted identifier —
        // it may already be deleted and the fault traps. A scoped fetch,
        // identity-gated before the state write, is the safe re-evaluation.
        if (inserted + updated).contains(where: isDeckDesignIdentifier) {
            refreshCandidate()
        }
    }

    private func persistentIdentifiers(
        in info: [AnyHashable: Any],
        key: ModelContext.NotificationKey,
        rebroadcastKey: String
    ) -> [PersistentIdentifier] {
        (info[key.rawValue] as? [PersistentIdentifier])
            ?? (info[rebroadcastKey] as? [PersistentIdentifier])
            ?? []
    }

    private func isDeckDesignIdentifier(_ identifier: PersistentIdentifier) -> Bool {
        identifier.entityName == String(describing: DeckDesign.self)
    }

    // MARK: - Compact design row

    private func designRow(_ design: DeckDesign) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(opportunity.deckDesignTitle)
                        .font(.custom("Mohave-Medium", size: 14))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(updatedStamp(for: design))
                        .font(.custom("JetBrainsMono-Regular", size: 8.5))
                        .tracking(0.5)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .textCase(.uppercase)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Open deck design \(opportunity.deckDesignTitle)")
    }

    private var startAffordance: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onCreate()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .semibold))
                Text("START DECK DESIGN")
                    .font(.custom("JetBrainsMono-Medium", size: 9))
                    .tracking(0.9)
                    .textCase(.uppercase)
            }
            .foregroundColor(OPSStyle.Colors.text2)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Start a deck design")
    }

    private func updatedStamp(for design: DeckDesign) -> String {
        let date = design.updatedAt ?? design.createdAt
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "UPDATED \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    // MARK: - Remote self-repair

    /// Cold-device path: no local design for this lead → one fetch by
    /// opportunity_id, merged through `DeckDesignServerMerge` — the SAME
    /// inbound rule the deck viewport's repair uses, so a pending local edit
    /// survives the repair and a case-variant id can never duplicate a row
    /// (bug 2fa645a8).
    private func selfRepairFetchIfNeeded() async {
        guard candidate == nil, !remoteFetchAttempted else { return }
        remoteFetchAttempted = true

        let repo = DeckDesignRepository(companyId: opportunity.companyId)
        guard let dtos = try? await repo.fetchForOpportunity(opportunity.id) else { return }
        // Post-cancellation resume: the view is gone and the context may be
        // dead — merging into it would trap. Bail before touching it.
        guard !Task.isCancelled else { return }

        do {
            try DeckDesignServerMerge.merge(dtos, into: modelContext)
        } catch {
            print("[LeadDeckSection] Deck design repair merge failed for \(opportunity.id): \(error)")
        }
    }
}
