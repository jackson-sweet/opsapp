//
//  ClientLeadsSection.swift
//  OPS
//
//  The Leads section on the client profile (ContactDetailView), above
//  Projects. Open leads up top (job-first), a collapsed won/lost history peek
//  below, tap-through to the full lead, and create pre-linked to the client.
//  Only mounted when the operator can view pipeline (caller-gated on
//  permissionStore.leadAccessPolicy.canViewAny).
//
//  Leads aren't SwiftData-synced, so refresh is explicit: on appear, on the
//  lead-mutation notifications LeadsTabView also reloads on, and when the
//  detail / action sheets dismiss.
//
//  Spec: docs/superpowers/specs/2026-07-21-ios-client-leads-section-design.md
//

import SwiftUI
import Combine
import UIKit

/// Which verb opened the NEW LEAD sheet from a client's profile. The form is
/// identical either way — only what happens after the save differs.
enum ClientLeadCreateIntent: String, Identifiable {
    case lead
    case bookVisit

    var id: String { rawValue }
}

struct ClientLeadsSection: View {
    let client: Client
    /// Test-only seam (nil in production): pre-supplied leads bypass the async
    /// repository load so the section renders deterministically in snapshots,
    /// mirroring the VinylOrders board's preview seam.
    var previewLeads: [Opportunity]? = nil
    /// Opens a lead's linked project. This section always lives inside the
    /// client profile, which is presented modally, so the app-wide project
    /// route would land the project BEHIND that sheet. The host presents it.
    var onOpenProject: ((String) -> Void)? = nil

    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var permissionStore: PermissionStore
    @StateObject private var vm = ClientLeadsViewModel()

    @State private var isOpenExpanded = false
    @State private var isHistoryExpanded = false
    @State private var isHistoryListExpanded = false
    @State private var detailLead: Opportunity?
    @State private var activeSheet: LeadsSheet?
    /// Which verb opened NEW LEAD — the two differ only in what happens after
    /// the save (bug 9a49bd47).
    @State private var addLeadIntent: ClientLeadCreateIntent?
    /// The booking sheet, opened on the lead BOOK VISIT just created.
    @State private var bookingRequest: BookSiteVisitRequest?

    private var companyId: String { client.companyId ?? dataController.currentUser?.companyId ?? "" }
    private var policy: LeadAccessPolicy { permissionStore.leadAccessPolicy }
    private var canCreate: Bool { policy.canCreate }

