//
//  DependencyPickerSheet.swift
//  OPS
//
//  Picker for selecting a task type as a dependency.
//  Filters out self, existing deps, and cycle-creating options.
//

import SwiftUI
import SwiftData

struct DependencyPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var dataController: DataController

    let currentTaskTypeId: String?
    let existingDependencies: [TaskTypeDependency]
    let companyId: String
    let onSelect: (String) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                let available = availableTaskTypes()
                if available.isEmpty {
                    Text("No available task types")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                } else {
                    VStack(spacing: 0) {
                        ForEach(available) { taskType in
                            Button(action: {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                onSelect(taskType.id)
                                dismiss()
                            }) {
                                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                    TaskBadge(
                                        name: taskType.display,
                                        color: Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent,
                                        size: .large
                                    )

                                    Spacer()

                                    Image(systemName: "plus.circle.fill")
                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                                }
                                .padding(.horizontal, OPSStyle.Layout.spacing3)
                                .padding(.vertical, 10)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())

                            if taskType.id != available.last?.id {
                                Rectangle()
                                    .fill(OPSStyle.Colors.cardBorderSubtle)
                                    .frame(height: 1)
                                    .padding(.leading, OPSStyle.Layout.spacing3)
                            }
                        }
                    }
                    .glassSurface()
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                    .padding(.top, OPSStyle.Layout.spacing3)
                }
            }
            .background(OPSStyle.Colors.background)
            .standardSheetToolbar(
                title: "Add Dependency",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: {}
            )
        }
    }

    private func availableTaskTypes() -> [TaskType] {
        guard let ctx = dataController.modelContext else { return [] }
        let cId = companyId
        let predicate = #Predicate<TaskType> {
            $0.companyId == cId && $0.deletedAt == nil
        }
        let descriptor = FetchDescriptor<TaskType>(predicate: predicate, sortBy: [SortDescriptor(\.displayOrder)])
        let allTypes = (try? ctx.fetch(descriptor)) ?? []

        let existingIds = Set(existingDependencies.map { $0.dependsOnTaskTypeId })

        return allTypes.filter { type in
            if type.id == currentTaskTypeId { return false }
            if existingIds.contains(type.id) { return false }
            if let currentId = currentTaskTypeId {
                let allTypeTuples = allTypes.map { (id: $0.id, dependencies: $0.dependencies) }
                if SchedulingEngine.wouldCreateCycle(taskTypeId: currentId, newDependsOnId: type.id, allTaskTypes: allTypeTuples) {
                    return false
                }
            }
            return true
        }
    }
}
