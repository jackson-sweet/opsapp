//
//  AddressEditorSheet.swift
//  OPS
//
//  Simple sheet for editing a project's address.
//

import SwiftUI

struct AddressEditorSheet: View {
    @Binding var address: String
    let onSave: () -> Void
    let onCancel: () -> Void

    @State private var draft: String = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                Text("PROJECT ADDRESS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                TextField("Enter address", text: $draft, axis: .vertical)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(3...6)
                    .padding(OPSStyle.Layout.spacing3)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                            .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                    )
                    .padding(.horizontal, OPSStyle.Layout.spacing3)

                Spacer()
            }
            .padding(.top, OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("EDIT ADDRESS")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        address = draft
                        onSave()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .onAppear {
            draft = address
        }
    }
}
