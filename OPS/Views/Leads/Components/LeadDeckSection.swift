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

    /// Inline read-only tool state — never mutated (canvas gets showsTools:
    /// false), same pattern as DeckTabView's inline preview.
    @StateObject private var toolState = DeckViewerToolState()

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

    var body: some View {
        if !featureEnabled {
            EmptyView()
        } else if candidate == nil && !canManage {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                PanelSectionHeader(label: "DECK DESIGN")
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)

                if let design = candidate {
                    designCard(design)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                } else {
                    SheetCTAButton(
                        label: "START DECK DESIGN",
                        icon: "square.and.pencil",
                        variant: .outline,
                        action: onCreate
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                }
            }
            .task(id: opportunity.id) {
                await selfRepairFetchIfNeeded()
            }
        }
    }

    // MARK: - Design card

    private func designCard(_ design: DeckDesign) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onOpen(design)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                // Read-only blueprint. Hit testing off so the tap belongs to
                // the card — the builder owns interaction.
                DeckTab2DView(
                    drawingData: design.drawingData,
                    toolState: toolState,
                    showsTools: false
                )
                .frame(height: 190)
                .allowsHitTesting(false)
                .clipped()

                Rectangle()
                    .fill(OPSStyle.Colors.line)
                    .frame(height: 1)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(design.title)
                            .font(.custom("Mohave-Medium", size: 14))
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)

                        Text(updatedStamp(for: design))
                            .font(OPSStyle.Typography.nanoLabel)
                            .kerning(1.2)
                            .foregroundColor(OPSStyle.Colors.textMute)
                            .textCase(.uppercase)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
            }
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .fill(OPSStyle.Colors.surfaceInput)
            )
            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.panelRadius, style: .continuous)
                    .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Open deck design \(design.title)")
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
