//
//  LeadDispositionReasonSheet.swift
//  OPS
//
//  Phase C correction sheet. A reason is selected first and committed with one
//  explicit footer action; optional context stays behind disclosure.
//

import SwiftUI

struct LeadDispositionReasonSheet: View {
    let opportunity: Opportunity
    let onSelect: (LeadDispositionReason, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var showsContext = false
    @State private var selectionState = LeadDispositionReasonSelectionState()

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            footer
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(selectionState.isSubmitting)
        .accessibilityIdentifier("lead-disposition-reason-sheet")
    }

    private func reasonRow(_ reason: LeadDispositionReason) -> some View {
        let isSelected = selectionState.selectedReason == reason

        return Button {
            selectionState.select(reason)
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

                Image(
                    systemName: isSelected
                        ? OPSStyle.Icons.checkmarkCircleFill
                        : OPSStyle.Icons.circle
                )
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(
                    isSelected
                        ? OPSStyle.Colors.opsAccent
                        : OPSStyle.Colors.textMute
                )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(
                maxWidth: .infinity,
                minHeight: OPSStyle.Layout.touchTargetStandard,
                alignment: .leading
            )
            .background(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.cardRadius,
                    style: .continuous
                )
                .fill(
                    isSelected
                        ? OPSStyle.Colors.surfaceActive
                        : OPSStyle.Colors.surfaceInput
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.cardRadius,
                    style: .continuous
                )
                .strokeBorder(
                    isSelected
                        ? OPSStyle.Colors.activeSegmentBorder
                        : OPSStyle.Colors.nestedBorder,
                    lineWidth: OPSStyle.Layout.Border.standard
                )
            )
            .clipShape(
                RoundedRectangle(
                    cornerRadius: OPSStyle.Layout.cardRadius,
                    style: .continuous
                )
            )
        }
        .buttonStyle(.plain)
        .disabled(selectionState.isSubmitting)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
            .disabled(selectionState.isSubmitting)
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

    private var footer: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if let inlineError = selectionState.inlineError {
                SheetStatusLine(mode: .error(inlineError))
            } else if selectionState.isSubmitting {
                SheetStatusLine(mode: .syncing)
            }

            SheetCTAButton(
                label: "APPLY REASON",
                icon: OPSStyle.Icons.checkmark,
                isLoading: selectionState.isSubmitting,
                action: submitSelection
            )
            .disabled(!selectionState.canSubmit)
            .opacity(selectionState.canSubmit ? 1 : OPSStyle.Layout.Opacity.medium)
            .accessibilityIdentifier("lead-disposition-apply-reason")
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2_5)
        .padding(.bottom, OPSStyle.Layout.spacing3_5)
        .background(OPSStyle.Colors.background)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(OPSStyle.Colors.lineSoft)
                .frame(height: OPSStyle.Layout.Border.standard)
        }
    }

    private func submitSelection() {
        guard let reason = selectionState.beginSubmission() else { return }
        let normalizedNote = LeadDispositionInteractionPolicy.normalizedNote(note)

        Task {
            let succeeded = await onSelect(reason, normalizedNote)
            selectionState.finishSubmission(succeeded: succeeded)
            if succeeded {
                dismiss()
            }
        }
    }
}
