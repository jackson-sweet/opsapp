//
//  ActivityFormSheet.swift
//  OPS
//
//  Sheet to log a new activity on an opportunity.
//

import SwiftUI

struct ActivityFormSheet: View {
    let opportunityId: String
    let companyId: String
    @ObservedObject var detailVM: OpportunityDetailViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var selectedType: ActivityType = .note
    @State private var body = ""
    @State private var isSaving = false

    private let userTypes: [ActivityType] = [.note, .call, .email, .meeting, .siteVisit]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: OPSStyle.Layout.spacing3) {
                    // Type picker
                    sectionHeader("TYPE")
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: OPSStyle.Layout.spacing2) {
                            ForEach(userTypes, id: \.self) { type in
                                Button {
                                    selectedType = type
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: type.icon)
                                            .font(.system(size: 14))
                                        Text(type.rawValue.uppercased().replacingOccurrences(of: "_", with: " "))
                                            .font(OPSStyle.Typography.smallCaption)
                                            .fontWeight(.medium)
                                    }
                                    .foregroundColor(
                                        selectedType == type
                                        ? OPSStyle.Colors.primaryText
                                        : OPSStyle.Colors.tertiaryText
                                    )
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedType == type
                                        ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                        : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                    )
                                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                            .stroke(
                                                selectedType == type
                                                ? OPSStyle.Colors.primaryAccent
                                                : Color.white.opacity(0.1),
                                                lineWidth: 1
                                            )
                                    )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }

                    // Notes
                    sectionHeader("NOTES")
                    TextEditor(text: $body)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .padding(OPSStyle.Layout.spacing2)
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }
                .padding(.top, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle("LOG ACTIVITY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if isSaving {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                    } else {
                        Button("SAVE") { save() }
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    private func save() {
        isSaving = true
        Task {
            await detailVM.logActivity(
                opportunityId: opportunityId,
                companyId: companyId,
                type: selectedType,
                body: body.isEmpty ? nil : body
            )
            dismiss()
        }
    }
}
