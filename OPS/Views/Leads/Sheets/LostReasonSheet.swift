//
//  LostReasonSheet.swift
//  OPS
//
//  Half-detent sheet for marking a lead lost. Phase 4 of the LEADS tab
//  rebuild (docs/superpowers/plans/2026-05-19-leads-tab-rebuild.md §8.5).
//
//  Body:
//    [read-only L2 summary card — id · stage · value · name]
//    REASON         [PRICE] [TIMING] [COMPETITION] [SCOPE] [NO RESPONSE] [OTHER]
//    NOTES          [textarea, 4 rows, optional]
//
//  Footer: [CANCEL] [CONFIRM LOST] (rose-destructive)
//
//  Drag indicator + medium detent set by the parent (LeadsTabView.sheetView).
//

import SwiftUI

struct LostReasonSheet: View {
    let opportunity: Opportunity

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss

    @State private var reason: LossReason?
    @State private var notes: String = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool { reason != nil && !isSaving }

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        summaryCard
                        reasonSection
                        notesSection
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 130)
                }
                .scrollIndicators(.hidden)
            }

            footerOverlay
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(isSaving)
    }

    // MARK: - Header

    private var header: some View {
        // Drag handle is provided by the parent's `.presentationDragIndicator(.visible)`
        VStack(spacing: 0) {
            SheetTitleLabel(title: "MARK AS LOST")
                .padding(.top, 6)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Summary

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text(metaLine)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(.custom("JetBrainsMono-Regular", size: 10))
            .kerning(1.4)
            .textCase(.uppercase)

            Text(opportunity.title?.isEmpty == false
                 ? opportunity.title!
                 : opportunity.contactName)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .nestedCard()
    }

    private var metaLine: String {
        var parts: [String] = []
        parts.append(String(opportunity.id.prefix(6)).uppercased())
        parts.append(opportunity.stage.displayName)
        if let value = opportunity.estimatedValue, value > 0 {
            parts.append(formatCompactValue(value))
        } else {
            parts.append("—")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Reason

    private var reasonSection: some View {
        LeadField(label: "REASON") {
            LeadChipPicker(
                selection: reasonBinding,
                options: LostReasonSheet.options
            )
        }
    }

    private var reasonBinding: Binding<String> {
        Binding(
            get: { reason?.rawValue ?? "" },
            set: { reason = LossReason(rawValue: $0) }
        )
    }

    static let options: [LeadChipOption] = LossReason.allCases.map {
        LeadChipOption(id: $0.rawValue, label: $0.displayName)
    }

    // MARK: - Notes

    private var notesSection: some View {
        LeadField(label: "NOTES", hint: "[OPTIONAL]") {
            LeadTextArea(
                placeholder: "What did you learn? Useful for next quarter's win-rate review.",
                text: $notes,
                rows: 4
            )
        }
    }

    // MARK: - Footer

    private var footerOverlay: some View {
        VStack(spacing: 10) {
            Spacer()
            if let errorMessage {
                SheetStatusLine(mode: .error(errorMessage))
                    .padding(.horizontal, 20)
            } else if isSaving {
                SheetStatusLine(mode: .syncing)
                    .padding(.horizontal, 20)
            }

            SheetFooterButtonRow {
                SheetCTAButton(
                    label: "CANCEL",
                    variant: .secondary,
                    action: { dismiss() }
                )
                .disabled(isSaving)
            } primary: {
                SheetCTAButton(
                    label: "CONFIRM LOST",
                    icon: "xmark",
                    variant: .destructive,
                    isLoading: isSaving,
                    action: confirm
                )
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.5)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
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

    // MARK: - Save

    private func confirm() {
        guard let reason = reason else { return }
        errorMessage = nil
        isSaving = true

        Task {
            do {
                let companyId = opportunity.companyId
                _ = try await OpportunityRepository(companyId: companyId).markLost(
                    opportunityId: opportunity.id,
                    reason: reason,
                    notes: notes.isEmpty ? nil : notes,
                    userId: dataController.currentUser?.id
                )
                opportunity.stage = .lost
                opportunity.lostReason = reason.rawValue
                opportunity.lostNotes = notes.isEmpty ? nil : notes
                opportunity.actualCloseDate = Date()
                opportunity.stageEnteredAt = Date()

                UINotificationFeedbackGenerator().notificationOccurred(.success)
                NotificationCenter.default.post(
                    name: Notification.Name("LeadMarkedLostSuccess"),
                    object: nil,
                    userInfo: ["leadId": opportunity.id]
                )
                dismiss()
            } catch {
                isSaving = false
                errorMessage = simplifyError(error)
            }
        }
    }

    private func simplifyError(_ error: Error) -> String {
        let description = String(describing: error).lowercased()
        if description.contains("network") || description.contains("offline") {
            return "OFFLINE — TAP TO RETRY"
        }
        return "COULD NOT SAVE — TAP TO RETRY"
    }

    // MARK: - Formatting

    /// Compact currency: `$1.2K`, `$32K`, `$184K`, `$1.5M`. Whole numbers
    /// below 1K render with thousands separator.
    private func formatCompactValue(_ value: Double) -> String {
        if value >= 1_000_000 {
            let m = value / 1_000_000
            return String(format: "$%.1fM", m)
        }
        if value >= 1_000 {
            let k = value / 1_000
            if k >= 10 { return String(format: "$%.0fK", k) }
            return String(format: "$%.1fK", k)
        }
        let fmt = NumberFormatter()
        fmt.numberStyle = .decimal
        fmt.maximumFractionDigits = 0
        return "$" + (fmt.string(from: NSNumber(value: value)) ?? String(Int(value)))
    }
}
