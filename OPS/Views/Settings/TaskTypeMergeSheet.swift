//
//  TaskTypeMergeSheet.swift
//  OPS
//
//  Target-type picker for merging one task type into another. Reassigns
//  every ProjectTask from the source type to the chosen target type via the
//  canonical DataController path, then soft-deletes the source type. Used
//  when a task type can't be deleted outright because it still owns tasks.
//

import SwiftUI
import SwiftData

struct TaskTypeMergeSheet: View {
    let source: TaskType
    let allCompanyTypes: [TaskType]
    /// Fires after the merge+delete finishes so the parent can refresh its
    /// task-type list and close any edit sheet that was showing.
    let onComplete: () -> Void

    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTargetId: String? = nil
    @State private var isMerging: Bool = false
    @State private var mergeError: String? = nil
    @State private var showingConfirmation: Bool = false

    private var sourceActiveTaskCount: Int {
        source.tasks.filter { $0.deletedAt == nil }.count
    }

    private var candidateTargets: [TaskType] {
        // Offer every other task type in the same company (including defaults
        // — merging into a default is a legitimate cleanup move). Sorted with
        // the same precedence the list uses.
        allCompanyTypes
            .filter { $0.id != source.id && $0.deletedAt == nil }
            .sorted {
                if $0.isDefault != $1.isDefault {
                    return !$0.isDefault && $1.isDefault
                }
                return $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending
            }
    }

    private var selectedTarget: TaskType? {
        guard let id = selectedTargetId else { return nil }
        return candidateTargets.first { $0.id == id }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                if candidateTargets.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            intro
                            targetList
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                }

