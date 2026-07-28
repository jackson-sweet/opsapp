//
//  RejectConfirmationView.swift
//  OPS
//
//  Sheet presented when the reviewer taps "SEND BACK n" on a batch's detail.
//  Shows the flagged lines, lets the reviewer edit comments, unflag items,
//  and send the flags back to the crew (clean lines approve).
//

import SwiftUI

struct RejectConfirmationView: View {
    let batch: ExpenseBatchDTO
    @ObservedObject var viewModel: ExpenseViewModel
    var onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @State private var reviewNotes: String = ""

    // MARK: - Computed

    private var flaggedExpenses: [ExpenseDTO] {
        viewModel.selectedBatchExpenses.filter { viewModel.flaggedExpenseIds.contains($0.id) }
    }

    private var cleanCount: Int {
        viewModel.selectedBatchExpenses.count - flaggedExpenses.count
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        header
                            .padding(.top, OPSStyle.Layout.spacing3)

                        flaggedItemsList

                        contextLine

                        reviewNotesField
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.bottom, 100)
                }

                stickyFooter
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("CANCEL") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            Text(batch.batchNumber)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("\(flaggedExpenses.count) ITEM\(flaggedExpenses.count == 1 ? "" : "S") FLAGGED")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.warningStatus)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Flagged Items List

    private var flaggedItemsList: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            ForEach(flaggedExpenses) { expense in
                flaggedItemCard(expense)
            }
        }
    }

    private func flaggedItemCard(_ expense: ExpenseDTO) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            // Merchant + amount row
            HStack {
                Text(expense.merchantName ?? "UNKNOWN")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                Spacer()

                Text(BooksFormat.exact(expense.amount))
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            // Editable comment
            TextField(
                "Revision comment...",
                text: Binding(
                    get: { viewModel.flagComments[expense.id] ?? "" },
                    set: { viewModel.flagComments[expense.id] = $0 }
                )
            )
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(OPSStyle.Layout.spacing2)
            .background(OPSStyle.Colors.surfaceInput)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )

            // Unflag button
            Button {
                let expenseId = expense.id
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task {
                    await viewModel.unflagExpense(expenseId)
                }
            } label: {
                Text("UNFLAG")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .buttonStyle(PlainButtonStyle())
        }
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface(borderColor: OPSStyle.Colors.warningStatus)
    }

    // MARK: - Context Line

    private var contextLine: some View {
        Group {
            if !viewModel.selectedBatchExpenses.isEmpty {
                let flaggedCount = flaggedExpenses.count
                Text("\(cleanCount) expense\(cleanCount == 1 ? "" : "s") get\(cleanCount == 1 ? "s" : "") approved. \(flaggedCount) go\(flaggedCount == 1 ? "es" : "") back to the crew with your notes.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Review Notes

    private var reviewNotesField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("REVIEW NOTES")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            TextEditor(text: $reviewNotes)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.surfaceInput)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    // MARK: - Sticky Footer

    private var stickyFooter: some View {
        OPSFloatingButtonBar(horizontalPadding: OPSStyle.Layout.spacing3, verticalPadding: OPSStyle.Layout.spacing2) {
            Group {
                if flaggedExpenses.isEmpty {
                // All items unflagged — offer approve all
                Button {
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    Task {
                        await viewModel.approveBatch(batch)
                        dismiss()
                        onDismiss()
                    }
                } label: {
                    Text("APPROVE ALL")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.successStatus)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                // Flagged items remain — send revisions
                Button {
                    let userId = dataController.currentUser?.id ?? ""
                    let notes = reviewNotes.isEmpty ? nil : reviewNotes
                    UINotificationFeedbackGenerator().notificationOccurred(.warning)
                    Task {
                        await viewModel.sendRevisions(
                            batchId: batch.id,
                            batch: batch,
                            reviewedBy: userId,
                            reviewNotes: notes
                        )
                        dismiss()
                        onDismiss()
                    }
                } label: {
                    let count = flaggedExpenses.count
                    Text("SEND BACK \(count)")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.buttonText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(OPSStyle.Colors.errorStatus)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }

    // MARK: - Formatters

}
