import SwiftUI

/// Read-only audit feedback is shared by the crew's expense sheet and the
/// office review card. Historical values come from the immutable receipt.
struct ExpenseCorrectionHistoryView: View {
    let expense: ExpenseDTO
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var corrections: [ExpenseCorrectionDTO] = []
    @State private var isLoading = false
    @State private var failed = false
    @State private var loadGeneration = 0

    private var loadIdentity: String {
        [expense.companyId, expense.id, expense.updatedAt, dataController.currentUser?.id ?? "",
         dataController.currentUser?.companyId ?? ""].joined(separator: ":")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            if isLoading {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    ProgressView().tint(OPSStyle.Colors.secondaryText)
                    Text("Loading review history")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            } else if failed {
                Text("Review history couldn't load.")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Button("RETRY") { Task { await load() } }
                    .font(OPSStyle.Typography.button)
                    .opsSecondaryButtonStyle()
                    .accessibilityLabel("Retry expense review history")
            } else {
                ForEach(corrections) { correction in
                    ExpenseCorrectionRecordView(
                        correction: correction,
                        actorName: dataController.getUser(id: correction.actorId)?.fullName
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: loadIdentity) {
            corrections = []
            await load()
        }
    }

    private func load() async {
        loadGeneration += 1
        let generation = loadGeneration
        let identity = loadIdentity
        failed = false
        guard let user = dataController.currentUser,
              user.companyId?.lowercased() == expense.companyId.lowercased() else {
            corrections = []
            isLoading = false
            return
        }
        isLoading = true
        defer { if generation == loadGeneration { isLoading = false } }
        do {
            let result = try await viewModel.loadExpenseCorrections(
                expenseId: expense.id, companyId: expense.companyId, actorId: user.id
            )
            guard !Task.isCancelled, identity == loadIdentity, generation == loadGeneration else { return }
            corrections = result
        } catch {
            guard !Task.isCancelled, identity == loadIdentity, generation == loadGeneration else { return }
            failed = true
        }
    }
}

struct ExpenseCorrectionRecordView: View {
    let correction: ExpenseCorrectionDTO
    let actorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("CORRECTED & RETURNED")
                .font(OPSStyle.Typography.sectionLabel)
                .foregroundColor(OPSStyle.Colors.primaryText)
            if let actorName, !actorName.isEmpty {
                Text("BY \(actorName.uppercased())")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            if let date = SupabaseDate.parse(correction.correctedAt) {
                Text(date.formatted(date: .abbreviated, time: .shortened))
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            if !correction.correctionNote.isEmpty {
                Text(correction.correctionNote)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(ExpenseCorrectionChange.changes(in: correction)) { change in
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(change.label)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("FROM  \(change.before)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Text("TO    \(change.after)")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, OPSStyle.Layout.spacing1)
                .accessibilityElement(children: .combine)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OPSStyle.Layout.spacing3)
        .glassSurface()
    }
}
