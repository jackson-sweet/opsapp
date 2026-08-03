//
//  DiscardExplainerSheet.swift
//  OPS
//
//  First-run education shown the first time an operator discards a lead.
//  Contrasts DISCARD (never a real lead — junk) with LOST (a real deal you
//  didn't win). Confirming performs the discard and flips the shared
//  `leads_discard_explainer_seen` flag so subsequent discards use the lighter
//  confirm dialog instead. Half-detent; mirrors LostReasonSheet chrome.
//
//    [title — DISCARD vs LOST]
//    [// LOST     — a real lead you chased and lost …]
//    [// DISCARD  — never a real lead — spam, wrong number …]
//    [CANCEL] [DISCARD LEAD] (rose-destructive)
//

import SwiftUI

struct DiscardExplainerSheet: View {
    let opportunity: Opportunity
    /// Returns true only after the guarded server transaction succeeds.
    let onConfirm: () async -> Bool

    @Environment(\.dismiss) private var dismiss
    @AppStorage("leads_discard_explainer_seen") private var explainerSeen = false
    @State private var isWorking = false

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                SheetTitleLabel(title: "DISCARD vs LOST", size: .half)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing2_5)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        definitionRow(
                            term: "LOST",
                            termColor: OPSStyle.Colors.text3,
                            body: "A real lead you chased and lost. Counts in your win rate.",
                            bodyColor: OPSStyle.Colors.text2
                        )
                        definitionRow(
                            term: "DISCARD",
                            termColor: OPSStyle.Colors.roseTextM,
                            body: "Never a real lead — spam, scam, or noise. Off your board, never a lost deal.",
                            bodyColor: OPSStyle.Colors.text
                        )
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
            }

            footer
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isWorking)
    }

    // MARK: - Definition row

    private func definitionRow(term: String, termColor: Color, body: String, bodyColor: Color) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(term)
                    .foregroundColor(termColor)
            }
            .font(OPSStyle.Typography.miniLabel)
            .kerning(1.4)
            .textCase(.uppercase)

            Text(body)
                .font(OPSStyle.Typography.body)
                .foregroundColor(bodyColor)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            Spacer()
            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isWorking)
            } primary: {
                SheetCTAButton(
                    label: "DISCARD LEAD",
                    icon: "nosign",
                    variant: .destructive,
                    isLoading: isWorking
                ) {
                    guard !isWorking else { return }
                    isWorking = true
                    Task {
                        let succeeded = await onConfirm()
                        if succeeded {
                            explainerSeen = true
                            dismiss()
                        } else {
                            isWorking = false
                        }
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .background(
            LinearGradient(
                colors: [
                    Color.black.opacity(0),
                    Color.black.opacity(0.95),
                    .black,
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 160)
            .allowsHitTesting(false),
            alignment: .bottom
        )
        .ignoresSafeArea(edges: .bottom)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }
}
