//
//  TimeOffRequestSheet.swift
//  OPS
//
//  Bottom sheet for requesting time off — creates a pending time off event.
//

import SwiftUI

struct TimeOffRequestSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var dataController: DataController
    @ObservedObject var viewModel: CalendarViewModel

    @State private var startDate: Date
    @State private var endDate: Date
    @State private var reason: String = ""
    @State private var isSaving: Bool = false

    init(isPresented: Binding<Bool>, viewModel: CalendarViewModel) {
        _isPresented = isPresented
        self.viewModel = viewModel
        _startDate = State(initialValue: viewModel.selectedDate)
        _endDate = State(initialValue: viewModel.selectedDate)
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 24)
                        .padding(.top, 20)

                        // From date
                        sectionLabel("FROM")
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 12)

                        // To date
                        sectionLabel("TO")
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .colorScheme(.dark)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

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
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 0.5)
                            )
                            .padding(.horizontal, 20)
                            .padding(.bottom, 32)

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
                            .cornerRadius(2)
                        }
                        .disabled(isSaving)
                        .padding(.horizontal, 20)
                        .padding(.bottom, 32)
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
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(OPSStyle.Typography.microLabel)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
    }

    private func submit() {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return }

        isSaving = true

        let event = CalendarUserEvent(
            userId: userId,
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

        guard let context = dataController.modelContext else { isSaving = false; return }
        context.insert(event)
        try? context.save()

        Task {
            let repo = CalendarUserEventRepository(companyId: companyId)
            let iso = ISO8601DateFormatter()
            let dto = CreateCalendarUserEventDTO(
                userId: userId,
                companyId: companyId,
                type: "time_off",
                title: event.title,
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
                    event.id = saved.id
                    event.needsSync = false
                    event.lastSyncedAt = Date()
                    try? context.save()
                }
                savedId = saved.id
            }

            // Bug 2 — Notify admin/owner/office users that a time-off
            // request has been submitted. Best-effort: silently swallowed
            // on auth/network failure so the submit itself always succeeds.
            await notifyAdminsOfTimeOffRequest(
                companyId: companyId,
                requesterId: userId,
                requesterName: dataController.currentUser?.fullName ?? "A team member",
                eventTitle: event.title,
                startDate: startDate,
                endDate: endDate,
                eventId: savedId ?? event.id
            )

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
        eventTitle: String,
        startDate: Date,
        endDate: Date,
        eventId: String
    ) async {
        struct UserIdRow: Codable { let id: String }

        // Bug 8ef185af: include `operator` in the schedulers list. Per the
        // OPS role hierarchy (owner → admin → office → operator → crew),
        // operators are foremen / crew leads who schedule team work and are
        // the people most likely to need awareness of pending time-off
        // requests. The previous filter only hit ["admin", "owner", "office"]
        // so a company with no admin/office users (Canpro is one — owner +
        // operators + crew) generated zero notifications even though there
        // were operators who could action the request.
        let schedulers = (try? await SupabaseService.shared.client
            .from("users")
            .select("id")
            .eq("company_id", value: companyId)
            .in("role", values: ["admin", "owner", "office", "operator"])
            .execute()
            .value as [UserIdRow]) ?? []

        let recipientIds = schedulers.map(\.id).filter { $0 != requesterId }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"
        let dateRange = Calendar.current.isDate(startDate, inSameDayAs: endDate)
            ? dateFormatter.string(from: startDate)
            : "\(dateFormatter.string(from: startDate)) – \(dateFormatter.string(from: endDate))"

        let title = "Time Off Request"
        let body  = "\(requesterName) requested time off: \(dateRange)"

        let notifRepo = NotificationRepository()

        // Bug 8ef185af: also drop a confirmation row for the requester so
        // they always see something land in the rail when they submit. In
        // a single-admin company where the requester IS the only scheduler
        // (e.g. Canpro owner self-requesting), `recipientIds` is empty and
        // without this self-notification the user gets zero feedback that
        // the request was even recorded.
        let selfNotif = NotificationRepository.CreateNotificationDTO(
            userId: requesterId,
            companyId: companyId,
            type: "time_off_requested",
            title: "Time Off Submitted",
            body: "Your request for \(dateRange) is pending review.",
            projectId: nil,
            noteId: nil,
            expenseId: nil,
            batchId: nil,
            deepLinkType: "schedule"
        )
        try? await notifRepo.createNotification(selfNotif)

        guard !recipientIds.isEmpty else {
            print("[TimeOffRequestSheet] No other schedulers to notify (requester is the only one)")
            return
        }

        // In-app notification for every other scheduler
        for recipientId in recipientIds {
            let notifDTO = NotificationRepository.CreateNotificationDTO(
                userId: recipientId,
                companyId: companyId,
                type: "time_off_requested",
                title: title,
                body: body,
                projectId: nil,
                noteId: nil,
                expenseId: nil,
                batchId: nil,
                deepLinkType: "schedule"
            )
            try? await notifRepo.createNotification(notifDTO)
        }

        // Push via OneSignal
        try? await OneSignalService.shared.sendToUsers(
            userIds: recipientIds,
            title: title,
            body: body,
            data: [
                "type": "time_off_requested",
                "eventId": eventId,
                "screen": "schedule"
            ]
        )

        print("[TimeOffRequestSheet] Time-off push sent to \(recipientIds.count) scheduler(s)")
    }
}
