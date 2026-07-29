//
//  LeadDispositionReasonSheet.swift
//  OPS
//
//  Phase C correction sheet. A standard reason submits on the first tap; the
//  optional note stays behind disclosure and is never used as model input.
//

import SwiftUI

struct LeadDispositionReasonSheet: View {
    let opportunity: Opportunity
    let onSelect: (LeadDispositionReason, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var showsContext = false
    @State private var selectedReason: LeadDispositionReason?

    private var isWorking: Bool { selectedReason != nil }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetTitleLabel(title: "WHY ISN'T THIS A LEAD?", size: .half)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        Text("// CHOOSE THE CLOSEST REASON")
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(OPSStyle.Colors.textMute)

                        ForEach(LeadDispositionReason.standardReasons, id: \.self) { reason in
                            reasonRow(reason)
                        }

                        contextDisclosure
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("lead-disposition-reason-sheet")
    }

    private func reasonRow(_ reason: LeadDispositionReason) -> some View {
        Button {
            guard !isWorking else { return }
            selectedReason = reason
            Task {
                let succeeded = await onSelect(reason, note)
                if succeeded {
                    dismiss()
                } else {
                    selectedReason = nil
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(reason.label)
                        .font(OPSStyle.Typography.buttonLabel)
                        .foregroundColor(OPSStyle.Colors.text)

                    Text(reason.detail)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.text2)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                if selectedReason == reason {
                    ProgressView()
                        .tint(OPSStyle.Colors.text2)
                } else {
                    Image(systemName: OPSStyle.Icons.forward)
                        .font(OPSStyle.Typography.miniLabel)
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(
                maxWidth: .infinity,
                minHeight: OPSStyle.Layout.touchTargetStandard,
                alignment: .leading
            )
            .nestedCard()
        }
        .buttonStyle(.plain)
        .disabled(isWorking)
        .accessibilityIdentifier("lead-disposition-reason-\(reason.rawValue)")
    }

    private var contextDisclosure: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Button {
                showsContext.toggle()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.notes)
                    Text(showsContext ? "HIDE CONTEXT" : "ADD CONTEXT")
                    Spacer()
                    Image(systemName: showsContext ? "chevron.up" : "chevron.down")
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.text2)
                .frame(
                    maxWidth: .infinity,
                    minHeight: OPSStyle.Layout.touchTargetMin,
                    alignment: .leading
                )
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("lead-disposition-context-toggle")

            if showsContext {
                LeadTextArea(
                    placeholder: "Short context for the record.",
                    text: $note,
                    rows: 3
                )
                .onChange(of: note) { _, newValue in
                    if newValue.count > LeadDispositionInteractionPolicy.noteLimit {
                        note = String(newValue.prefix(LeadDispositionInteractionPolicy.noteLimit))
                    }
                }
                .accessibilityIdentifier("lead-disposition-context-note")

                Text("\(note.count)/\(LeadDispositionInteractionPolicy.noteLimit)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }
}
