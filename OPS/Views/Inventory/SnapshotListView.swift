//
//  SnapshotListView.swift
//  OPS
//
//  List view for displaying inventory snapshots
//  Tactical minimalist design
//

import SwiftUI
import SwiftData

struct SnapshotListView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var isLoading = true
    @State private var snapshots: [InventorySnapshotDTO] = []
    @State private var errorMessage: String? = nil
    @State private var selectedSnapshot: InventorySnapshotDTO? = nil

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                        Text("Loading snapshots...")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                } else if snapshots.isEmpty {
                    emptyStateView
                } else {
                    snapshotList
                }
            }
            .standardSheetToolbar(
                title: "Snapshots",
                cancelText: "Done",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: { }
            )
            .onAppear {
                loadSnapshots()
            }
            .sheet(item: $selectedSnapshot) { snapshot in
                SnapshotDetailView(snapshot: snapshot)
                    .environmentObject(dataController)
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Image(systemName: "camera.metering.unknown")
                .font(.system(size: 48))
                .foregroundColor(OPSStyle.Colors.tertiaryText)

            Text("No Snapshots")
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Inventory snapshots will appear here when created automatically or manually.")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing4)

            if let error = errorMessage {
                Text(error)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.top, OPSStyle.Layout.spacing2)
            }

            Button(action: { loadSnapshots() }) {
                HStack(spacing: OPSStyle.Layout.spacing1) {
                    Image(systemName: OPSStyle.Icons.arrowClockwise)
                    Text("Refresh")
                }
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
            .padding(.top, OPSStyle.Layout.spacing2)
        }
    }

    // MARK: - Snapshot List

    private var snapshotList: some View {
        ScrollView {
            LazyVStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(snapshots, id: \.id) { snapshot in
                    snapshotRow(snapshot)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, 100)
        }
        .refreshable {
            loadSnapshots()
        }
    }

    private func snapshotRow(_ snapshot: InventorySnapshotDTO) -> some View {
        Button(action: {
            selectedSnapshot = snapshot
        }) {
            HStack(spacing: OPSStyle.Layout.spacing3) {
                // Icon
                Image(systemName: "camera.fill")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(snapshot.isAutomatic == true ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.primaryAccent)
                    .frame(width: 32)

                // Info
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(formatSnapshotDate(snapshot.createdDate ?? snapshot.createdAt))
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        Text("\(snapshot.itemCount ?? 0) items")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        Text(snapshot.isAutomatic == true ? "Automatic" : "Manual")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OPSStyle.Colors.subtleBackground)
                            .cornerRadius(OPSStyle.Layout.smallCornerRadius)
                    }
                }

                Spacer()

                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    // MARK: - Functions

    private func loadSnapshots() {
        isLoading = true
        errorMessage = nil

        Task {
            do {
                let fetched = try await dataController.apiService.fetchCompanySnapshots(companyId: companyId)
                await MainActor.run {
                    snapshots = fetched
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func formatSnapshotDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Unknown date" }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return displayFormatter.string(from: date)
    }
}

// MARK: - Snapshot Detail View

struct SnapshotDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    let snapshot: InventorySnapshotDTO

    @State private var isLoading = true
    @State private var items: [InventorySnapshotItemDTO] = []
    @State private var errorMessage: String? = nil

    var body: some View {
        NavigationView {
            ZStack {
                OPSStyle.Colors.background
                    .ignoresSafeArea()

                if isLoading {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                        Text("Loading items...")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing4) {
                            // Summary card
                            summaryCard

                            // Items list
                            if !items.isEmpty {
                                itemsList
                            }

                            Spacer()
                                .frame(height: 100)
                        }
                        .padding(.top, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .standardSheetToolbar(
                title: "Snapshot Details",
                cancelText: "Done",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: { }
            )
            .onAppear {
                loadItems()
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("SUMMARY")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                infoRow(label: "Date", value: formatSnapshotDate(snapshot.createdDate ?? snapshot.createdAt))
                infoRow(label: "Type", value: snapshot.isAutomatic == true ? "Automatic" : "Manual")
                infoRow(label: "Items", value: "\(snapshot.itemCount ?? 0)")

                if let notes = snapshot.notes, !notes.isEmpty {
                    infoRow(label: "Notes", value: notes)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
            Text(value)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
        }
    }

    private var itemsList: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            HStack {
                Text("ITEMS")
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                Spacer()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)

            VStack(spacing: 0) {
                ForEach(items, id: \.id) { item in
                    itemRow(item)

                    if item.id != items.last?.id {
                        Divider()
                            .background(OPSStyle.Colors.cardBorder)
                            .padding(.leading, OPSStyle.Layout.spacing3)
                    }
                }
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3)
        }
    }

    private func itemRow(_ item: InventorySnapshotItemDTO) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing3) {
            // Quantity
            VStack(spacing: 2) {
                Text(formatQuantity(item.quantity ?? 0))
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                if let unit = item.unitDisplay, !unit.isEmpty {
                    Text(unit)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .frame(width: 50)

            // Divider
            Rectangle()
                .fill(OPSStyle.Colors.cardBorder)
                .frame(width: 1)
                .padding(.vertical, OPSStyle.Layout.spacing1)

            // Name
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name ?? "Unnamed")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                if let sku = item.sku, !sku.isEmpty {
                    Text(sku)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }

            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func loadItems() {
        isLoading = true

        Task {
            do {
                let fetched = try await dataController.apiService.fetchSnapshotItems(snapshotId: snapshot.id)
                await MainActor.run {
                    items = fetched
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load items: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func formatSnapshotDate(_ dateString: String?) -> String {
        guard let dateString = dateString else { return "Unknown date" }

        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: dateString) else { return dateString }

        let displayFormatter = DateFormatter()
        displayFormatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return displayFormatter.string(from: date)
    }

    private func formatQuantity(_ quantity: Double) -> String {
        if quantity.truncatingRemainder(dividingBy: 1) == 0 {
            return String(Int(quantity))
        } else {
            return String(format: "%.1f", quantity)
        }
    }
}

// Make InventorySnapshotDTO Identifiable for sheet binding
extension InventorySnapshotDTO: Identifiable {}

#Preview {
    SnapshotListView()
        .environmentObject(DataController())
}
