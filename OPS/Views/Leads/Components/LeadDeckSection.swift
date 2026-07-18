//
//  LeadDeckSection.swift
//  OPS
//
//  Deck design on the lead — the quoting artifact for a deck build, drawn
//  before any project exists. Shows the lead's display-candidate design as a
//  read-only 2D blueprint card (tap → builder); empty state is one quiet
//  START row, feature-flagged with the builder and gated on pipeline.manage.
//
//  Data flow mirrors DeckTabView: @Query for live local designs (SwiftData
//  invalidates on builder saves), plus a one-shot remote self-repair fetch so
//  a cold device pulls lead decks drawn elsewhere before the next full sync.
//

import SwiftUI
import SwiftData

struct LeadDeckSection: View {
    let opportunity: Opportunity
    let canManage: Bool
    var onCreate: () -> Void = {}
    var onOpen: (DeckDesign) -> Void = { _ in }

    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var permissionStore: PermissionStore
    @Query private var allDesigns: [DeckDesign]

    @State private var remoteFetchAttempted = false

    /// Read from the INJECTED store (LeadDetailView provides it), not the
    /// static shared — the shared store fails closed before hydration, which
    /// would blank this section in previews/harnesses and on a cold launch
    /// race. The env store is the surface's source of truth for gating.
    private var featureEnabled: Bool {
        permissionStore.isFeatureEnabled("deck_builder")
    }

    private var candidate: DeckDesign? {
        DeckDesign.displayCandidate(in: allDesigns, forOpportunityId: opportunity.id)
    }

    /// Document-row form (Leads redesign spec §5.9): the DECK row's content
    /// region — a compact design line (title + updated stamp + chevron) or
    /// the START affordance; the details document supplies the label column
    /// and gates the row on the feature flag. Blueprint preview lives in the
    /// builder, one tap away — the dossier is rows, not acreage.
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
        .task(id: opportunity.id) {
            await selfRepairFetchIfNeeded()
        }
    }

    // MARK: - Compact design row

    private func designRow(_ design: DeckDesign) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(design)
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(design.title)
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
        .accessibilityLabel("Open deck design \(design.title)")
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
    /// opportunity_id, inserting rows we don't have (mirrors DeckTabView's
    /// self-repair; existing rows go through the normal inbound merge, not
    /// this shortcut).
    private func selfRepairFetchIfNeeded() async {
        guard candidate == nil, !remoteFetchAttempted else { return }
        remoteFetchAttempted = true

        let repo = DeckDesignRepository(companyId: opportunity.companyId)
        guard let dtos = try? await repo.fetchForOpportunity(opportunity.id) else { return }

        for dto in dtos {
            let designId = DeckDesign.canonicalUUIDString(dto.id)
            let descriptor = FetchDescriptor<DeckDesign>(
                predicate: #Predicate<DeckDesign> { $0.id == designId }
            )
            if let existing = (try? modelContext.fetch(descriptor))?.first {
                existing.applyServerSnapshot(dto, accepting: Set(DeckDesign.serverMergeFields))
            } else {
                let model = dto.toModel()
                model.lastSyncedAt = Date()
                model.needsSync = false
                modelContext.insert(model)
            }
        }
        try? modelContext.save()
    }
}
