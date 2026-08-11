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
                                dateRow(form)
                                timeRow(form)
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

    private func dateRow(_ form: BookSiteVisitForm) -> some View {
        pickerRow(label: "DATE") {
            DatePicker(
                "",
                selection: dateBinding,
                in: Calendar.current.startOfDay(for: Date())...,
                displayedComponents: .date
            )
            .datePickerStyle(.compact)
            .labelsHidden()
            .colorScheme(.dark)
            .tint(OPSStyle.Colors.text)
        }
    }

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
