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
    
    var body: some View {
        HStack(spacing: 0) {
            // Week toggle
            toggleButton(
                title: "Week",
                isSelected: viewModel.viewMode == .week,
                action: {
                    withAnimation {
                        if viewModel.viewMode != .week {
                            viewModel.toggleViewMode()
                        }
                    }
                }
            )
            
            // Month toggle
            toggleButton(
                title: "Month",
                isSelected: viewModel.viewMode == .month,
                action: {
                    withAnimation {
                        if viewModel.viewMode != .month {
                            viewModel.toggleViewMode()
                        }
                    }
                }
            )
            
            Spacer()
            
            // Month/year picker
            Button(action: {}) {
                HStack(spacing: 8) {
                    Text("April, 2025")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(OPSStyle.Colors.cardBackground.opacity(0.5))
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
        .frame(height: 44)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
    
    private func toggleButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(isSelected ? OPSStyle.Colors.cardBackground : Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}
