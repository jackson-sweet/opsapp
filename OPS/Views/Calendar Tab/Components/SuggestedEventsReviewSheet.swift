//
//  SuggestedEventsReviewSheet.swift
//  OPS
//
//  Phase-C "Suggested events" review surface (item 63144953). Lists the
//  detected commitments OPS pulled from the operator's messages and lets them
//  confirm each one onto the calendar — or dismiss it. Reached only from the
//  schedule banner, which itself only appears when there's something to review,
//  so this sheet is never seen empty in normal use.
//

import SwiftUI

struct SuggestedEventsReviewSheet: View {
    @Binding var isPresented: Bool
    @ObservedObject var viewModel: CalendarViewModel
    @EnvironmentObject var dataController: DataController
    @StateObject private var mirrorService = CalendarMirrorService.shared

    /// First-add iPhone Calendar Mirror permission ask — reuses the established
    /// consent gate so confirming a suggestion can also land it on the phone.
    @State private var showingMirrorPrompt = false

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if viewModel.suggestedEvents.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            Text("Deadlines OPS caught in your messages — add the ones that matter.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .padding(.top, OPSStyle.Layout.spacing3_5)

                            ForEach(viewModel.suggestedEvents) { dto in
                                SuggestedEventCard(
                                    event: dto,
                                    onAdd: { handleAdd(dto) },
                                    onDismiss: { handleDismiss(dto) }
                                )
                                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                                .transition(.opacity.combined(with: .move(edge: .trailing)))
                            }
                        }
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                    }
                    .animation(OPSStyle.Animation.standard, value: viewModel.suggestedEvents)
                }
            }
            .navigationTitle("[ SUGGESTED EVENTS ]")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("DONE") { isPresented = false }
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
        .colorScheme(.dark)
        // Reuse the established consent gate for the add-to-phone step.
        .sheet(isPresented: $showingMirrorPrompt) {
            CalendarMirrorPromptSheet(isPresented: $showingMirrorPrompt)
        }
        .onChange(of: viewModel.suggestedEvents.isEmpty) { _, isEmpty in
            // Close once everything's been actioned — unless the consent prompt
            // is up (it's presented from this sheet and must outlive it).
            if isEmpty && !showingMirrorPrompt { isPresented = false }
        }
        .onChange(of: showingMirrorPrompt) { _, showing in
            if !showing && viewModel.suggestedEvents.isEmpty { isPresented = false }
        }
    }

    private var emptyState: some View {
        Text("Nothing to review right now.")
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.tertiaryText)
            .padding(OPSStyle.Layout.spacing4)
    }

    // MARK: - Actions

    private func handleAdd(_ dto: SuggestedCalendarEventDTO) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let wasLast = viewModel.suggestedEvents.count == 1
        // Match the UserEventSheet consent rule: ask once per install, only when
        // the OS permission has never been requested. Set BEFORE the async add so
        // the empty-list auto-close doesn't tear this sheet (and the prompt) down.
        let needsConsent = !mirrorService.hasShownPrompt
            && mirrorService.authorizationStatus == .notDetermined
        if needsConsent { showingMirrorPrompt = true }

        Task {
            let created = await viewModel.addSuggestedEvent(dto)
            await MainActor.run {
                if created {
                    if wasLast {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                } else if needsConsent {
                    // Add didn't happen (no user/company) — drop the consent ask.
                    showingMirrorPrompt = false
                }
            }
        }
    }

    private func handleDismiss(_ dto: SuggestedCalendarEventDTO) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        Task { await viewModel.dismissSuggestedEvent(dto) }
    }
}

// MARK: - Card

private struct SuggestedEventCard: View {
    let event: SuggestedCalendarEventDTO
    let onAdd: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            // When it's due
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "calendar")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm))
                    .foregroundColor(OPSStyle.Colors.opsAccent)
                Text(Self.dueLabel(for: event.dueDate))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            // What it is
            Text(CalendarViewModel.eventTitle(from: event.content))
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            // Actions — accent reserved for ADD; DISMISS is a quiet outline.
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Button(action: onDismiss) {
                    Text("DISMISS")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.separator, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .buttonStyle(PlainButtonStyle())

                Button(action: onAdd) {
                    Text("ADD")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: OPSStyle.Layout.touchTargetMin)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .background(OPSStyle.Colors.opsAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    /// "FRI · MAY 31 · ALL DAY" or "FRI · MAY 31 · 2:00 PM" — JetBrains Mono at
    /// the call site. Mirrors the all-day/timed split used when the event is built.
    static func dueLabel(for dueDate: Date) -> String {
        let timing = CalendarViewModel.eventTiming(for: dueDate)
        let dayFmt = DateFormatter()
        dayFmt.dateFormat = "EEE · MMM d"
        let dayPart = dayFmt.string(from: dueDate).uppercased()
        if timing.allDay {
            return "\(dayPart) · ALL DAY"
        }
        let timeFmt = DateFormatter()
        timeFmt.dateFormat = "h:mm a"
        return "\(dayPart) · \(timeFmt.string(from: dueDate).uppercased())"
    }
}
