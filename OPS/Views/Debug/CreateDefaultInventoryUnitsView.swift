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
    @State private var createdUnits: [InventoryUnitDTO] = []
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

            VStack(spacing: 24) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 48))
                        .foregroundColor(Color.teal)

                    Text("Create Default Inventory Units")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("Company: \(companyName)")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                .padding(.top, 20)

                // Existing units section
                if !companyUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("EXISTING UNITS (\(companyUnits.count))")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.secondaryText)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(companyUnits) { unit in
                                    UnitChip(display: unit.display, isDefault: unit.isDefault)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Created units section
                if !createdUnits.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("NEWLY CREATED UNITS (\(createdUnits.count))")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.successStatus)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(createdUnits, id: \.id) { unit in
                                    UnitChip(display: unit.display, isDefault: unit.isDefault ?? true)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)
                }

                Spacer()

                // Info box
                VStack(alignment: .leading, spacing: 8) {
                    Text("This will create the following default units:")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)

                    Text("ea (each), box, ft (feet), gal (gallon), lb (pound), roll, bag, pallet, sheet, bundle")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    Text("The Bubble workflow will handle creating these units in the database.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .padding(.top, 4)
                }
                .padding()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
                .padding(.horizontal, 16)

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
                    .padding(.vertical, 16)
                    .background(hasCreated ? OPSStyle.Colors.successStatus : Color.teal)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(isLoading || hasCreated || companyId.isEmpty)
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
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

                let units = try await dataController.apiService.createDefaultInventoryUnits(companyId: companyId)

                await MainActor.run {
                    createdUnits = units
                    hasCreated = true
                    isLoading = false

                    // Also save the units locally
                    for dto in units {
                        let unit = dto.toModel()
                        modelContext.insert(unit)
                    }
                    try? modelContext.save()

                    print("[DEV_TOOLS] Successfully created \(units.count) default inventory units")
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
        HStack(spacing: 4) {
            Text(display)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.primaryText)

            if isDefault {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Color.teal)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    NavigationStack {
        CreateDefaultInventoryUnitsView()
            .environmentObject(DataController())
    }
}
