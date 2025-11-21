//
//  DeletionSheet.swift
//  OPS
//
//  Generic deletion sheet that handles cascading deletions with reassignment
//

import SwiftUI
import SwiftData

/// Reassignment mode for deletion sheets
enum ReassignmentMode: String, CaseIterable {
    case bulk = "Bulk Reassign"
    case individual = "Individual"
}

/// Generic deletion sheet supporting cascading deletions with reassignment options
///
/// Usage Example (Client Deletion):
/// ```swift
/// DeletionSheet(
///     item: client,
///     itemType: "Client",
///     childItems: client.projects,
///     childType: "Project",
///     availableReassignments: availableClients,
///     getItemDisplay: { client in
///         AnyView(
///             Text(client.name)
///                 .font(OPSStyle.Typography.title)
///                 .foregroundColor(OPSStyle.Colors.primaryText)
///         )
///     },
///     filterAvailableItems: { clients in
///         clients.filter { $0.id != client.id && !$0.id.contains("-") }
///     },
///     getChildId: { $0.id },
///     getReassignmentId: { $0.id },
///     renderReassignmentRow: { child, selectedId, markedForDeletion, available, onToggleDelete in
///         AnyView(ProjectReassignmentRow(...))
///     },
///     renderSearchField: { binding, available in
///         AnyView(ClientSearchField(...))
///     },
///     onDelete: { client, reassignments, deletions in
///         // Custom deletion logic
///     }
/// )
/// ```
struct DeletionSheet<Item, ChildItem, ReassignmentItem>: View {
    // MARK: - Configuration

    let item: Item
    let itemType: String  // "Client", "Task Type", etc.
    let childItems: [ChildItem]
    let childType: String  // "Project", "Task", etc.
    let availableReassignments: [ReassignmentItem]

    // MARK: - Display Closures

    /// Render the item's display (can be simple text or complex layout with icon/color)
    let getItemDisplay: (Item) -> AnyView

    /// Filter available reassignment items (e.g., exclude current item, filter UUIDs)
    let filterAvailableItems: ([ReassignmentItem]) -> [ReassignmentItem]

    /// Get child item ID for tracking
    let getChildId: (ChildItem) -> String

    /// Get reassignment item ID
    let getReassignmentId: (ReassignmentItem) -> String

    /// Render a single child reassignment row
    let renderReassignmentRow: (
        _ child: ChildItem,
        _ selectedId: Binding<String?>,
        _ markedForDeletion: Bool,
        _ availableItems: [ReassignmentItem],
        _ onToggleDelete: @escaping () -> Void
    ) -> AnyView

    /// Render the search field for selecting reassignment target
    let renderSearchField: (
        _ selectedId: Binding<String?>,
        _ availableItems: [ReassignmentItem]
    ) -> AnyView

    // MARK: - Deletion Handler

    /// Called when user confirms deletion
    /// - Parameters:
    ///   - item: The item being deleted
    ///   - reassignments: Map of child IDs to reassignment target IDs
    ///   - deletions: Set of child IDs marked for deletion
    let onDelete: (Item, [String: String], Set<String>) async throws -> Void

    // MARK: - Optional Callbacks

    var onDeletionStarted: (() -> Void)? = nil

    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    // MARK: - State

    @State private var reassignmentMode: ReassignmentMode = .bulk
    @State private var reassignments: [String: String] = [:]
    @State private var itemsToDelete: Set<String> = []
    @State private var bulkSelectedItem: String?
    @State private var bulkDeleteAll = false
    @State private var isDeleting = false
    @State private var showingError = false
    @State private var errorMessage = ""

    // MARK: - Computed Properties

    private var filteredAvailableItems: [ReassignmentItem] {
        filterAvailableItems(availableReassignments)
    }

