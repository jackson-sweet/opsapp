//
//  TaskTemplateEditSheet.swift
//  OPS
//
//  Inline edit / create for a TaskTemplate row (sub-task under a TaskType).
//  Mirrors the TaskTypeSheet's section-card visual language so the editor
//  reads as part of the parent sheet, not a foreign modal.
//

import SwiftUI
import SwiftData

struct TaskTemplateEditSheet: View {
    enum Mode {
        case create(taskTypeId: String, companyId: String, onSave: (TaskTemplate) -> Void)
        case edit(template: TaskTemplate, onSave: () -> Void)

        var title: String {
            switch self {
            case .create: return "NEW SUB-TASK"
            case .edit:   return "EDIT SUB-TASK"
            }
        }
    }

    let mode: Mode

    @EnvironmentObject private var dataController: DataController
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = ""
    @State private var templateDescription: String = ""
    @State private var estimatedHoursString: String = ""
    @State private var isSaving: Bool = false
    @State private var errorMessage: String? = nil
    @State private var showDeleteConfirmation: Bool = false

    @FocusState private var titleFocused: Bool

    private var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isEditing: Bool {
        if case .edit = mode { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        titleField
                        descriptionField
                        estimatedHoursField
                        if isEditing { deleteSection }
                        if let errorMessage {
                            Text(errorMessage)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.errorText)
                        }
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
                .dismissKeyboardOnTap()
            }
            .navigationTitle(mode.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().tint(OPSStyle.Colors.primaryAccent)
                        } else {
                            Text("SAVE")
                                .font(OPSStyle.Typography.buttonLabel)
                                .foregroundColor(isValid
                                                 ? OPSStyle.Colors.primaryAccent
                                                 : OPSStyle.Colors.tertiaryText)
                        }
                    }
                    .disabled(!isValid || isSaving)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            hydrate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                titleFocused = true
            }
        }
        .alert(
            "Delete this sub-task?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                Task { await performDelete() }
            }
        } message: {
            Text("This sub-task will no longer be proposed when new estimates approve.")
        }
    }

    // MARK: - Fields

    private var titleField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("TITLE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("e.g. Footings, Framing, Vinyl Membrane", text: $title)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .focused($titleFocused)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var descriptionField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("INSTRUCTIONS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("Optional notes for the crew", text: $templateDescription, axis: .vertical)
                .lineLimit(2...5)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var estimatedHoursField: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("ESTIMATED HOURS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            TextField("Optional", text: $estimatedHoursString)
                .keyboardType(.decimalPad)
                .font(OPSStyle.Typography.body)
                .monospacedDigit()
                .foregroundColor(OPSStyle.Colors.primaryText)
                .padding(OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
    }

    private var deleteSection: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showDeleteConfirmation = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "trash")
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                Text("DELETE SUB-TASK")
                    .font(OPSStyle.Typography.bodyBold)
                    .tracking(1.2)
            }
            .foregroundColor(OPSStyle.Colors.errorStatus)
            .frame(maxWidth: .infinity)
            .frame(height: OPSStyle.Layout.touchTargetStandard)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.top, OPSStyle.Layout.spacing3)
    }

    // MARK: - Hydration

    private func hydrate() {
        if case .edit(let template, _) = mode {
            title = template.title
            templateDescription = template.templateDescription ?? ""
            if let hrs = template.estimatedHours {
                estimatedHoursString = formatHours(hrs)
            }
        }
    }

    private func formatHours(_ value: Double) -> String {
        if value == 0 { return "" }
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 2
        return f.string(from: NSNumber(value: value)) ?? String(value)
    }

    // MARK: - Save / Delete

    @MainActor
    private func save() async {
        guard isValid, !isSaving else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = templateDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedHoursString = estimatedHoursString.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsedHours: Double? = trimmedHoursString.isEmpty ? nil : Double(trimmedHoursString)

        switch mode {
        case .create(let taskTypeId, let companyId, let onSave):
            let repo = TaskTemplateRepository(companyId: companyId)
            let dto = CreateTaskTemplateDTO(
                id: UUID().uuidString,
                companyId: companyId,
                taskTypeId: taskTypeId,
                taskTypeRef: taskTypeId,
                title: trimmedTitle,
                description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                estimatedHours: parsedHours,
                displayOrder: nextDisplayOrder(taskTypeId: taskTypeId),
                defaultTeamMemberIds: nil
            )
            do {
                let created = try await repo.create(dto)
                let model = created.toModel()
                modelContext.insert(model)
                try? modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.subCreated)
                onSave(model)
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = error.localizedDescription
            }

        case .edit(let template, let onSave):
            let repo = TaskTemplateRepository(companyId: template.companyId)
            var fields = UpdateTaskTemplateDTO()
            if trimmedTitle != template.title { fields.title = trimmedTitle }
            let newDescription = trimmedDescription.isEmpty ? nil : trimmedDescription
            if newDescription != template.templateDescription { fields.description = newDescription }
            if parsedHours != template.estimatedHours { fields.estimatedHours = parsedHours }
            do {
                let updated = try await repo.update(template.id, fields: fields)
                template.title = updated.title
                template.templateDescription = updated.description
                template.estimatedHours = updated.estimatedHours
                template.updatedAt = updated.updatedAt.flatMap { SupabaseDate.parse($0) }
                try? modelContext.save()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                ToastCenter.shared.present(Feedback.Task.subUpdated)
                onSave()
                dismiss()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                errorMessage = error.localizedDescription
            }
        }
    }

    @MainActor
    private func performDelete() async {
        guard case .edit(let template, let onSave) = mode else { return }
        isSaving = true
        defer { isSaving = false }
        errorMessage = nil

        let repo = TaskTemplateRepository(companyId: template.companyId)
        do {
            try await repo.softDelete(template.id)
            template.deletedAt = Date()
            try? modelContext.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(Feedback.Task.subDeleted)
            onSave()
            dismiss()
        } catch {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            errorMessage = error.localizedDescription
        }
    }

    /// Returns the next display_order value for a new sub-task. Walks the
    /// existing templates in the local store rather than re-fetching so the
    /// new row lands at the bottom of the visible list without a network
    /// round-trip.
    private func nextDisplayOrder(taskTypeId: String) -> Int {
        let descriptor = FetchDescriptor<TaskTemplate>(
            predicate: #Predicate<TaskTemplate> { template in
                template.taskTypeId == taskTypeId && template.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.displayOrder, order: .reverse)]
        )
        if let highest = try? modelContext.fetch(descriptor).first {
            return highest.displayOrder + 1
        }
        return 0
    }
}
