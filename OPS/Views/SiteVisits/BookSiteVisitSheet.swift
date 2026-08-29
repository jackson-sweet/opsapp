//
//  BookSiteVisitSheet.swift
//  OPS
//
//  Book (or move) a visit appointment on a lead. One sheet, state-aware:
//  create mode books; when the lead already holds an open booking the same
//  entry point opens THAT booking — reschedule and cancel live here, so two
//  stacked bookings can never be offered.
//
//  Booking is RPC-only by design (side effects are server-owned), so this
//  sheet requires signal: offline resolves to one terse error row, never a
//  queued write. On success the server row is mirrored into the local store
//  immediately (needsSync=false — it is already server truth) so the lead
//  surfaces read BOOKED without waiting for the realtime echo.
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - Request

/// What a visit affordance asked for. Identifiable so `.sheet(item:)` drives it.
struct BookSiteVisitRequest: Identifiable {
    let lead: Opportunity
    /// Non-nil = the lead's open booking → the sheet opens on it.
    let existing: BookSiteVisitForm.BookingSnapshot?

    var id: String { lead.id }
}

// MARK: - Sheet

struct BookSiteVisitSheet: View {
    let request: BookSiteVisitRequest
    /// Injectable for tests; defaults to the live RPC transport.
    var service: SiteVisitBookingService? = nil

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var form: BookSiteVisitForm?

    // WHEN-surface context: other booked visits, resolved names, and the
    // resolver that fetches them. Test seam mirrors initialForm.
    @State private var contextVisits: [BookingDayVisit]
    @State private var contextNamesByOpportunityId: [String: String] = [:]
    private let leadResolver = CalendarSiteVisitLeadResolver()

    /// Snapshot/preview seam — a preseeded form renders the full field stack
    /// without a signed-in DataController. Production callers omit it.
    init(
        request: BookSiteVisitRequest,
        service: SiteVisitBookingService? = nil,
        initialForm: BookSiteVisitForm? = nil,
        initialContextVisits: [BookingDayVisit] = []
    ) {
        self.request = request
        self.service = service
        _form = State(initialValue: initialForm)
        _contextVisits = State(initialValue: initialContextVisits)
    }
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var showingCrewPicker = false
    @State private var cancelConfirm: OPSConfirmConfig?

    private var isReschedule: Bool { request.existing != nil }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if let form {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            leadHeader

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                                SiteVisitWeekRail(
                                    selectedDate: form.mergedDate(),
                                    visitCountsByDay: SiteVisitBookingDayContext.countsByDay(contextVisits),
                                    onSelect: { day in
                                        self.form?.setDateAndTime(
                                            SiteVisitBookingDayContext.merging(
                                                day: day,
                                                timeOfDayFrom: form.mergedDate()
                                            )
                                        )
                                    }
                                )

                                bookedThatDaySection(form)

                                timeRow(form)
                                windowCaption(form)
                                if !form.isValid(now: Date()) {
                                    Text("PICK A FUTURE TIME")
                                        .font(OPSStyle.Typography.nanoLabel)
                                        .tracking(1.2)
                                        .foregroundColor(OPSStyle.Colors.roseTextM)
                                }
                            }

                            chipSection(
                                label: "DURATION",
                                options: form.durationOptions,
                                selected: form.durationMinutes,
                                caption: nil
                            ) { self.form?.selectDuration($0) }

                            crewSection(form)

                            chipSection(
                                label: "HEADS-UP",
                                options: form.headsUpOptions,
                                selected: form.headsUpMinutes,
                                caption: "PUSH BEFORE THE VISIT"
                            ) { self.form?.selectHeadsUp($0) }

                            if let errorMessage {
                                errorRow(errorMessage)
                            }

                            if isReschedule {
                                cancelVisitRow
                            }