    private var canDelete: Bool {
        if childItems.isEmpty {
            return true
        }

        switch reassignmentMode {
        case .bulk:
            return bulkSelectedItem != nil || bulkDeleteAll
        case .individual:
            return childItems.allSatisfy { child in
                let childId = getChildId(child)
                return reassignments[childId] != nil || itemsToDelete.contains(childId)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Header section
                    VStack(alignment: .leading, spacing: 4) {
                        Text("DELETE \(itemType.uppercased())")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        getItemDisplay(item)

                        Text("\(childItems.count) \(childType.lowercased())\(childItems.count == 1 ? "" : "s")")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 16)

                    if !childItems.isEmpty {
                        // Segmented control for mode selection
                        SegmentedControl(
                            selection: $reassignmentMode,
                            options: [
                                (.bulk, "Bulk Reassign"),
                                (.individual, "Individual")
                            ]
                        )
                        .padding(.horizontal, 20)
                        .padding(.bottom, 16)

                        // Content based on mode
                        ScrollView {
                            VStack(spacing: 16) {
                                if reassignmentMode == .bulk {
                                    bulkReassignmentView
                                } else {
                                    individualReassignmentView
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 100)
                        }
                    } else {
                        Spacer()
                    }
                }

                // Delete Button - Floating at bottom
                Button(action: performDeletion) {
                    HStack {
                        if isDeleting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.errorStatus))
                                .scaleEffect(0.8)
                        } else {
                            Text("Delete \(itemType)")
                                .font(OPSStyle.Typography.body)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(.ultraThinMaterial)
                    .foregroundColor(
                        canDelete
                            ? OPSStyle.Colors.errorStatus
                            : OPSStyle.Colors.tertiaryText
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(
                                canDelete
                                    ? OPSStyle.Colors.errorStatus
                                    : OPSStyle.Colors.tertiaryText,
                                lineWidth: 1.5
                            )
                    )
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(!canDelete || isDeleting)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Error", isPresented: $showingError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    // MARK: - Bulk Reassignment View

    private var bulkReassignmentView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !bulkDeleteAll {
                Text("Reassign all \(childItems.count) \(childType.lowercased())\(childItems.count == 1 ? "" : "s") to:")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.secondaryText)

                renderSearchField($bulkSelectedItem, filteredAvailableItems)
            } else {
                Text("All \(childItems.count) \(childType.lowercased())\(childItems.count == 1 ? "" : "s") will be deleted")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .italic()
            }

            // Delete All button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    bulkDeleteAll.toggle()
                    if bulkDeleteAll {
                        bulkSelectedItem = nil
                    }
                }
            }) {
                HStack {
                    Image(systemName: bulkDeleteAll ? OPSStyle.Icons.close : OPSStyle.Icons.delete)
                        .font(OPSStyle.Typography.body)
                    Text(bulkDeleteAll ? "Don't Delete All \(childType)s" : "Delete All \(childType)s")
                        .font(OPSStyle.Typography.bodyBold)
                }
                .foregroundColor(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(bulkDeleteAll ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.errorStatus, lineWidth: 1.5)
                )
                .cornerRadius(OPSStyle.Layout.cornerRadius)
            }
        }
    }

    // MARK: - Individual Reassignment View

    private var individualReassignmentView: some View {
        VStack(spacing: 12) {
            ForEach(Array(childItems.enumerated()), id: \.offset) { index, child in
                let childId = getChildId(child)
                renderReassignmentRow(
                    child,
                    binding(for: childId),
                    itemsToDelete.contains(childId),
                    filteredAvailableItems,
                    { toggleItemDeletion(childId) }
                )
            }
        }
    }

    // MARK: - Helper Methods

    private func binding(for childId: String) -> Binding<String?> {
        Binding(
            get: { reassignments[childId] },
            set: { reassignments[childId] = $0 }
        )
    }

    private func toggleItemDeletion(_ childId: String) {
        if itemsToDelete.contains(childId) {
            itemsToDelete.remove(childId)
        } else {
            itemsToDelete.insert(childId)
            reassignments.removeValue(forKey: childId)
        }
    }

    private func performDeletion() {
        // Call optional callback
        onDeletionStarted?()

        // If no callback, dismiss immediately
        if onDeletionStarted == nil {
            // Only set isDeleting if we're staying on screen
            isDeleting = true
        } else {
            // If callback exists, it might dismiss, so dismiss now
            dismiss()
        }

        Task {
            do {
                try await onDelete(item, reassignments, itemsToDelete)

                // Only dismiss if we didn't already (callback case)
                if onDeletionStarted == nil {
                    await MainActor.run {
                        dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isDeleting = false
                    errorMessage = "Failed to delete \(itemType.lowercased()): \(error.localizedDescription)"
                    showingError = true
                }
            }
        }
    }
}
