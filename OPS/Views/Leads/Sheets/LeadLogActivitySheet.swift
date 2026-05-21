//
//  LeadLogActivitySheet.swift
//  OPS
//
//  Half-detent sheet for capturing an Activity against a lead. Phase 4 of
//  the LEADS tab rebuild
//  (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.7).
//
//  Triggered from the LOG quick-glyph on a LeadActionCard. Lands a row in
//  the activities table via `LeadDetailViewModel.logActivity`. After save,
//  posts a LeadActivityLoggedSuccess notification so LeadsTabView can reload
//  buckets — a newly-logged activity bumps `lastActivityAt` which re-shuffles
//  the WAITING / FRESH / OVERDUE classifications.
//
//  Per bible §10:205, a first Activity logged on a `newLead` auto-advances
//  it to `qualifying` via a server-side trigger.
//
//  Drag indicator + medium detent set by the parent (LeadsTabView.sheetView).
//

import SwiftUI

struct LeadLogActivitySheet: View {
    let opportunity: Opportunity

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var activityType: ActivityType = .call
    @State private var direction: String = "outbound"
    @State private var subjectText: String = ""
    @State private var bodyText: String = ""
    @State private var outcome: String = ""
    @State private var durationText: String = ""
    @State private var hasEditedSubject = false

    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !isSaving
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        typeSection
                        if showsDirection { directionSection }
                        subjectSection
                        bodySection
                        if showsOutcome { outcomeSection }
                        if showsDuration { durationSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 140)
                }
                .scrollIndicators(.hidden)
            }

            footerOverlay
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
        .onAppear { regenerateDefaultSubjectIfNeeded() }
        .onChange(of: activityType) { _, _ in
            regenerateDefaultSubjectIfNeeded()
        }
    }

    // MARK: - Header

    private var header: some View {
        // Drag handle is provided by the parent's `.presentationDragIndicator(.visible)`
        SheetTitleLabel(title: "LOG ACTIVITY", size: .half)
            .padding(.horizontal, 20)
            .padding(.top, 6)
            .padding(.bottom, 12)
    }

    // MARK: - Type

    private var typeSection: some View {
        LeadField(label: "TYPE") {
            LeadChipPicker(
                selection: typeBinding,
                options: LeadLogActivitySheet.typeOptions
            )
        }
    }

    private var typeBinding: Binding<String> {
        Binding(
            get: { activityType.rawValue },
            set: { newValue in
                if let t = ActivityType(rawValue: newValue) { activityType = t }
            }
        )
    }

    static let typeOptions: [LeadChipOption] = [
        .init(id: ActivityType.call.rawValue,     label: "CALL"),
        .init(id: ActivityType.email.rawValue,    label: "EMAIL"),
        .init(id: "sms",                          label: "SMS"),
        .init(id: ActivityType.siteVisit.rawValue, label: "VISIT"),
        .init(id: ActivityType.note.rawValue,     label: "NOTE"),
        .init(id: ActivityType.meeting.rawValue,  label: "MEETING"),
    ]

    // MARK: - Direction

    private var showsDirection: Bool {
        // VISIT and NOTE don't carry direction
        activityType != .note && activityType != .siteVisit
    }

    private var directionSection: some View {
        LeadField(label: "DIRECTION") {
            LeadChipPicker(
                selection: $direction,
                options: [
                    .init(id: "inbound",  label: "INBOUND"),
                    .init(id: "outbound", label: "OUTBOUND"),
                ]
            )
        }
    }

    // MARK: - Subject

    private var subjectSection: some View {
        LeadField(label: "SUBJECT", hint: "[OPTIONAL]") {
            LeadTextInput(
                placeholder: defaultSubject(),
                text: Binding(
                    get: { subjectText },
                    set: { newValue in
                        subjectText = newValue
                        hasEditedSubject = !newValue.isEmpty
                    }
                )
            )
        }
    }

    private func defaultSubject() -> String {
        let leadName = opportunity.contactName.isEmpty ? "lead" : opportunity.contactName
        switch activityType {
        case .call:      return "Call with \(leadName)"
        case .email:     return "Email to \(leadName)"
        case .siteVisit: return "Visit to \(leadName)"
        case .note:      return "Note on \(leadName)"
        case .meeting:   return "Meeting with \(leadName)"
        default:         return "Activity on \(leadName)"
        }
    }

    private func regenerateDefaultSubjectIfNeeded() {
        // Only auto-fill when the operator hasn't typed their own subject.
        // Once they've edited the field once, we leave it alone.
        if !hasEditedSubject {
            subjectText = ""
        }
    }

    // MARK: - Body

    private var bodySection: some View {
        LeadField(label: "BODY", hint: "[OPTIONAL]") {
            LeadTextArea(
                placeholder: bodyPlaceholder(),
                text: $bodyText,
                rows: 4
            )
        }
    }

    private func bodyPlaceholder() -> String {
        switch activityType {
        case .call:      return "What did you talk about?"
        case .email:     return "Paste the gist of the email here."
        case .siteVisit: return "What did you find on site?"
        case .note:      return "Anything worth remembering."
        case .meeting:   return "Agenda, decisions, next steps."
        default:         return "Details…"
        }
    }

    // MARK: - Outcome

    private var showsOutcome: Bool {
        activityType != .note
    }

    private var outcomeSection: some View {
        LeadField(label: "OUTCOME", hint: "[OPTIONAL]") {
            LeadChipPicker(
                selection: $outcome,
                options: LeadLogActivitySheet.outcomeOptions
            )
        }
    }

    static let outcomeOptions: [LeadChipOption] = [
        .init(id: "left_voicemail", label: "LEFT VOICEMAIL"),
        .init(id: "spoke",          label: "SPOKE"),
        .init(id: "no_answer",      label: "NO ANSWER"),
        .init(id: "replied",        label: "REPLIED"),
        .init(id: "booked_visit",   label: "BOOKED VISIT"),
        .init(id: "other",          label: "OTHER"),
    ]

    // MARK: - Duration

    private var showsDuration: Bool {
        activityType != .note && activityType != .email
    }

    private var durationSection: some View {
        LeadField(label: "DURATION", hint: "[MINUTES, OPTIONAL]") {
            HStack(spacing: 10) {
                LeadTextInput(
                    placeholder: "15",
                    text: $durationText,
                    keyboard: .numberPad
                )
                .frame(maxWidth: 120)

                Text("MINUTES")
                    .font(.custom("JetBrainsMono-Regular", size: 11))
                    .kerning(1.4)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .textCase(.uppercase)

                Spacer()
            }
        }
    }

    // MARK: - Footer

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, 20)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, 20)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isSaving)
            } primary: {
                SheetCTAButton(
                    label: "LOG",
                    icon: "checkmark",
                    variant: .primary,
                    isLoading: isSaving,
                    action: save
                )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.95),
                    .black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    // MARK: - Save

    private func save() {
        guard canSave else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let vm = LeadDetailViewModel(
                    opportunityId: opportunity.id,
                    companyId: opportunity.companyId
                )

                let resolvedSubject = subjectText.isEmpty ? defaultSubject() : subjectText
                let resolvedDirection: String? = showsDirection ? direction : nil
                let resolvedOutcome: String? = (showsOutcome && !outcome.isEmpty) ? outcome : nil
                let resolvedDuration: Int? = {
                    guard showsDuration else { return nil }
                    let trimmed = durationText.trimmingCharacters(in: .whitespaces)
                    return Int(trimmed)
                }()

                try await vm.logActivity(
                    type: activityType,
                    subject: resolvedSubject,
                    body: bodyText.isEmpty ? nil : bodyText,
                    direction: resolvedDirection,
                    outcome: resolvedOutcome,
                    durationMinutes: resolvedDuration
                )

                // Local optimistic — bump lastActivityAt so triage buckets
                // re-classify before the next full reload completes.
                opportunity.lastActivityAt = Date()

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadActivityLoggedSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                dismiss()
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func simplifyError(_ error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP TO RETRY"
        }
        return "COULD NOT LOG — TAP TO RETRY"
    }
}
