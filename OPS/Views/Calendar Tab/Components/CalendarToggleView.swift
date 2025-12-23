//
//  CalendarToggleView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-24.
//


// CalendarToggleView.swift
import SwiftUI

struct CalendarToggleView: View {
    @ObservedObject var viewModel: CalendarViewModel
    @Environment(\.tutorialMode) private var tutorialMode
    @Environment(\.tutorialPhase) private var tutorialPhase
    @State private var showDatePicker = false
    @State private var tutorialHighlightPulse = false

    /// Whether to show tutorial highlight on the Month button
    private var shouldHighlightMonth: Bool {
        tutorialMode && tutorialPhase == .calendarMonthPrompt
    }

    /// Whether to disable the segmented control during calendarWeek phase only
    private var isSegmentedControlDisabled: Bool {
        tutorialMode && tutorialPhase == .calendarWeek
    }

    /// Whether to disable the week picker button during both calendarWeek AND calendarMonthPrompt phases
    private var isWeekPickerDisabled: Bool {
        tutorialMode && (tutorialPhase == .calendarWeek || tutorialPhase == .calendarMonthPrompt)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Week/Month toggle with segmented control style
            SegmentedControl(
                selection: Binding(
                    get: { viewModel.viewMode },
                    set: { newMode in
                        // Block interaction during calendarWeek phase only
                        guard !isSegmentedControlDisabled else { return }
                        withAnimation {
                            if newMode != viewModel.viewMode {
                                viewModel.toggleViewMode()
                                // Notify tutorial system when month is tapped
                                if tutorialMode && tutorialPhase == .calendarMonthPrompt && newMode == .month {
                                    NotificationCenter.default.post(
                                        name: Notification.Name("TutorialCalendarMonthTapped"),
                                        object: nil
                                    )
                                }
                            }
                        }
                    }
                ),
                options: [
                    (CalendarViewModel.CalendarViewMode.week, "Week"),
                    (CalendarViewModel.CalendarViewMode.month, "Month")
                ]
            )
            .overlay(
                // Tutorial: Dark overlay when disabled during calendarWeek phase only
                Group {
                    if isSegmentedControlDisabled {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(Color.black.opacity(0.7))
                            .allowsHitTesting(true)
                    }
                }
            )
            .overlay(
                // Tutorial: Grey out the Week side and highlight the Month side
                GeometryReader { geo in
                    if shouldHighlightMonth {
                        HStack(spacing: 0) {
                            // Grey overlay on Week side (left half) - blocks interaction
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .fill(Color.black.opacity(0.5))
                                .frame(width: geo.size.width / 2)

                            // Month side highlight (right half) - allows interaction
                            ZStack {
                                // Glow effect behind the border
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .fill(TutorialHighlightStyle.color.opacity(0.15))
                                    .frame(width: geo.size.width / 2)
                                    .allowsHitTesting(false)

                                // Pulsing border
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .strokeBorder(TutorialHighlightStyle.color, lineWidth: 3)
                                    .frame(width: geo.size.width / 2)
                                    .opacity(tutorialHighlightPulse ? TutorialHighlightStyle.pulseOpacity.max : TutorialHighlightStyle.pulseOpacity.min)
                                    .animation(
                                        .easeInOut(duration: TutorialHighlightStyle.pulseDuration)
                                        .repeatForever(autoreverses: true),
                                        value: tutorialHighlightPulse
                                    )
                                    .allowsHitTesting(false)
                            }
                            .shadow(color: TutorialHighlightStyle.color.opacity(0.5), radius: 6, x: 0, y: 0)
                            .allowsHitTesting(false)
                        }
                    }
                }
            )
            .onAppear {
                if shouldHighlightMonth {
                    tutorialHighlightPulse = true
                }
            }
            .onChange(of: tutorialPhase) { _, newPhase in
                tutorialHighlightPulse = tutorialMode && newPhase == .calendarMonthPrompt
            }
            //.frame(width: 200)
            // Remove explicit height to let SegmentedControl use its natural height
            
            Spacer()
            
            // Period display with picker - fixed width and matching segmented control
            Button(action: {
                guard !isWeekPickerDisabled else { return }
                showDatePicker = true
            }) {
                Text(periodString)
                    .font(.bodyBold) // Match the font used in SegmentedControl
                    .foregroundColor(.black)
                    .frame(width: 100) // Fixed width to accommodate "September" and week ranges
                    .padding(.vertical, 12) // Match the padding in SegmentedControl
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .overlay(
                // Tutorial: Dark overlay when disabled during calendarWeek AND calendarMonthPrompt phases
                Group {
                    if isWeekPickerDisabled {
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .fill(Color.black.opacity(0.7))
                            .allowsHitTesting(true)
                    }
                }
            )
            .popover(isPresented: $showDatePicker) {
                DatePickerPopover(
                    mode: viewModel.viewMode == .week ? .week : .month,
                    selectedDate: viewModel.viewMode == .month ? viewModel.visibleMonth : viewModel.selectedDate,
                    onSelectDate: { date in
                        print("📅 CalendarToggleView: onSelectDate called with \(date)")
                        if viewModel.viewMode == .month {
                            let calendar = Calendar.current
                            if let monthStart = calendar.dateInterval(of: .month, for: date)?.start {
                                print("📅 Setting visibleMonth to \(monthStart)")
                                DispatchQueue.main.async {
                                    viewModel.visibleMonth = monthStart
                                    viewModel.selectDate(monthStart, userInitiated: false)
                                    print("📅 visibleMonth set to \(self.viewModel.visibleMonth)")
                                }
                            }
                        } else {
                            viewModel.selectDate(date)
                        }
                        showDatePicker = false
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.vertical, 8)
    }
    
    // Dynamic period string based on view mode - simplified without year
    private var periodString: String {
        let formatter = DateFormatter()
        
        switch viewModel.viewMode {
        case .week:
            // For week view, show the week range (e.g. "May 3-9")
            var calendar = Calendar.current
            calendar.firstWeekday = 2

            // Get start of the week containing selected date (Monday)
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: viewModel.selectedDate))!

            // Get end of week (Sunday)
            let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart)!
            
            // Format start date
            formatter.dateFormat = "MMM d"
            let startString = formatter.string(from: weekStart)
            
            // For end date, check if it's in the same month
            if calendar.component(.month, from: weekStart) == calendar.component(.month, from: weekEnd) {
                formatter.dateFormat = "d"
            } else {
                formatter.dateFormat = "MMM d"
            }
            let endString = formatter.string(from: weekEnd)
            
            return "\(startString)-\(endString)"
            
        case .month:
            // For month view, show the currently visible month
            formatter.dateFormat = "MMMM"
            return formatter.string(from: viewModel.visibleMonth)
        }
    }
}
