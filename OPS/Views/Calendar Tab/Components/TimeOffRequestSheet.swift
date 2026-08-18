//
//  TimeOffRequestSheet.swift
//  OPS
//
//  Bottom sheet for requesting time off — creates a pending time off event.
//

import SwiftUI
import SwiftData

struct TimeOffRequestSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    /// All users in the current company. Used to populate the multi-select
    /// "FOR" picker so admins / operators can request time off on behalf of
    /// crew members. Filtered to the current company below.
    @Query private var allUsers: [User]

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var reason: String = ""
    @State private var isSaving: Bool = false

    /// Bug 81470acd — the set of users this request applies to. Defaults
    /// to the current user (self-request, every role's default behaviour).
    /// When the role has `time_off.approve`, the "FOR" row becomes tappable
    /// and the user can pick one or more crew to request on behalf of.
    @State private var targetUserIds: Set<String> = []
    @State private var showingTargetPicker: Bool = false

    init(isPresented: Binding<Bool>, viewModel: CalendarViewModel) {
        _isPresented = isPresented
        self.viewModel = viewModel
        _startDate = State(initialValue: viewModel.selectedDate)
        _endDate = State(initialValue: viewModel.selectedDate)
    }

    /// Roles permitted to request time off on behalf of other crew members.
    /// `time_off.approve` is the canonical permission for booking/reviewing
    /// crew time off. Crew without it can only request time off for themselves — same as
    /// the previous (single-user) behaviour.
    private var canRequestForOthers: Bool {
        PermissionStore.shared.can("time_off.approve")
    }

    /// Roster filtered to the current company, sorted alphabetically. The
    /// sheet shows initials + role for each row so the picker is legible
    /// at a glance even when avatars haven't loaded.
    private var companyMembers: [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allUsers
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.fullName.lowercased() < $1.fullName.lowercased() }
    }

    /// Materialised targets for the rendered "FOR" row + submit loop.
    /// Falls back to `[currentUser]` if `targetUserIds` is empty (defensive
    /// for the picker-cleared edge case).
    private var resolvedTargets: [User] {
        let ids = targetUserIds.isEmpty
            ? Set([dataController.currentUser?.id].compactMap { $0 })
            : targetUserIds
        return companyMembers.filter { ids.contains($0.id) }
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: OPSStyle.Layout.spacing2_5) {
                            Image(systemName: "clock.badge.questionmark")
                                .foregroundColor(OPSStyle.Colors.tanTextM)
                            Text("Request will be sent to your admin for approval.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tanTextM)
                        }
                        .padding(OPSStyle.Layout.spacing3_5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OPSStyle.Colors.tanFillM)
                        .overlay(
                            Rectangle()
                                .frame(height: OPSStyle.Layout.Border.standard)
                                .foregroundColor(OPSStyle.Colors.tanLineM),
                            alignment: .bottom
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing4)
                        .padding(.top, OPSStyle.Layout.spacing3_5)

                        // Bug 81470acd — multi-target row. Shown for every
                        // role (so the user knows whose request this is)
                        // but only TAPPABLE when `canRequestForOthers`.
                        // The chevron + tap target are suppressed for
                        // crew so they can't even attempt to change it.
                        sectionLabel(canRequestForOthers ? "FOR" : "FOR YOU")
                        targetRow
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // From date
                        sectionLabel("FROM")
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing2_5)

                        // To date
                        sectionLabel("TO")
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing3_5)

                        // Reason field
                        sectionLabel("REASON (OPTIONAL)")
                        TextField("", text: $reason)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .placeholder(when: reason.isEmpty) {
                                Text("ENTER REASON")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                            .padding(OPSStyle.Layout.spacing3_5)
                            .background(OPSStyle.Colors.surfaceInput)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing5)

                        // Submit button (amber)
                        Button(action: submit) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().tint(OPSStyle.Colors.invertedText)
                                } else {
                                    Text("SUBMIT REQUEST")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(OPSStyle.Colors.invertedText)
                                }
                                Spacer()
                            }
                            .frame(height: OPSStyle.Layout.touchTargetStandard)
                            .background(OPSStyle.Colors.tan)
                            .cornerRadius(OPSStyle.Layout.progressBarRadius)
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                    }
                }
            }
            .navigationTitle("[ REQUEST TIME OFF ]")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") { isPresented = false }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .colorScheme(.dark)
        .onAppear {
            // Default the target to the current user every time the sheet
            // appears. Mutated only when the role can pick others.
            if targetUserIds.isEmpty, let id = dataController.currentUser?.id {
                targetUserIds = [id]
            }
        }
        .sheet(isPresented: $showingTargetPicker) {
            TeamMemberPickerSheet(
                selectedTeamMemberIds: $targetUserIds,
                allTeamMembers: companyMembers
            )
        }
    }

    /// Bug 81470acd — single shared row that summarises whose request this
    /// is. For self-only roles it renders as a non-interactive avatar +
    /// name pill; for managers it adds a chevron and opens the picker on
    /// tap. The targets list also drives the submit loop and per-target
    /// notification copy below.
    @ViewBuilder
    private var targetRow: some View {
        if canRequestForOthers {
            Button(action: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingTargetPicker = true
            }) {
                targetRowContent
            }
            .buttonStyle(PlainButtonStyle())
        } else {
            targetRowContent
        }
    }

    private var targetRowContent: some View {
        let targets = resolvedTargets
        let summary = targets.count <= 1
            ? (targets.first?.fullName ?? "You")
            : "\(targets.count) team members"

        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: -6) {
                ForEach(Array(targets.prefix(3))) { user in
                    UserAvatar(user: user, size: 28)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.background, lineWidth: 1.5)
                        )
                }
                if targets.count > 3 {
                    Text("+\(targets.count - 3)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.leading, OPSStyle.Layout.spacing2)
                }
            }

            Text(summary)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            if canRequestForOthers {
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
        .padding(OPSStyle.Layout.spacing3_5)
        .glassSurface()
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 6)
    }

    private func submit() {
        // The queue is the delivery mechanism now, so it is a precondition:
        // inserting locally with nowhere to send the request is what stranded
        // rows before (bug ef5a69e6).
        guard let requesterId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId,
              let context = dataController.modelContext,
              let syncEngine = dataController.syncEngine else { return }

        // Bug 81470acd — defense-in-depth: enforce the permission gate at
        // submit time too. Roles without time_off.approve that somehow hold a
        // multi-user selection (stale state, accessibility shortcut) get
        // collapsed back to themselves so they can't write events for
        // anyone else.
        let effectiveTargets: [User]
        if canRequestForOthers {
            effectiveTargets = resolvedTargets
        } else if let me = dataController.currentUser {
            effectiveTargets = [me]
        } else {
            effectiveTargets = []
        }
        guard !effectiveTargets.isEmpty else { return }

        let requesterName = dataController.currentUser?.fullName ?? "A team member"

        isSaving = true

        // Insert one CalendarUserEvent per target — each row's `userId`
        // is the *target* (whose calendar carries the time off), so an
        // admin requesting on behalf of crew leaves a clear data trail
        // per crew member, with the same start/end/reason across the
        // batch. The amber pending status remains until a manager
        // approves through the schedule UI.
        struct PreparedEvent {
            let event: CalendarUserEvent
            let target: User
        }

        var prepared: [PreparedEvent] = []
        for target in effectiveTargets {
            let event = CalendarUserEvent(
                // The id is ours from the first instant: it is the queue's key,
                // and it used to be rewritten to the server's id after a
                // successful create — which is exactly why a failed create left
                // a row nothing could ever push. Lowercased because Postgres
                // uuid columns are, and an uppercase id would echo back as a
                // second row.
                id: UUID().uuidString.lowercased(),
                userId: target.id,
                companyId: companyId,
                type: .timeOff,
                title: reason.isEmpty ? "Time Off Request" : reason,
                startDate: startDate,
                endDate: endDate,
                allDay: true,
                notes: reason.isEmpty ? nil : reason,
                address: nil,
                teamMemberIds: nil
            )
            event.status = CalendarUserEventStatus.pending.rawValue
            event.needsSync = true
            context.insert(event)
            prepared.append(PreparedEvent(event: event, target: target))
        }
        try? context.save()

        // Queue the server write durably instead of firing it and hoping. The
        // approver notification travels with the operation and dispatches from
        // the confirmed create — nobody is told about a request that only ever
        // existed on this phone (bug ef5a69e6).
        for item in prepared {
            CalendarUserEventOutboundSync.enqueueCreate(
                item.event,
                notification: CalendarUserEventOutboundSync.TimeOffNotification(
                    kind: .requested,
                    companyId: companyId,
                    requesterId: requesterId,
                    requesterName: requesterName,
                    targetUserId: item.target.id,
                    targetName: item.target.fullName,
                    eventTitle: item.event.title,
                    startDate: startDate,
                    endDate: endDate
                ),
                syncEngine: syncEngine,
                deferPush: true
            )
        }
        CalendarUserEventOutboundSync.pushQueued(syncEngine: syncEngine)

        isSaving = false
        viewModel.loadUserEvents()
        isPresented = false
    }
}
