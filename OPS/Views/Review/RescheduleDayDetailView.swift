//
//  RescheduleDayDetailView.swift
//  OPS
//
//  Day-detail surface reached by pinching out (or tapping the inspect
//  affordance) on the task reschedule sheet. Lists every event already
//  scheduled for the target day so the operator can see what they're
//  pushing into before committing — then move the task there in one tap.
//
//  Event data comes from the canonical day query
//  `DataController.getScheduledTasks(for:)` (same source the calendar uses),
//  and the row rendering mirrors CalendarSchedulerSheet's day inspector so
//  the two surfaces read identically (task-color stripe, crew dots, date).
//

import SwiftUI

struct RescheduleDayDetailView: View {
    /// The task being rescheduled. Used to compute the destination range
    /// (preserving the task's duration) and to mark its own events.
    let task: ProjectTask
    /// The day the operator zoomed into.
    let day: Date
    /// Confirm — move the task to this day. Receives the destination
    /// start/end so the caller routes through its canonical reschedule path
    /// (save + sync + cascade preview).
    let onConfirm: (_ newStart: Date, _ newEnd: Date) -> Void
    /// Back out without changing anything (collapse the zoom).
    let onClose: () -> Void

    @EnvironmentObject private var dataController: DataController

    /// Events scheduled on `day`, excluding the task being moved (its own
    /// dates are implied by the action, not a thing to schedule around).
    @State private var dayEvents: [ProjectTask] = []

    // MARK: - Destination range
    //
    // Moving "to this day" anchors the task's start at the focused day and
    // preserves its existing duration. Mirrors SchedulingEngine.pushByDays'
    // duration math (duration - 1 days added to the new start) so a 3-day
    // task dropped on Mon spans Mon–Wed, not just Mon.

    private var destinationStart: Date {
        Calendar.current.startOfDay(for: day)
    }

    private var destinationEnd: Date {
        let extraDays = max(task.duration - 1, 0)
        return Calendar.current.date(byAdding: .day, value: extraDays, to: destinationStart) ?? destinationStart
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                    dayHeaderCard
                    eventsSection
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            confirmFooter
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .onAppear(perform: loadDayEvents)
    }

    // MARK: - Day Header Card
    //
    // States the day being inspected and the move that will happen. Pinch is
    // reversible right up to the confirm tap, so the header doubles as a
    // close affordance via the collapse control.

