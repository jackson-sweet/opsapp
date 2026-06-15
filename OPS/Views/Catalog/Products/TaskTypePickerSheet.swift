//
//  TaskTypePickerSheet.swift
//  OPS
//
//  Shared task-type picker. Surfaces when a product needs a task type
//  attached (Service-category products) and when a TaskType wants to
//  reassign one of its linked products. Lists active company task types
//  with their color swatch + display name and pins a "+ NEW TASK TYPE"
//  affordance at the top so the operator can scaffold a new type without
//  losing the parent context.
//

import SwiftUI
import SwiftData

struct TaskTypePickerSheet: View {
    /// Currently selected task type id, if any. Used to render the checkmark
    /// and to filter out "no change" taps.
    let selectedTaskTypeId: String?

    /// Filter the list to types whose display contains this string (lowercased).
    /// Empty = no filter.
    @State private var searchQuery: String = ""

    /// Called with the picked TaskType (existing or just-created). Sheet
    /// dismisses immediately after firing so the caller's onChange / state
    /// update isn't racing the dismiss animation.
    let onSelect: (TaskType) -> Void

    @EnvironmentObject private var dataController: DataController
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var taskTypes: [TaskType] = []
    @State private var showingCreateSheet: Bool = false

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var filteredTaskTypes: [TaskType] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return taskTypes }
        let lower = trimmed.lowercased()
        return taskTypes.filter { $0.display.lowercased().contains(lower) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 0) {
                    searchField
                    ScrollView {
                        VStack(spacing: OPSStyle.Layout.spacing2) {
                            newTaskTypeRow

                            if filteredTaskTypes.isEmpty {
                                emptyState
                            } else {
                                ForEach(filteredTaskTypes, id: \.id) { taskType in
                                    taskTypeRow(taskType)
                                }
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                    }
                }
            }
            .navigationTitle("PICK TASK TYPE")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear(perform: loadTaskTypes)
        .sheet(isPresented: $showingCreateSheet) {
            TaskTypeSheet(mode: .create(onSave: { newType in
                // The TaskTypeSheet inserts the model on save and triggers
                // sync. We just need to forward the freshly-created row up
                // and close the picker so the operator lands back on the
                // product form with their new type selected.
                onSelect(newType)
                dismiss()
            }))
            .environmentObject(dataController)
        }
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            TextField("Search", text: $searchQuery)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .overlay(
            Rectangle()
                .fill(OPSStyle.Colors.separator)
                .frame(height: 1),
            alignment: .bottom
        )
    }

    // MARK: - Rows

    private var newTaskTypeRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showingCreateSheet = true
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Text("// + NEW TASK TYPE")
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                Spacer()
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.primaryAccent.opacity(0.4), lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Create new task type")
    }

    private func taskTypeRow(_ taskType: TaskType) -> some View {
        let isSelected = (taskType.id == selectedTaskTypeId)
        let color = Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(taskType)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                Circle()
                    .fill(color)
                    .frame(width: 18, height: 18)
                    .overlay(
                        Circle()
                            .stroke(color.opacity(0.6), lineWidth: 1)
                    )
                Text(taskType.display.uppercased())
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
            .padding(OPSStyle.Layout.spacing2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(
                        isSelected ? OPSStyle.Colors.text : OPSStyle.Colors.cardBorder,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel("Pick task type \(taskType.display)")
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("// NO TASK TYPES MATCH")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            if !searchQuery.isEmpty {
                Text("Try a different search or scaffold a new type above.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            } else {
                Text("No active task types in your company yet. Scaffold one above to get started.")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(OPSStyle.Layout.spacing4)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Load

    private func loadTaskTypes() {
        guard !companyId.isEmpty else { return }
        let descriptor = FetchDescriptor<TaskType>(
            predicate: #Predicate<TaskType> { taskType in
                taskType.companyId == companyId && taskType.deletedAt == nil
            },
            sortBy: [SortDescriptor(\.displayOrder), SortDescriptor(\.display)]
        )
        if let local = try? modelContext.fetch(descriptor) {
            taskTypes = local
        }
    }
}