                            Spacer(minLength: OPSStyle.Layout.spacing4)
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing3)
                        .padding(.bottom, 100)
                    }
                } else {
                    ProgressView()
                        .tint(OPSStyle.Colors.text2)
                }
            }
            .standardSheetToolbar(
                title: isReschedule ? "RESCHEDULE" : "BOOK VISIT",
                actionText: isReschedule ? "SAVE" : "BOOK",
                isActionEnabled: canCommit,
                isSaving: isSaving,
                onCancel: { dismiss() },
                onAction: { commit() }
            )
        }
        .interactiveDismissDisabled(isSaving)
        .colorScheme(.dark)
        .task { await prepareForm() }
        .sheet(isPresented: $showingCrewPicker) {
            if let companyId = dataController.currentUser?.companyId {
                TeamMemberPickerSheet(
                    selectedTeamMemberIds: assigneeBinding,
                    allTeamMembers: dataController.getTeamMembers(companyId: companyId)
                        .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
                )
            }
        }
        .opsConfirm($cancelConfirm)
        .onReceive(
            NotificationCenter.default.publisher(for: Notification.Name("SiteVisitBookingChanged"))
        ) { _ in
            loadContext()
        }
        .animation(OPSStyle.Animation.standard, value: errorMessage)
    }

    // MARK: - Form lifecycle

    // A reschedule with nothing changed stays committable — commit() skips
    // the RPC and the sheet simply closes, which is what "SAVE with nothing
    // to save" should feel like.
    private var canCommit: Bool {
        guard let form, !isSaving else { return false }
        return form.isValid(now: Date())
    }

    private func prepareForm() async {
        guard form == nil, let userId = dataController.currentUser?.id else { return }
        // The form renders immediately on the product default; the operator's
        // own default lands async and only while the row is untouched.
        if let existing = request.existing {
            form = .reschedule(
                existing: existing,
                bookerId: userId,
                defaultHeadsUpMinutes: 30
            )
        } else {
            form = .create(
                bookerId: userId,
                defaultHeadsUpMinutes: 30,
                startingAt: Self.defaultStart()
            )
        }
        // Same hop the heads-up seed below uses — the WHEN surface reads the
        // SwiftData main context, so it must land on the main actor.
        await MainActor.run { loadContext() }
        let defaultLead = await fetchDefaultHeadsUp()
        await MainActor.run {
            form?.seedDefaultHeadsUp(defaultLead)
        }
    }

    /// Tomorrow 9:00 — the first slot an operator realistically books from a
    /// door-step conversation today.
    static func defaultStart(now: Date = Date(), calendar: Calendar = .current) -> Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func fetchDefaultHeadsUp() async -> Int {
        guard let userId = dataController.currentUser?.id,
              let companyId = dataController.currentUser?.companyId else { return 30 }
        let repo = NotificationPreferencesRepository()
        let prefs = try? await repo.fetchPreferences(userId: userId, companyId: companyId)
        return prefs?.siteVisitReminderLeadMinutes ?? 30
    }

    // MARK: - Commit

    private func commit() {
        guard let form, canCommit else { return }
        isSaving = true
        errorMessage = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                let bookingService = await resolveService()
                if isReschedule {
                    let intent = form.rescheduleIntent()
                    if intent.hasChanges {
                        _ = try await bookingService.reschedule(
                            siteVisitId: intent.siteVisitId,
                            scheduledAt: intent.scheduledAt,
                            durationMinutes: intent.durationMinutes,
                            assigneeIds: intent.assigneeIds,
                            reminderOverride: intent.reminderOverride
                        )
                        await applyRescheduleLocally(intent, form: form)
                    }
                } else {
                    let intent = form.createIntent()
                    let visitId = try await bookingService.book(
                        opportunityId: request.lead.id,
                        scheduledAt: intent.scheduledAt,
                        durationMinutes: intent.durationMinutes,
                        assigneeIds: intent.assigneeIds,
                        reminderLeadMinutes: intent.reminderLeadMinutes
                    )
                    await insertBookedVisitLocally(visitId: visitId, form: form)
                }
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    NotificationCenter.default.post(
                        name: Notification.Name("SiteVisitBookingChanged"),
                        object: nil,
                        userInfo: ["leadId": request.lead.id]
                    )
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = (error as? SiteVisitBookingError)?.errorDescription
                        ?? SiteVisitBookingError.server(detail: "\(error)").errorDescription
                }
            }
        }
    }

    private func requestCancelVisit() {
        guard let existing = request.existing else { return }
        cancelConfirm = OPSConfirmConfig(
            title: "CANCEL VISIT?",
            message: "The appointment comes off every calendar. The lead keeps its record.",
            verb: "CANCEL VISIT",
            isDestructive: true
        ) {
            performCancel(existing)
        }
    }

    private func performCancel(_ existing: BookSiteVisitForm.BookingSnapshot) {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                let bookingService = await resolveService()
                _ = try await bookingService.cancel(siteVisitId: existing.siteVisitId)
                await markCancelledLocally(existing.siteVisitId)
                await MainActor.run {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    NotificationCenter.default.post(
                        name: Notification.Name("SiteVisitBookingChanged"),
                        object: nil,
                        userInfo: ["leadId": request.lead.id]
                    )
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = (error as? SiteVisitBookingError)?.errorDescription
                        ?? SiteVisitBookingError.server(detail: "\(error)").errorDescription
                }
            }
        }
    }

    @MainActor
    private func resolveService() -> SiteVisitBookingService {
        service ?? SiteVisitBookingService()
    }

    // MARK: - Local mirror (server truth, applied immediately)

    @MainActor
    private func insertBookedVisitLocally(visitId: String, form: BookSiteVisitForm) {
        guard let context = dataController.modelContext,
              let userId = dataController.currentUser?.id else { return }
        let intent = form.createIntent()
        let visit = SiteVisit(
            id: visitId,
            opportunityId: request.lead.id,
            companyId: request.lead.companyId,
            status: .scheduled,
            scheduledAt: intent.scheduledAt,
            durationMinutes: intent.durationMinutes,
            assigneeIds: intent.assigneeIds ?? [userId],
            createdBy: userId
        )
        visit.bookedAt = Date()
        visit.reminderLeadMinutes = intent.reminderLeadMinutes
        // Already server truth — must never enter the outbound queue or the
        // orphan sweep. The first realtime echo converges server-owned fields.
        visit.needsSync = false
        visit.lastSyncedAt = nil
        context.insert(visit)
        try? context.save()
        mirrorBookingChange(visitId: visit.id)
    }

    @MainActor
    private func applyRescheduleLocally(
        _ intent: BookSiteVisitForm.RescheduleIntent,
        form: BookSiteVisitForm
    ) {
        guard let context = dataController.modelContext,
              let visit = fetchLocalVisit(id: intent.siteVisitId, in: context) else { return }
        if let scheduledAt = intent.scheduledAt { visit.scheduledAt = scheduledAt }
        if let duration = intent.durationMinutes { visit.durationMinutes = duration }
        if let assignees = intent.assigneeIds { visit.assigneeIds = assignees }
        if case .set(let lead) = intent.reminderOverride { visit.reminderLeadMinutes = lead }
        if case .clear = intent.reminderOverride { visit.reminderLeadMinutes = nil }
        try? context.save()
        mirrorBookingChange(visitId: visit.id)
    }

    @MainActor
    private func markCancelledLocally(_ visitId: String) {
        guard let context = dataController.modelContext,
              let visit = fetchLocalVisit(id: visitId, in: context) else { return }
        visit.status = .cancelled
        try? context.save()
        mirrorBookingChange(visitId: visitId)
    }

    /// Keep the personal-calendar mirror in lockstep with the booking —
    /// mirrorEvent is self-healing, so book, reschedule, and cancel all
    /// resolve through the same call (cancel unmirrors via eligibility).
    @MainActor
    private func mirrorBookingChange(visitId: String) {
        Task {
            await CalendarMirrorService.shared.mirrorEvent(opsId: visitId, source: .siteVisit)
        }
    }

    @MainActor
    private func fetchLocalVisit(id: String, in context: ModelContext) -> SiteVisit? {
        let lower = id.lowercased()
        var descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate { $0.id == lower }
        )
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Header

    private var leadHeader: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(request.lead.displayContactName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)
            if let address = request.lead.address, !address.isEmpty {
                Text(address)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Field rows

    private func timeRow(_ form: BookSiteVisitForm) -> some View {
        pickerRow(label: "TIME") {
            DatePicker(
                "",
                selection: dateBinding,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .colorScheme(.dark)
            .tint(OPSStyle.Colors.text)
        }
    }

    // MARK: - WHEN context (other booked visits)

    /// The selected day's already-booked visits — the scheduler sheet's
    /// day-panel idea at appointment scale. Informational, never blocking:
    /// the operator books over it if they know better.
    @ViewBuilder
    private func bookedThatDaySection(_ form: BookSiteVisitForm) -> some View {
        let dayVisits = SiteVisitBookingDayContext.visits(contextVisits, on: form.mergedDate())
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("BOOKED — \(DaySheetDateToken.day(form.mergedDate()))")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(alignment: .leading, spacing: 0) {
                if dayVisits.isEmpty {
                    Text("—")
                        .font(OPSStyle.Typography.metadata)
                        .foregroundColor(OPSStyle.Colors.textMute)
                        .padding(.vertical, OPSStyle.Layout.spacing2)
                        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                        .accessibilityLabel("Nothing booked that day")
                } else {
                    ForEach(Array(dayVisits.enumerated()), id: \.element.id) { index, visit in
                        contextVisitRow(visit)
                        if index < dayVisits.count - 1 {
                            Rectangle()
                                .fill(OPSStyle.Colors.fillNeutralDim)
                                .frame(height: OPSStyle.Layout.Border.standard)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()
        }
    }

    private func contextVisitRow(_ visit: BookingDayVisit) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Text(Self.windowText(start: visit.start, durationMinutes: visit.durationMinutes))
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .monospacedDigit()

            Text(contextName(for: visit))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(contextName(for: visit)), \(Self.windowText(start: visit.start, durationMinutes: visit.durationMinutes))"
        )
    }

    private func contextName(for visit: BookingDayVisit) -> String {
        guard let opportunityId = visit.opportunityId else { return "Site visit" }
        return contextNamesByOpportunityId[opportunityId.lowercased()] ?? "Site visit"
    }

    /// "ENDS 11:30 AM", plus a tan non-blocking collision note when the
    /// chosen window intersects an existing visit (scheduler philosophy:
    /// signals inform, they never overrule).
    @ViewBuilder
    private func windowCaption(_ form: BookSiteVisitForm) -> some View {
        let dayVisits = SiteVisitBookingDayContext.visits(contextVisits, on: form.mergedDate())
        let end = form.mergedDate().addingTimeInterval(TimeInterval(form.durationMinutes * 60))
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("ENDS \(Self.timeText(end))")
                .font(OPSStyle.Typography.nanoLabel)
                .tracking(0.8)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .monospacedDigit()

            if let clash = SiteVisitBookingDayContext.overlap(
                chosenStart: form.mergedDate(),
                durationMinutes: form.durationMinutes,
                against: dayVisits
            ) {
                Text("OVERLAPS — \(contextName(for: clash).uppercased()) · \(Self.windowText(start: clash.start, durationMinutes: clash.durationMinutes))")
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                    .monospacedDigit()
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private static func windowText(start: Date, durationMinutes: Int) -> String {
        let end = start.addingTimeInterval(TimeInterval(durationMinutes * 60))
        return "\(timeText(start)) – \(timeText(end))"
    }

    private static func timeText(_ date: Date) -> String {
        contextTimeFormatter.string(from: date).uppercased()
    }

    private static let contextTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    // MARK: - Context loading

    /// Booked appointments from the local store (synced company-wide), scoped
    /// by the operator's calendar visibility, excluding the booking being
    /// moved. Works offline — the store is the source; names then fall back
    /// to the resolver's last-good cache or "Site visit".
    @MainActor
    private func loadContext() {
        guard let context = dataController.modelContext,
              let user = dataController.currentUser else { return }
        // Company id is stored lowercased on every SiteVisit row (model init
        // and SiteVisitWire both normalize), so match in that canonical form.
        let companyId = request.lead.companyId.lowercased()
        let todayStart = Calendar.current.startOfDay(for: Date())
        // The predicate carries only the shape SwiftData translates reliably
        // (SiteVisitBookingLookup's house rule); booking, window, and status
        // are decided in Swift — a company holds a modest number of visits.
        let descriptor = FetchDescriptor<SiteVisit>(
            predicate: #Predicate<SiteVisit> { $0.companyId == companyId && $0.deletedAt == nil }
        )
        let stored = ((try? context.fetch(descriptor)) ?? []).filter { visit in
            guard visit.bookedAt != nil, let scheduledAt = visit.scheduledAt else { return false }
            return scheduledAt >= todayStart
        }
        contextVisits = SiteVisitBookingDayContext.contextVisits(
            in: stored,
            currentUserId: user.id,
            canViewAllCalendar: PermissionStore.shared.can("calendar.view", requiredScope: "all"),
            excluding: request.existing?.siteVisitId
        )
        resolveContextNames()
    }

    private func resolveContextNames() {
        guard let user = dataController.currentUser,
              let companyId = user.companyId else { return }
        let ids = Array(Set(contextVisits.compactMap { $0.opportunityId?.lowercased() }))
        guard !ids.isEmpty else { return }
        Task {
            let details = await leadResolver.refreshDetails(
                opportunityIds: ids,
                userId: user.id,
                companyId: companyId
            )
            await MainActor.run {
                contextNamesByOpportunityId = details.mapValues { $0.displayName }
            }
        }
    }

    private func pickerRow<Picker: View>(
        label: String,
        @ViewBuilder picker: () -> Picker
    ) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            picker()
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var dateBinding: Binding<Date> {
        Binding(
            get: { form?.mergedDate() ?? Date() },
            set: { form?.setDateAndTime($0) }
        )
    }

    private var assigneeBinding: Binding<Set<String>> {
        Binding(
            get: { form?.assigneeIds ?? [] },
            set: { form?.setAssignees($0) }
        )
    }

    // MARK: - Chip section

    private func chipSection(
        label: String,
        options: [Int],
        selected: Int,
        caption: String?,
        onSelect: @escaping (Int) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text(label)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            ValueChipRow(
                options: options,
                selected: selected,
                label: BookSiteVisitForm.durationLabel,
                onSelect: onSelect
            )

            if let caption {
                Text(caption)
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
        }
    }

    // MARK: - Crew section

    private func crewSection(_ form: BookSiteVisitForm) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("WHO'S GOING")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingCrewPicker = true
            } label: {
                crewRowContent(form)
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Who's going, \(crewSummary(form))")
        }
    }

    private func crewRowContent(_ form: BookSiteVisitForm) -> some View {
        let members = selectedMembers(form)
        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: -6) {
                ForEach(Array(members.prefix(3)), id: \.id) { user in
                    UserAvatar(user: user, size: 28)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.background, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                if members.count > 3 {
                    Text("+\(members.count - 3)")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.leading, OPSStyle.Layout.spacing2)
                }
            }

            Text(crewSummary(form))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            Image(systemName: OPSStyle.Icons.chevronRight)
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(minHeight: 52)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .contentShape(Rectangle())
    }

    private func selectedMembers(_ form: BookSiteVisitForm) -> [User] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        var members = dataController.getTeamMembers(companyId: companyId)
        if let me = dataController.currentUser, !members.contains(where: { $0.id == me.id }) {
            members.append(me)
        }
        return members
            .filter { form.assigneeIds.contains($0.id.lowercased()) }
            .sorted { $0.fullName.localizedCaseInsensitiveCompare($1.fullName) == .orderedAscending }
    }

    private func crewSummary(_ form: BookSiteVisitForm) -> String {
        let members = selectedMembers(form)
        if members.count <= 1 {
            let isJustMe = form.assigneeIds == [dataController.currentUser?.id.lowercased() ?? ""]
            return isJustMe ? "You" : (members.first?.fullName ?? "You")
        }
        return "\(members.count) going"
    }

    // MARK: - Error + cancel rows

    private func errorRow(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// ERROR — \(isReschedule ? "NOT SAVED" : "NOT BOOKED")")
                .font(OPSStyle.Typography.nanoLabel)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.roseTextM)
            Text(message)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var cancelVisitRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            requestCancelVisit()
        } label: {
            Text("CANCEL VISIT")
                .font(OPSStyle.Typography.buttonLabel)
                .kerning(0.27)
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isSaving)
        .accessibilityLabel("Cancel this visit")
    }
}
