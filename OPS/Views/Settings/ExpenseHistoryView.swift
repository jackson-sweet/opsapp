//
//  ExpenseHistoryView.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-13.
//

import SwiftUI

struct ExpenseHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack {
            // Background
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                // Header
                SettingsHeader(
                    title: "Expenses",
                    onBackTapped: {
                        dismiss()
                    }
                )
                
                // Coming soon content
                VStack(spacing: 32) {
                    Spacer()
                    
                    Image(systemName: "dollarsign.circle")
                        .font(OPSStyle.Typography.largeTitle)
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                    
                    Text("COMING SOON")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(.white)
                        .padding(.top, 24)
                    
                    Text("Expense tracking will be available in the next update")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                    
                    // Feature preview
                    VStack(alignment: .leading, spacing: 16) {
                        Text("PLANNED FEATURES")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .padding(.bottom, 4)
                        
                        featureRow(icon: "receipt", text: "Expense submission with photo receipts")
                        featureRow(icon: "chart.bar", text: "Track expense approvals and payments")
                        featureRow(icon: "folder.badge.plus", text: "Organize expenses by projects and categories")
                        featureRow(icon: "icloud.and.arrow.up", text: "Automatic syncing with office accounting")
                    }
                    .padding()
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(12)
                    .padding(.horizontal, 32)
                    .padding(.top, 24)
                    
                    Spacer()
                    Spacer()
                }
            }
        }
        .navigationBarBackButtonHidden(true)
    }
    
    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .frame(width: 24)
            
            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(.white)
            
            Spacer()
        }
    }
}

#Preview {
    ExpenseHistoryView()
        .preferredColorScheme(.dark)
}