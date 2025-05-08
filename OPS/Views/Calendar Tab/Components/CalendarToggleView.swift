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
        HStack(alignment: .top, spacing: 16) {
            // Week/Month toggle with segmented control style
            ZStack {
                // Background
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color("TextPrimary"))
                    .frame(height: 36)
                
                // Toggle buttons
                HStack(spacing: 0) {
                    // Week toggle
                    Button(action: {
                        withAnimation {
                            if viewModel.viewMode != .week {
                                viewModel.toggleViewMode()
                            }
                        }
                    }) {
                        Text("Week")
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.viewMode == .week ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                Group {
                                    if viewModel.viewMode == .week {
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius - 2)
                                            .fill(Color.black)
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                    }
                    
                    // Month toggle
                    Button(action: {
                        withAnimation {
                            if viewModel.viewMode != .month {
                                viewModel.toggleViewMode()
                            }
                        }
                    }) {
                        Text("Month")
                            .font(OPSStyle.Typography.body)
                            .fontWeight(.medium)
                            .foregroundColor(viewModel.viewMode == .month ? .white : .black)
                            .frame(maxWidth: .infinity)
                            .frame(height: 32)
                            .background(
                                Group {
                                    if viewModel.viewMode == .month {
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius - 2)
                                            .fill(Color.black)
                                    } else {
                                        Color.clear
                                    }
                                }
                            )
                    }
                }
                .padding(2)
            }
            .frame(width: 200)
            
            Spacer()
            
            // Period display with picker - simplified
            Button(action: {
                showDatePicker = true
            }) {
                Text(periodString)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(.black)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
            .frame(height: 36)
            .popover(isPresented: $showDatePicker) {
                DatePickerPopover(
                    mode: viewModel.viewMode == .week ? .week : .month,
                    selectedDate: viewModel.selectedDate,
                    onSelectDate: { date in
                        withAnimation {
                            viewModel.selectDate(date)
                        }
                    }
                )
                .presentationCompactAdaptation(.popover)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    // Dynamic period string based on view mode - simplified without year
    private var periodString: String {
        let formatter = DateFormatter()
        
        switch viewModel.viewMode {
        case .week:
            // For week view, show the week range (e.g. "May 3-9")
            let calendar = Calendar.current
            
            // Get start of the week containing selected date
            let weekStart = calendar.date(from: calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: viewModel.selectedDate))!
            
            // Get end of week
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
            // For month view, show just the month name
            formatter.dateFormat = "MMMM"
            return formatter.string(from: viewModel.selectedDate)
        }
    }
}
