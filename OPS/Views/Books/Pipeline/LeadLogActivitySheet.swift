//
//  LeadLogActivitySheet.swift
//  OPS
//
//  Modal for adding a manual activity entry to a lead. Used from LeadDetailView.
//  Distinct from the voice-first LogActivitySheet in OPS/Views/Pipeline/.
//

import SwiftUI

struct LeadLogActivitySheet: View {
    @Environment(\.dismiss) private var dismiss

    var onSave: (ActivityType, String?, String?) -> Void

    @State private var type: ActivityType = .note
    @State private var subject: String = ""
    @State private var bodyText: String = ""

    private let userPickableTypes: [ActivityType] = [.note, .call, .email, .meeting, .siteVisit]

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        Text("LOG ACTIVITY")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("TYPE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                        Picker("TYPE", selection: $type) {
                            ForEach(userPickableTypes, id: \.self) { t in
                                Text(t.rawValue.uppercased()).tag(t)
                            }
                        }
                        .pickerStyle(.segmented)

                        Text("SUBJECT (OPTIONAL — TRIGGER BACKFILLS)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextField("e.g. Discussed pricing", text: $subject)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .padding(OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackground)
                            .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard))
                            .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius))

                        Text("BODY")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        TextEditor(text: $bodyText)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .scrollContentBackground(.hidden)
                            .padding(OPSStyle.Layout.spacing2)
                            .frame(minHeight: 160)
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
                    Button("SAVE") {
                        onSave(type,
                               subject.isEmpty ? nil : subject,
                               bodyText.isEmpty ? nil : bodyText)
                        dismiss()
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .disabled(subject.isEmpty && bodyText.isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
