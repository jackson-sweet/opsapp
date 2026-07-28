//
//  SchedulerDaySheet.swift
//  OPS
//
//  Long-press a day → the full truth about it.
//
//  The grid encodes a day in bars; the panel names what a *pick* costs. This
//  sheet is for the moment in between — "what is actually going on that
//  Thursday?" — asked about a day the operator has not committed to.
//
//  The header leads with one plain-language line, because the first thing a
//  person needs is not a list, it is a verdict: MARCUS OFF. DANA ON HARBOUR
//  DECK. CREW CLEAR. The rows underneath are the evidence for it.
//
//  Work that touches neither this crew nor this project is grouped under
//  `// ELSEWHERE` — present, because a day is not empty, but never competing
//  with the jobs that actually bear on the decision.
//

import SwiftUI

struct SchedulerDaySheet: View {
    let day: Date
    let context: SchedulerDayContext
    let action: SchedulerSelection.DayAction
    let onApply: () -> Void

    @Environment(\.dismiss) private var dismiss

    private let calendar = Calendar.current

    private var split: (relevant: [SchedulerDayContext.Event], elsewhere: [SchedulerDayContext.Event]) {
        context.events(on: day)
    }

    private var actionLabel: String {
        switch action {
        case .useAsStart: return "USE AS START"
        case .useAsEnd: return "USE AS END"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    let events = split

                    if events.relevant.isEmpty && events.elsewhere.isEmpty {
                        emptyLine
                    }

                    ForEach(events.relevant) { event in
                        row(event)
                    }

                    if !events.elsewhere.isEmpty {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            Text("//")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.inactiveText)
                            Text("ELSEWHERE")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Spacer(minLength: 0)
                        }
                        .padding(.top, OPSStyle.Layout.spacing2)

                        ForEach(events.elsewhere.prefix(elsewhereLimit)) { event in
                            row(event)
                        }

                        if events.elsewhere.count > elsewhereLimit {
                            Text("+ \(events.elsewhere.count - elsewhereLimit) MORE")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            actionButton
        }
        .background(OPSStyle.Colors.background)
    }

    /// Enough context to judge the day, short of turning the sheet into a
    /// second calendar.
    private var elsewhereLimit: Int { 4 }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Text("//")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.inactiveText)
                Text(SchedulerDayContext.weekdayDate(day, calendar: calendar).uppercased())
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: 0)
            }

            // The verdict. Everything below is evidence for it.
            Text(context.interpretation(for: day))
                .font(OPSStyle.Typography.cardSubtitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    private var emptyLine: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Text("//")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.inactiveText)
            Text(context.item.crewIds.isEmpty ? "NO JOBS" : "NO JOBS · CREW CLEAR")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Spacer(minLength: 0)
        }
    }

    private func row(_ event: SchedulerDayContext.Event) -> some View {
        SchedulerEventRow(
            event: event,
            isConflict: context.isConflict(event),
            isThisProject: context.isSameProject(event),
            attribution: context.attribution(for: event),
            distance: context.distanceLabel(to: event)
        )
    }

    // MARK: - Action

    /// Default button style, never accent — the accent belongs to SAVE, which
    /// is the only control on this flow that writes anything.
    private var actionButton: some View {
        Button {
            onApply()
            dismiss()
        } label: {
            Text(actionLabel)
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.bottomCTAHeight)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .fill(OPSStyle.Colors.surfaceInput)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                        .strokeBorder(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .contentShape(Rectangle())
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }
}
