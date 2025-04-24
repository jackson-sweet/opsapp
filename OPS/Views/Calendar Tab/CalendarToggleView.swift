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
        }
        .frame(height: 44)
        .background(OPSStyle.Colors.cardBackground)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .padding(.horizontal)
    }
    
    private func toggleButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isSelected ? OPSStyle.Colors.cardBackground : Color.clear)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
        }
    }
}