                if !candidateTargets.isEmpty {
                    VStack {
                        Spacer()
                        mergeBar
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("MERGE TASK TYPE")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .tracking(1.2)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryAccent)
                }
            }
            .alert("Merge into \(selectedTarget?.display ?? "")?", isPresented: $showingConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Merge", role: .destructive) {
                    Task { await performMerge() }
                }
            } message: {
                Text("\(sourceActiveTaskCount) task\(sourceActiveTaskCount == 1 ? "" : "s") currently using \(source.display) will be reassigned to \(selectedTarget?.display ?? ""). \(source.display) will then be deleted. This cannot be undone.")
            }
            .errorToast($mergeError, label: Feedback.Err.mergeFailed)
            .loadingOverlay(isPresented: $isMerging, message: "Merging…")
        }
    }

    // MARK: - Subviews

    private var intro: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color(hex: source.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 44, height: 44)
                    Image(systemName: source.icon ?? "hammer.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(source.display.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .tracking(1.0)
                    Text("\(sourceActiveTaskCount) task\(sourceActiveTaskCount == 1 ? "" : "s") will be reassigned")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Text("Pick the task type that should absorb every task currently using \(source.display).")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var targetList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("[ MERGE INTO ]")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .tracking(1.2)

            VStack(spacing: 0) {
                ForEach(candidateTargets) { target in
                    targetRow(target)

                    if target.id != candidateTargets.last?.id {
                        OPSStyle.Colors.separator
                            .frame(height: 1)
                            .padding(.leading, 60)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
    }

    private func targetRow(_ target: TaskType) -> some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            selectedTargetId = target.id
        }) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(Color(hex: target.color) ?? OPSStyle.Colors.primaryAccent)
                        .frame(width: 36, height: 36)
                    Image(systemName: target.icon ?? "hammer.fill")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.display)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    let count = target.tasks.filter { $0.deletedAt == nil }.count
                    Text("\(count) current task\(count == 1 ? "" : "s")")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }

                Spacer()

                if target.isDefault {
                    Text("DEFAULT")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(OPSStyle.Colors.background.opacity(0.6))
                        .cornerRadius(4)
                }

                Image(systemName: selectedTargetId == target.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(selectedTargetId == target.id ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var mergeBar: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [OPSStyle.Colors.background.opacity(0), OPSStyle.Colors.background],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 20)

            HStack(spacing: 12) {
                Button(action: { dismiss() }) {
                    Text("Cancel")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                }
                .disabled(isMerging)

                Button(action: {
                    guard selectedTarget != nil else { return }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    showingConfirmation = true
                }) {
                    Text("Merge")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(selectedTarget != nil ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBorder)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(selectedTarget == nil || isMerging)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
            .background(OPSStyle.Colors.background)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text("NO OTHER TASK TYPES")
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .tracking(1.2)
            Text("Create another task type before merging — there's nowhere to merge into.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)
        }
    }

    // MARK: - Merge

    /// Reassigns every active task from the source type to the target type,
    /// saves locally, records sync operations, then soft-deletes the source.
    /// The soft-delete uses the DataController path so cascading doesn't
    /// re-delete the freshly-reassigned tasks.
    ///
    /// Bug 4dadd96c — also re-pins every Product and TaskTemplate that
    /// pointed at the source type. Without this, merging left dangling
    /// products on the source type and templates orphaned in the catalog.
    private func performMerge() async {
        guard let target = selectedTarget else { return }
        guard !isMerging else { return }
        isMerging = true

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let targetId = target.id
        let sourceId = source.id

        // Reassign every active task to the target type.
        let activeTasks = source.tasks.filter { $0.deletedAt == nil }
        for task in activeTasks {
            task.taskType = target
            task.needsSync = true
            dataController.syncEngine.recordOperation(
                entityType: .projectTask,
                entityId: task.id,
                operationType: "update",
                changedFields: ["task_type_id": targetId]
            )
        }

        // Re-pin every Product that pointed at the source. Both columns get
        // rewritten so legacy `task_type_id` text reads land on the same
        // parent as the canonical `task_type_ref` reads.
        let productDescriptor = FetchDescriptor<Product>(
            predicate: #Predicate<Product> { product in
                product.taskTypeRef == sourceId || product.taskTypeId == sourceId
            }
        )
        let linkedProducts = (try? modelContext.fetch(productDescriptor)) ?? []
        for product in linkedProducts {
            product.taskTypeRef = targetId
            product.taskTypeId = targetId
        }

        // Re-pin every TaskTemplate (sub-task scaffolding) that pointed at
        // the source so the merge target inherits the workflow steps.
        let templateDescriptor = FetchDescriptor<TaskTemplate>(
            predicate: #Predicate<TaskTemplate> { template in
                (template.taskTypeRef == sourceId || template.taskTypeId == sourceId)
                && template.deletedAt == nil
            }
        )
        let linkedTemplates = (try? modelContext.fetch(templateDescriptor)) ?? []
        for template in linkedTemplates {
            template.taskTypeRef = targetId
            template.taskTypeId = targetId
            template.needsSync = true
        }

        do {
            try modelContext.save()
        } catch {
            isMerging = false
            mergeError = error.localizedDescription
            return
        }

        // Mirror the local re-pins server-side. Failures here aren't fatal —
        // the rows have `needsSync` and the SwiftData snapshot is authoritative
        // locally; the next sync sweep will reconcile.
        let companyId = source.companyId
        let productRepo = ProductRepository(companyId: companyId)
        for product in linkedProducts {
            var fields = UpdateProductDTO()
            fields.taskTypeRef = targetId
            fields.taskTypeId = targetId
            do {
                _ = try await productRepo.update(product.id, fields: fields)
            } catch {
                print("[TaskTypeMerge] ⚠️ Product re-pin sync failed for \(product.id): \(error)")
            }
        }

        let templateRepo = TaskTemplateRepository(companyId: companyId)
        for template in linkedTemplates {
            var fields = UpdateTaskTemplateDTO()
            fields.taskTypeRef = targetId
            fields.taskTypeId = targetId
            do {
                _ = try await templateRepo.update(template.id, fields: fields)
            } catch {
                print("[TaskTypeMerge] ⚠️ TaskTemplate re-pin sync failed for \(template.id): \(error)")
            }
        }

        // Source type no longer owns any active tasks, products, or templates,
        // so the cascading soft delete inside DataController.deleteTaskType
        // won't touch the rows we just reassigned.
        do {
            try await dataController.deleteTaskType(taskTypeId: source.id)
        } catch {
            isMerging = false
            mergeError = error.localizedDescription
            return
        }

        dataController.triggerBackgroundSync()

        isMerging = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        ToastCenter.shared.present(Feedback.Settings.mergeComplete)
        onComplete()
        dismiss()
    }
}