    var body: some View {
        // No header `+`. The two things an operator comes to a client's page to
        // start — a new lead, and an appointment to go look at the work — are
        // named in the body where they can be read (bug 9a49bd47). A glyph in
        // a section header was the entry point nobody found.
        SectionCard(
            icon: OPSStyle.Icons.opportunity,
            title: "Leads (\(vm.openLeads.count))",
            contentPadding: EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)
        ) {
            VStack(spacing: 0) {
                if canCreate { createVerbs }
                content
            }
        }
        .task { await loadNow() }
        .onChange(of: activeSheet == nil) { _, isNil in if isNil { reload() } }
        .onChange(of: detailLead == nil) { _, isNil in if isNil { reload() } }
        .onReceive(leadMutations) { _ in reload() }
        .navigationDestination(item: $detailLead) { lead in
            LeadDetailView(
                opportunity: lead,
                onMarkLost: { activeSheet = .lost(lead) },
                onEdit:     { activeSheet = .edit(lead) },
                onMarkWon:  { activeSheet = .convert(lead) },
                onConvertLead: { converted in activeSheet = .convert(converted) },
                onOpenProject: onOpenProject
            )
            .environmentObject(dataController)
            .environmentObject(permissionStore)
        }
        .sheet(item: $activeSheet) { sheetView(for: $0) }
        .sheet(item: $addLeadIntent) { intent in
            AddLeadSheet(
                seedClient: client,
                onSaved: { _ in reload() },
                onBookSiteVisit: intent == .bookVisit
                    ? { lead in bookingRequest = BookSiteVisitRequest(lead: lead, existing: nil) }
                    : nil
            )
            .environmentObject(dataController)
        }
        .sheet(item: $bookingRequest) { request in
            BookSiteVisitSheet(request: request)
                .environmentObject(dataController)
        }
    }

    // MARK: - Create verbs (bug 9a49bd47)

    /// The two ways work starts with a client already on file. Both create a
    /// lead bound to THIS client; BOOK VISIT carries straight on into the
    /// booking sheet, because "when are we going out?" is the actual question
    /// and stopping at a saved lead answers half of it.
    private var createVerbs: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            createVerb(
                "NEW LEAD",
                icon: OPSStyle.Icons.plus,
                emphasised: false,
                spoken: "New lead for \(client.name)"
            ) { addLeadIntent = .lead }

            createVerb(
                "BOOK VISIT",
                icon: OPSStyle.Icons.calendar,
                emphasised: true,
                spoken: "Book a site visit for \(client.name)"
            ) { addLeadIntent = .bookVisit }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    /// No accent: this profile is a reading surface, and the client's own
    /// SAVE / SHARE row already owns its emphasis. BOOK VISIT leads on the
    /// active-control surface instead (DESIGN.md §3, MOBILE.md §4.1).
    private func createVerb(
        _ label: String,
        icon: String,
        emphasised: Bool,
        spoken: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: icon)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text(label)
                    .font(OPSStyle.Typography.buttonLabel)
                    .kerning(0.27)
                    .textCase(.uppercase)
                    .lineLimit(1)
            }
            .foregroundColor(emphasised ? OPSStyle.Colors.text : OPSStyle.Colors.text2)
            .frame(maxWidth: .infinity)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .fill(emphasised ? OPSStyle.Colors.surfaceActive : OPSStyle.Colors.surfaceInput)
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                    .strokeBorder(
                        emphasised ? OPSStyle.Colors.lineActive : OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(spoken)
    }

    // MARK: - Content states

    @ViewBuilder private var content: some View {
        switch vm.loadState {
        case .loading where vm.openLeads.isEmpty && vm.closedLeads.isEmpty:
            ProgressView()
                .tint(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(.vertical, OPSStyle.Layout.spacing5)
        case .error where vm.openLeads.isEmpty && vm.closedLeads.isEmpty:
            errorState
        default:
            if vm.openLeads.isEmpty && !vm.tally.hasAny {
                emptyState
            } else {
                VStack(spacing: 0) {
                    openList
                    if vm.tally.hasAny { historyDisclosure }
                }
            }
        }
    }

    private var openList: some View {
        let leads = vm.openLeads
        let shown = isOpenExpanded ? leads : Array(leads.prefix(5))
        return VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, lead in
                Button { detailLead = lead } label: { ClientLeadRow(lead: lead) }
                    .buttonStyle(PlainButtonStyle())
                if index < shown.count - 1 {
                    Divider().background(OPSStyle.Colors.secondaryText.opacity(0.2))
                }
            }
            if leads.count > 5 {
                expander(isExpanded: isOpenExpanded, moreCount: leads.count - 5) {
                    withAnimation(OPSStyle.Animation.standard) { isOpenExpanded.toggle() }
                }
            }
        }
    }

    private var historyDisclosure: some View {
        let closed = vm.closedLeads
        let shown = isHistoryListExpanded ? closed : Array(closed.prefix(5))
        return VStack(spacing: 0) {
            Divider().background(OPSStyle.Colors.secondaryText.opacity(0.2))

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation(OPSStyle.Animation.standard) { isHistoryExpanded.toggle() }
            } label: {
                HStack {
                    Text("// \(historyLabel)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer()
                    Image(systemName: isHistoryExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: OPSStyle.Layout.IconSize.xs))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
                .padding(.vertical, OPSStyle.Layout.spacing2_5)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())

            if isHistoryExpanded {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, lead in
                    if index == 0 {
                        Divider().background(OPSStyle.Colors.secondaryText.opacity(0.2))
                    }
                    Button { detailLead = lead } label: { ClientLeadRow(lead: lead, isHistory: true) }
                        .buttonStyle(PlainButtonStyle())
                    if index < shown.count - 1 {
                        Divider().background(OPSStyle.Colors.secondaryText.opacity(0.2))
                    }
                }
                if closed.count > 5 {
                    expander(isExpanded: isHistoryListExpanded, moreCount: closed.count - 5) {
                        withAnimation(OPSStyle.Animation.standard) { isHistoryListExpanded.toggle() }
                    }
                }
            }
        }
    }

    /// Nothing on file. It no longer carries its own CTA: the two verbs sit
    /// directly above it now, and an empty state that repeats the button 8pt
    /// under it is the same invitation twice (bug 9a49bd47).
    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: OPSStyle.Icons.opportunity)
                .font(.system(size: OPSStyle.Layout.IconSize.xl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("No leads")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    private var errorState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text("Couldn't load leads")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Button { reload() } label: {
                Text("Retry")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    // MARK: - Pieces

    private func expander(isExpanded: Bool, moreCount: Int, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Spacer()
                Text(isExpanded ? "SHOW LESS" : "+ \(moreCount) MORE")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Spacer()
            }
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var historyLabel: String {
        var parts: [String] = []
        if vm.tally.won > 0 { parts.append("\(vm.tally.won) WON") }
        if vm.tally.lost > 0 { parts.append("\(vm.tally.lost) LOST") }
        if vm.tally.discarded > 0 { parts.append("\(vm.tally.discarded) DISCARDED") }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private func sheetView(for sheet: LeadsSheet) -> some View {
        switch sheet {
        case .edit(let opp):
            EditLeadSheet(opportunity: opp)
        case .lost(let opp):
            LostReasonSheet(opportunity: opp)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        case .convert(let opp):
            ConvertToProjectSheet(opportunity: opp)
        default:
            EmptyView()   // .add / .log / .wonChooser are not used from here
        }
    }

    // MARK: - Load

    private func loadNow() async {
        if let previewLeads {
            vm.apply(previewLeads, clientId: client.id, policy: policy)
            return
        }
        await vm.load(companyId: companyId, clientId: client.id, policy: policy)
        if let open = detailLead,
           !vm.openLeads.contains(where: { $0.id == open.id }),
           !vm.closedLeads.contains(where: { $0.id == open.id }) {
            detailLead = nil
        }
    }

    private func reload() { Task { await loadNow() } }

    private static let leadMutationNames: [Notification.Name] = [
        Notification.Name("LeadCreatedSuccess"),
        Notification.Name("LeadUpdatedSuccess"),
        Notification.Name("LeadMarkedLostSuccess"),
        Notification.Name("LeadMarkedWonSuccess"),
        Notification.Name("LeadConvertedSuccess"),
        Notification.Name("LeadLinkedProjectSuccess"),
        Notification.Name("LeadArchivedSuccess"),
        Notification.Name("LeadDeletedSuccess"),
        .opsLeadsDidChange
    ]

    private var leadMutations: Publishers.MergeMany<NotificationCenter.Publisher> {
        Publishers.MergeMany(Self.leadMutationNames.map {
            NotificationCenter.default.publisher(for: $0)
        })
    }
}
