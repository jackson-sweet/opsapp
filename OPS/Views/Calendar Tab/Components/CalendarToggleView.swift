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
    @State private var showDatePicker = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Week/Month toggle with segmented control style
            SegmentedControl(
                selection: Binding(
                    get: { viewModel.viewMode },
                    set: { newMode in
                        withAnimation {
                            if newMode != viewModel.viewMode {
                                viewModel.toggleViewMode()
                            }
                        }
                    }
                ),
                options: [
                    (CalendarViewModel.CalendarViewMode.week, "Week"),
                    (CalendarViewModel.CalendarViewMode.month, "Month")
                ]
            )
            //.frame(width: 200)
            // Remove explicit height to let SegmentedControl use its natural height
            
            Spacer()
            
            // Period display with picker - fixed width and matching segmented control
            Button(action: {
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
