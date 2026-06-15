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
    /// When the role has `team.manage`, the "FOR" row becomes tappable
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
    /// `team.manage` is the canonical permission for managing the team.
    /// Crew without it can only request time off for themselves — same as
    /// the previous (single-user) behaviour.
    private var canRequestForOthers: Bool {
        PermissionStore.shared.can("team.manage")
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
                        // Amber info banner
                        HStack(spacing: 10) {
                            Image(systemName: "clock.badge.questionmark")
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255))
                            Text("Request will be sent to your admin for approval.")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.85))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.10))
                        .overlay(
                            Rectangle()
                                .frame(height: 0.5)
                                .foregroundColor(Color(red: 196/255, green: 168/255, blue: 104/255).opacity(0.35)),
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
                            .padding(14)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                                    .stroke(OPSStyle.Colors.line, lineWidth: 0.5)
                            )
                            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                            .padding(.bottom, OPSStyle.Layout.spacing5)

                        // Submit button (amber)
                        Button(action: submit) {
                            HStack {
                                Spacer()
                                if isSaving {
                                    ProgressView().tint(.black)
                                } else {
                                    Text("SUBMIT REQUEST")
                                        .font(OPSStyle.Typography.button)
                                        .foregroundColor(.black)
                                }
                                Spacer()
                            }
                            .frame(height: 52)
                            .background(Color(red: 196/255, green: 168/255, blue: 104/255))
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
                                .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: 1.5)
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
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .stroke(OPSStyle.Colors.line, lineWidth: 0.5)
        )
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, 6)
    }

    private func submit() {
        guard let requesterId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId,
              let context = dataController.modelContext else { return }

        // Bug 81470acd — defense-in-depth: enforce the permission gate at
        // submit time too. Roles without team.manage that somehow hold a
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

        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()

            for item in prepared {
                let dto = CreateCalendarUserEventDTO(
                    userId: item.target.id,
                    companyId: companyId,
                    type: "time_off",
                    title: item.event.title,
                    startDate: iso.string(from: startDate),
                    endDate: iso.string(from: endDate),
                    allDay: true,
                    notes: reason.isEmpty ? nil : reason,
                    status: "pending",
                    address: nil,
                    teamMemberIds: nil
                )
                var savedId: String? = nil
                if let saved = try? await repo.create(dto) {
                    await MainActor.run {
                        item.event.id = saved.id
                        item.event.needsSync = false
                        item.event.lastSyncedAt = Date()
                        try? context.save()
                    }
                    savedId = saved.id
                }

                await notifyAdminsOfTimeOffRequest(
                    companyId: companyId,
                    requesterId: requesterId,
                    requesterName: requesterName,
                    targetUserId: item.target.id,
                    targetName: item.target.fullName,
                    eventTitle: item.event.title,
                    startDate: startDate,
                    endDate: endDate,
                    eventId: savedId ?? item.event.id
                )
            }

            await MainActor.run {
                isSaving = false
                viewModel.loadUserEvents()
                isPresented = false
            }
        }
    }

    // MARK: - Push notification to admins

    private func notifyAdminsOfTimeOffRequest(
        companyId: String,
        requesterId: String,
        requesterName: String,
        targetUserId: String,
        targetName: String,
        eventTitle: String,
        startDate: Date,
        endDate: Date,
        eventId: String
    ) async {
        // Recipients = anyone with time_off.approve. Permission-gated, never
        // role. Companies that want to delegate scheduling to operators or
        // foremen grant the permission to that custom role or via per-user
        // override.
        let approverIds = (try? await RecipientLookupService.usersWithPermission(
            companyId: companyId,
            permission: "time_off.approve"
        )) ?? []

        // Recipients exclude the requester AND the target — neither
        // should receive their own request as a "review this" entry.
        let recipientIds = approverIds
            .filter { $0 != requesterId && $0 != targetUserId }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateRange = Calendar.current.isDate(startDate, inSameDayAs: endDate)
            ? dateFormatter.string(from: startDate)
            : "\(dateFormatter.string(from: startDate)) – \(dateFormatter.string(from: endDate))"

        let isSelfRequest = requesterId == targetUserId
        let approvalTitle = "Time Off Request"
        let approvalBody: String = isSelfRequest
            ? "\(requesterName) requested time off: \(dateRange)"
            : "\(requesterName) requested time off for \(targetName): \(dateRange)"

        let notifRepo = NotificationRepository()

        // Bug 8ef185af: confirmation row for the requester so they
        // always see the submission land in the rail. Bug 81470acd: when
        // an admin requests on behalf of someone else, also drop a row
        // on the target's rail so they know a request was filed for
        // them — the calendar event alone isn't enough surface area.
        let selfNotif = NotificationRepository.CreateNotificationDTO(
            userId: requesterId,
            companyId: companyId,
            type: "time_off_requested",
            title: "Time Off Submitted",
            body: isSelfRequest
                ? "Your request for \(dateRange) is pending review."
                : "Submitted for \(targetName): \(dateRange) (pending review).",
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "schedule"
        )
        try? await notifRepo.createNotification(selfNotif)

        if !isSelfRequest {
            let targetNotif = NotificationRepository.CreateNotificationDTO(
                userId: targetUserId,
                companyId: companyId,
                type: "time_off_requested",
                title: "Time Off Submitted For You",
                body: "\(requesterName) submitted a time-off request on your behalf for \(dateRange).",
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: "schedule"
            )
            try? await notifRepo.createNotification(targetNotif)
        }

        guard !recipientIds.isEmpty else {
            print("[TimeOffRequestSheet] No other schedulers to notify")
            return
        }

        for recipientId in recipientIds {
            let notifDTO = NotificationRepository.CreateNotificationDTO(
                userId: recipientId,
                companyId: companyId,
                type: "time_off_requested",
                title: approvalTitle,
                body: approvalBody,
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: "schedule"
            )
            try? await notifRepo.createNotification(notifDTO)
        }

        try? await OneSignalService.shared.sendToUsers(
            userIds: recipientIds,
            title: approvalTitle,
            body: approvalBody,
            data: [
                "type": "time_off_requested",
                "eventId": eventId,
                "screen": "schedule"
            ]
        )

        print("[TimeOffRequestSheet] Time-off push sent to \(recipientIds.count) scheduler(s) for target \(targetName)")
    }
}
