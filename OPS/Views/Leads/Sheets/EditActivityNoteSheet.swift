//
//  EditActivityNoteSheet.swift
//  OPS
//
//  Amend a note that has already been logged (bug f740400e).
//
//  A note was write-once: the operator typed it into LOG ACTIVITY, it landed on
//  the lead's rail, and a typo — or the half of the thought he remembered
//  afterwards — was there for good. The only repair was a second note correcting
//  the first, which is how a rail turns into a transcript of its own corrections.
//
//  Scoped to notes on purpose. A call, an email, a site visit, a stage change:
//  those are records of something that happened somewhere else, and rewriting
//  one would make the lead's history a fiction. A note is the operator's own
//  writing about his own job, and it has to be fixable. `ActivityRepository`
//  re-checks the type so the scope cannot widen by accident from a call site.
//
//  One field, one button. The sheet holds the operator's text through a failed
//  save — losing what he just typed to a dropped connection is the one outcome
//  worth designing against.
//

import SwiftUI

struct EditActivityNoteSheet: View {
    let activity: Activity
    /// Returns true when the amendment is stored. False keeps the sheet up with
    /// the operator's text and an inline reason.
    let onSave: @MainActor (String) async -> Bool

    @Environment(\.dismiss) private var dismiss

    @State private var noteText: String = ""
    @State private var isSaving = false
    @State private var inlineError: String?

    private var trimmed: String {
        noteText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A blank note is not a note, and re-saving untouched text is a round trip
    /// that buys nothing.
    private var canSave: Bool {
        !trimmed.isEmpty && trimmed != (activity.displayBody ?? "") && !isSaving
    }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                        Text("// WHAT HAPPENED")
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(OPSStyle.Colors.textMute)

                        LeadTextArea(
                            placeholder: "Anything worth remembering.",
                            text: $noteText,
                            rows: 6
                        )
                        .accessibilityIdentifier("lead-note-edit-field")
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
        .interactiveDismissDisabled(isSaving)
        .onAppear { noteText = activity.displayBody ?? "" }
        .accessibilityIdentifier("lead-note-edit-sheet")
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "EDIT NOTE", size: .half)
            SheetCloseButton { dismiss() }
                .disabled(isSaving)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if let inlineError {
                SheetStatusLine(mode: .error(inlineError))
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
            }

            SheetCTAButton(
                label: "SAVE NOTE",
                icon: OPSStyle.Icons.checkmark,
                isLoading: isSaving,
                action: save
            )
            .disabled(!canSave)
            .opacity(canSave ? 1 : OPSStyle.Layout.Opacity.medium)
            .accessibilityIdentifier("lead-note-edit-save")
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

    private func save() {
        guard canSave else { return }
        let amended = trimmed
        isSaving = true
        inlineError = nil

        Task { @MainActor in
            let succeeded = await onSave(amended)
            isSaving = false
            if succeeded {
                dismiss()
            } else {
                inlineError = "COULD NOT SAVE NOTE · TRY AGAIN"
            }
        }
    }
}
