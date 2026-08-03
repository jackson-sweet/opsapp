//
//  LeadArchiveSheet.swift
//  OPS
//
//  Parking a real lead. Bug e0c8084f: archive used to be one confirm dialog and
//  a timestamp, so the reason a job was parked never survived to the day the
//  owner went looking for it.
//
//  Weight is the whole design problem here. Discard is a decision — its sheet
//  makes you pick a reason before anything happens. Archive is reversible and
//  routine, so ARCHIVE stays one tap: the reason chips and the note are both
//  optional and sit UNDER the button in reading order, offered rather than
//  demanded. An owner clearing five stale leads on a Friday never has to answer
//  a question; the one who wants to leave themselves a note can.
//

import SwiftUI

struct LeadArchiveSheet: View {
    let opportunity: Opportunity
    /// Returns true when the archive stuck — the sheet dismisses itself.
    let onArchive: (LeadArchiveReason?, String?) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var reason: LeadArchiveReason?
    @State private var note = ""
    @State private var showsNote = false
    @State private var isWorking = false

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        archiveButton
                        reasonSection
                        noteDisclosure
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isWorking)
        .accessibilityIdentifier("lead-archive-sheet")
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            SheetTitleLabel(title: "ARCHIVE LEAD", size: .half)

            Text("// OFF YOUR BOARD · RESTORE ANY TIME")
                .font(OPSStyle.Typography.miniLabel)
                .foregroundColor(OPSStyle.Colors.textMute)
                .kerning(1.4)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing3)
    }

    // MARK: - Primary action

    /// First in reading order and reachable with nothing else touched — the
    /// one-tap path is the common path.
    private var archiveButton: some View {
        SheetCTAButton(
            label: "ARCHIVE",
            icon: "archivebox",
            variant: .primary,
            isLoading: isWorking,
            action: commit
        )
        .disabled(isWorking)
        .accessibilityIdentifier("lead-archive-confirm")
    }

    // MARK: - Optional reason

    private var reasonSection: some View {
        LeadField(label: "REASON", hint: "[OPTIONAL]") {
            LeadChipPicker(
                selection: Binding(
                    get: { reason?.rawValue ?? "" },
                    set: { raw in
                        // Tapping the lit chip clears it — the operator can get
                        // back to "no reason" without leaving the sheet.
                        let tapped = LeadArchiveReason(rawValue: raw)
                        reason = (tapped == reason) ? nil : tapped
                    }
                ),
                options: Self.reasonOptions
            )
        }
        .disabled(isWorking)
    }

    static let reasonOptions: [LeadChipOption] = LeadArchiveReason.selectableReasons.map {
        LeadChipOption(id: $0.rawValue, label: $0.label)
    }

    // MARK: - Optional note

    private var noteDisclosure: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Button {
                showsNote.toggle()
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: OPSStyle.Icons.notes)
                    Text(showsNote ? "HIDE NOTE" : "ADD NOTE")
                    Spacer(minLength: OPSStyle.Layout.spacing2)
                    Image(systemName: showsNote ? "chevron.up" : "chevron.down")
                }
                .font(OPSStyle.Typography.buttonLabel)
                .foregroundColor(OPSStyle.Colors.text2)
                .lineLimit(1)
                .frame(
                    maxWidth: .infinity,
                    minHeight: OPSStyle.Layout.touchTargetMin,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isWorking)
            .accessibilityIdentifier("lead-archive-note-toggle")

            if showsNote {
                LeadTextArea(
                    placeholder: "Why it's parked.",
                    text: $note,
                    rows: 3
                )
                .onChange(of: note) { _, newValue in
                    if newValue.count > LeadDispositionInteractionPolicy.noteLimit {
                        note = String(newValue.prefix(LeadDispositionInteractionPolicy.noteLimit))
                    }
                }
                .accessibilityIdentifier("lead-archive-note")

                Text("\(note.count)/\(LeadDispositionInteractionPolicy.noteLimit)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.textMute)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }

    // MARK: - Commit

    private func commit() {
        guard !isWorking else { return }
        isWorking = true
        Task {
            let succeeded = await onArchive(
                reason,
                LeadDispositionInteractionPolicy.normalizedNote(note)
            )
            if succeeded {
                dismiss()
            } else {
                isWorking = false
            }
        }
    }
}
