//
//  CreateDefaultInventoryUnitsView.swift
//  OPS
//
//  Developer tool to create default inventory units for a company
//

import SwiftUI
import SwiftData

struct CreateDefaultInventoryUnitsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var dataController: DataController

    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var createdUnits: [InventoryUnitReadDTO] = []
    @State private var hasCreated = false

    // Get current company info
    private var companyName: String {
        dataController.getCurrentUserCompany()?.name ?? "Unknown Company"
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    // Query existing inventory units
    @Query private var existingUnits: [InventoryUnit]

    private var companyUnits: [InventoryUnit] {
        existingUnits.filter { $0.companyId == companyId && $0.deletedAt == nil }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: OPSStyle.Layout.spacing4) {
                // Header
                VStack(spacing: OPSStyle.Layout.spacing2) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color.teal)

                    Text("Create Default Inventory Units")
                        .font(OPSStyle.Typography.screenTitle(for: "Create Default Inventory Units"))
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text)

                    Text("Company: \(companyName)")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.top, OPSStyle.Layout.spacing3_5)

                // Existing units section
                if !companyUnits.isEmpty {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        Text("EXISTING UNITS (\(companyUnits.count))")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(companyUnits) { unit in
                                    UnitChip(display: unit.display, isDefault: unit.isDefault)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }

                // Created units section
                if !createdUnits.isEmpty {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        Text("NEWLY CREATED UNITS (\(createdUnits.count))")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.successStatus)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                ForEach(createdUnits, id: \.id) { unit in
                                    UnitChip(display: unit.display, isDefault: unit.isDefault)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                }

                Spacer()

                // Info box
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                    Text("This will create the following default units:")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("ea (each), box, ft (feet), gal (gallon), lb (pound), roll, bag, pallet, sheet, bundle")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text("Units will be created directly in Supabase.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, OPSStyle.Layout.spacing1)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
                .padding(.horizontal, OPSStyle.Layout.spacing3)

                // Action button
                Button(action: createDefaultUnits) {
                    HStack {
                        if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        } else {
                            Image(systemName: hasCreated ? "checkmark.circle.fill" : "plus.circle.fill")
                            Text(hasCreated ? "Created Successfully" : "Create Default Units")
                        }
                    }
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, OPSStyle.Layout.spacing3)
                    .background(hasCreated ? OPSStyle.Colors.successStatus : Color.teal)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(isLoading || hasCreated || companyId.isEmpty)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
        }
        .navigationTitle("Inventory Units")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") {
                    dismiss()
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
            }
        }
    }

    private func createDefaultUnits() {
        guard !companyId.isEmpty else {
            errorMessage = "No company ID found"
            return
        }

        isLoading = true
        errorMessage = nil

        Task {
            do {
                print("[DEV_TOOLS] Creating default inventory units for company: \(companyId)")

                guard let repo = dataController.inventoryRepository else {
                    throw NSError(domain: "OPS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No inventory repository available"])
                }

                let defaultUnits: [(display: String, sortOrder: Int)] = [
                    ("ea", 1), ("box", 2), ("ft", 3), ("gal", 4), ("lb", 5),
                    ("roll", 6), ("bag", 7), ("pallet", 8), ("sheet", 9), ("bundle", 10)
                ]

                var created: [InventoryUnitReadDTO] = []
                for unit in defaultUnits {
                    let dto = CreateInventoryUnitDTO(
                        companyId: companyId,
                        display: unit.display,
                        isDefault: true,
                        sortOrder: unit.sortOrder
                    )
                    let result = try await repo.createUnit(dto)
                    created.append(result)

                    // Save locally
                    await MainActor.run {
                        let localUnit = InventoryUnit(
                            id: result.id,
                            display: result.display,
                            companyId: result.companyId,
                            isDefault: result.isDefault,
                            sortOrder: result.sortOrder
                        )
                        localUnit.needsSync = false
                        localUnit.lastSyncedAt = Date()
                        modelContext.insert(localUnit)
                    }
                }

                await MainActor.run {
                    createdUnits = created
                    hasCreated = true
                    isLoading = false
                    try? modelContext.save()
                    print("[DEV_TOOLS] Successfully created \(created.count) default inventory units")
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to create units: \(error.localizedDescription)"
                    isLoading = false
                    print("[DEV_TOOLS] Failed to create inventory units: \(error)")
                }
            }
        }
    }
}

// MARK: - Unit Chip Component

struct UnitChip: View {
    let display: String
    let isDefault: Bool

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Text(display)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if isDefault {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.teal)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing2_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }
}

#Preview {
    NavigationStack {
        CreateDefaultInventoryUnitsView()
            .environmentObject(DataController())
    }
}
