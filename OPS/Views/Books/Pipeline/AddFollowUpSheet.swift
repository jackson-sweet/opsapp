//
//  AddFollowUpSheet.swift
//  OPS
//
//  Modal for adding a scheduled follow-up to a lead. `title` is required
//  (DB NOT NULL with no backfill trigger — bug fix #12 in spec).
//

import SwiftUI

struct AddFollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (String, String?, FollowUpType, Date, Date?) -> Void

    @State private var title: String = ""
    @State private var description: String = ""
    @State private var type: FollowUpType = .call
    @State private var dueAt: Date = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var reminderEnabled: Bool = false
    @State private var reminderAt: Date = Date()

    private var canSave: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("ADD FOLLOW-UP")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("TITLE *")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("e.g. Follow up re quote", text: $title)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))

                        Text("TYPE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Picker("TYPE", selection: $type) {
                            ForEach(FollowUpType.allCases, id: \.self) { t in
                                Text(t.rawValue.uppercased()).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("DUE")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        DatePicker("", selection: $dueAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                            .labelsHidden()
                            .colorScheme(.dark)

                        Toggle("REMINDER", isOn: $reminderEnabled)
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .tint(OPSStyle.Colors.text)

                        if reminderEnabled {
                            DatePicker("", selection: $reminderAt, in: Date()...dueAt, displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden()
                                .colorScheme(.dark)
                        }

                        Text("DESCRIPTION (OPTIONAL)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextEditor(text: $description)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(OPSStyle.Layout.spacing2)
                            .frame(minHeight: 100)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("ADD") {
                        onSave(
                            title.trimmingCharacters(in: .whitespacesAndNewlines),
                            description.isEmpty ? nil : description,
                            type,
                            dueAt,
                            reminderEnabled ? reminderAt : nil
                        )
                        dismiss()
                    }
                    .foregroundColor(canSave ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                    .disabled(!canSave)
                }
            }
        }
        .presentationDetents([.large])
    }
}