    private var dayHeaderCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Text("//")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                Text("DAY DETAIL")
                    .font(OPSStyle.Typography.metadata)
                    .tracking(1.2)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)

                // Collapse — non-gesture path back to the chip view so the
                // surface is escapable without a reverse-pinch (and works
                // under reduced motion). Mirrors the pinch-in dismissal.
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onClose()
                } label: {
                    Image(OPSStyle.Icons.collapse)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Collapse day detail")
            }

            Text(dayHeadlineLabel(for: day))
                .font(OPSStyle.Typography.dataValue)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)

            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(height: OPSStyle.Layout.Border.standard)

            // Destination summary — what the move resolves to. Multi-day
            // tasks show the spanned range; single-day tasks show one date.
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1 + 2) {
                sectionEyebrow(task.isMultiDay ? "MOVES TO" : "NEW START")
                Text(destinationLabel)
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
    }

    // MARK: - Events Section

    @ViewBuilder
    private var eventsSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                sectionEyebrow("ON THIS DAY")
                Spacer(minLength: 0)
                Text("\(dayEvents.count)")
                    .font(OPSStyle.Typography.dataValue)
                    .monospacedDigit()
                    .foregroundColor(OPSStyle.Colors.primaryText)
                +
                Text(dayEvents.count == 1 ? " EVENT" : " EVENTS")
                    .font(OPSStyle.Typography.category)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }

            if dayEvents.isEmpty {
                emptyDayState
            } else {
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(dayEvents) { event in
                        eventRow(event)
                    }
                }
            }
        }
    }

    // MARK: - Empty State
    //
    // Forward-looking per OPS empty-state pattern: name what would appear,
    // then point at the action. Em-dash bullet, no "N/A".

    private var emptyDayState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("—")
                    .font(OPSStyle.Typography.dataValue)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                Text("Nothing scheduled here")
                    .font(OPSStyle.Typography.cardSubtitle)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer(minLength: 0)
            }
            Text("A clear day. Move this work in and it's yours.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.5))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Event Row
    //
    // Mirrors CalendarSchedulerSheet.dayInspectorRow: leading stripe in the
    // task's color (white if it's the same project as the moving task),
    // title, day/crew metadata line, crew-conflict flag. Reproduced here
    // because that row is file-private to the scheduler sheet.

    private func eventRow(_ event: ProjectTask) -> some View {
        let isSameProject = (event.projectId == task.projectId) && !task.projectId.isEmpty
        let movingCrew = Set(task.getTeamMemberIds())
        let isCrewConflict = !movingCrew.isEmpty && !Set(event.getTeamMemberIds()).isDisjoint(with: movingCrew)
        let timeLabel = eventTimeLabel(event)

        return HStack(spacing: OPSStyle.Layout.spacing2_5) {
            RoundedRectangle(cornerRadius: OPSStyle.Layout.progressBarRadius)
                .fill(isSameProject ? OPSStyle.Colors.primaryText : event.swiftUIColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(event.displayTitle)
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if isSameProject {
                        Text("THIS PROJECT")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .padding(.horizontal, OPSStyle.Layout.spacing1)
                            .padding(.vertical, 1)
                            .background(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                                    .fill(OPSStyle.Colors.primaryText)
                            )
                    }
                }
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(timeLabel)
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    if !event.teamMembers.isEmpty {
                        Text("·")
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.inactiveText)
                        HStack(spacing: OPSStyle.Layout.spacing1 / 2) {
                            ForEach(event.teamMembers.prefix(4)) { user in
                                Circle()
                                    .fill(colorFor(user: user))
                                    .frame(
                                        width: OPSStyle.Layout.Indicator.dotMD - 1,
                                        height: OPSStyle.Layout.Indicator.dotMD - 1
                                    )
                            }
                            if event.teamMembers.count > 4 {
                                Text("+\(event.teamMembers.count - 4)")
                                    .font(OPSStyle.Typography.metadata)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        }
                    }
                }
            }

            Spacer(minLength: 0)

            if isCrewConflict {
                Text("CONFLICT")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.warningStatus)
                    .padding(.horizontal, OPSStyle.Layout.spacing1)
                    .padding(.vertical, 1)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .strokeBorder(OPSStyle.Colors.warningStatus.opacity(0.6), lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .padding(.horizontal, OPSStyle.Layout.spacing2)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .fill(OPSStyle.Colors.cardBackgroundDark)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .strokeBorder(OPSStyle.Colors.cardBorderSubtle, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Confirm Footer
    //
    // Steel-blue fill is the single dominant signal — the move CTA. Commit
    // haptic (.medium) fires on tap; the caller's reschedule path adds the
    // success notification, keeping the two-beat commit feel.

    private var confirmFooter: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onConfirm(destinationStart, destinationEnd)
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(OPSStyle.Icons.calendarBadgeCheckmark)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    Text("MOVE TO THIS DAY")
                        .font(OPSStyle.Typography.captionBold)
                        .tracking(1.0)
                    Spacer(minLength: 0)
                    Text(moveChipLabel)
                        .font(OPSStyle.Typography.metadata)
                        .monospacedDigit()
                        .opacity(0.8)
                }
                .foregroundColor(.white)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetStandard)
                .background(OPSStyle.Colors.primaryAccent)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel("Move task to \(dayHeadlineLabel(for: day))")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                onClose()
            } label: {
                Text("BACK")
                    .font(OPSStyle.Typography.captionBold)
                    .tracking(1.0)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OPSStyle.Colors.cardBorderSubtle)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    // MARK: - Section Eyebrow

    private func sectionEyebrow(_ label: String) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)
            Text(label)
                .font(OPSStyle.Typography.metadata)
                .tracking(1.2)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Data

    private func loadDayEvents() {
        let selfId = task.id
        dayEvents = dataController.getScheduledTasks(for: day)
            .filter { $0.id != selfId }
    }

    // MARK: - Formatting

    private func dayHeadlineLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE · MMM d"
        return formatter.string(from: date).uppercased()
    }

    private var destinationLabel: String {
        if task.isMultiDay {
            let start = shortDate(destinationStart)
            let end = shortDate(destinationEnd)
            return "\(start) – \(end)  \(task.duration)D"
        }
        return dayHeadlineLabel(for: destinationStart)
    }

    /// Compact label shown on the move CTA chip — destination start only.
    private var moveChipLabel: String {
        shortDate(destinationStart)
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }

    /// Per-event time/range descriptor for the metadata line. Single-day
    /// events show "ALL DAY"; multi-day events show their span so the
    /// operator sees an event bleeding into the focused day from elsewhere.
    private func eventTimeLabel(_ event: ProjectTask) -> String {
        guard let start = event.startDate else { return "—" }
        if event.isMultiDay, let end = event.endDate {
            return "\(shortDate(start)) – \(shortDate(end))"
        }
        return "ALL DAY"
    }

    private func colorFor(user: User) -> Color {
        if let hex = user.userColor, !hex.isEmpty, let color = Color(hex: hex) {
            return color
        }
        return user.roleColor
    }
}
