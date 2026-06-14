//
//  InventoryWizardFlow.swift
//  OPS
//
//  Orchestrates the inventory setup wizard flow.
//  Manages transitions between steps: choose method → add items → set thresholds → take snapshot.
//

import SwiftUI
import SwiftData

struct InventoryWizardFlow: View {
    @ObservedObject var coordinator: InventoryWizardCoordinator
    let onComplete: () -> Void
    let onSkip: () -> Void

    @EnvironmentObject private var dataController: DataController
    @Query private var inventoryItems: [InventoryItem]

    private var activeItems: [InventoryItem] {
        inventoryItems.filter { $0.deletedAt == nil }
    }

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            switch coordinator.currentStep {
            case .chooseMethod:
                InventoryMethodChoiceView(
                    onManual: { coordinator.selectManual() },
                    onImport: { coordinator.selectImport() },
                    onSkip: { dismissWizard() }
                )
                .transition(.opacity)

            case .addingManually:
                manualAddStep
                    .transition(.move(edge: .trailing))

            case .importing:
                importStep
                    .transition(.move(edge: .trailing))

            case .setThresholds:
                InventoryThresholdSetupView(
                    items: activeItems,
                    onApply: { coordinator.proceedToSnapshot() },
                    onSkip: { coordinator.proceedToSnapshot() }
                )
                .environmentObject(dataController)
                .transition(.move(edge: .trailing))

            case .takeSnapshot:
                InventorySnapshotSetupView(
                    companyId: companyId,
                    items: activeItems,
                    onComplete: { finishWizard() }
                )
                .transition(.move(edge: .trailing))

            case .complete:
                EmptyView()
            }
        }
        .animation(OPSStyle.Animation.standard, value: coordinator.currentStep)
    }

    // MARK: - Manual Add Step

    private var manualAddStep: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back and done
                HStack {
                    Button {
                        coordinator.goBack()
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            Text("BACK")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(height: 44)
                    }

                    Spacer()

                    Button {
                        // Done adding — proceed to thresholds if items exist
                        if !activeItems.isEmpty {
                            coordinator.proceedToThresholds()
                        } else {
                            coordinator.goBack()
                        }
                    } label: {
                        Text(activeItems.isEmpty ? "CANCEL" : "DONE ADDING")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(activeItems.isEmpty ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.wizardAccent)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)

                // Instruction
                HStack {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text("ADD YOUR ITEMS")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)

                        Text("\(activeItems.count) item\(activeItems.count == 1 ? "" : "s") added")
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    Spacer()
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.vertical, OPSStyle.Layout.spacing2_5)

                Divider().background(OPSStyle.Colors.cardBorder)

                // Inventory list + add button
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing2_5) {
                        // Existing items
                        ForEach(activeItems) { item in
                            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                        .font(OPSStyle.Typography.body)
                                        .foregroundColor(OPSStyle.Colors.primaryText)
                                    Text(item.quantityDisplay)
                                        .font(OPSStyle.Typography.smallCaption)
                                        .foregroundColor(OPSStyle.Colors.secondaryText)
                                }
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                    .foregroundColor(OPSStyle.Colors.successStatus)
                            }
                            .padding(OPSStyle.Layout.spacing2_5)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }

                        // Add item button
                        Button {
                            showingAddSheet = true
                        } label: {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                Text("ADD ITEM")
                                    .font(OPSStyle.Typography.bodyBold)
                            }
                            .foregroundColor(OPSStyle.Colors.wizardAccent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.cardBackgroundDark)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                            .overlay(
                                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                    .stroke(OPSStyle.Colors.wizardAccent.opacity(0.3), lineWidth: OPSStyle.Layout.Border.standard)
                            )
                        }

                        // Exit option — always available
                        skipSetupButton
                    }
                    .padding(OPSStyle.Layout.spacing3_5)
                }
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            InventoryFormSheet(item: nil)
                .environmentObject(dataController)
        }
    }

    @State private var showingAddSheet = false
    @State private var showingImportSheet = false

    // MARK: - Import Step

    private var importStep: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with back
                HStack {
                    Button {
                        coordinator.goBack()
                    } label: {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                            Text("BACK")
                                .font(OPSStyle.Typography.captionBold)
                        }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .frame(height: 44)
                    }

                    Spacer()

                    if !activeItems.isEmpty {
                        Button {
                            coordinator.proceedToThresholds()
                        } label: {
                            Text("CONTINUE")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.wizardAccent)
                                .frame(height: 44)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)

                // Import prompt — left-aligned, icon inline with title
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    HStack(spacing: OPSStyle.Layout.spacing2_5) {
                        Image(systemName: "square.and.arrow.down")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.wizardAccent)

                        Text("IMPORT FROM SPREADSHEET")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    Text("Upload a CSV or Excel file with your inventory list.")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineSpacing(3)

                    Button {
                        showingImportSheet = true
                    } label: {
                        Text("SELECT FILE")
                            .font(OPSStyle.Typography.button)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OPSStyle.Layout.spacing3)
                            .background(OPSStyle.Colors.primaryText)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                    // Exit option — always available
                    skipSetupButton
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing4)

                Spacer()
            }
        }
        .sheet(isPresented: $showingImportSheet) {
            SpreadsheetImportSheet()
                .environmentObject(dataController)
        }
        .onChange(of: activeItems.count) { oldCount, newCount in
            // After import adds items, auto-advance
            if oldCount == 0 && newCount > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    coordinator.proceedToThresholds()
                }
            }
        }
    }

    // MARK: - Shared Components

    /// Persistent exit button available on every step after method choice
    private var skipSetupButton: some View {
        Button {
            TutorialHaptics.lightTap()
            dismissWizard()
        } label: {
            Text("SKIP SETUP")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .frame(maxWidth: .infinity)
                .frame(height: OPSStyle.Layout.touchTargetMin)
        }
        .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Helpers

    private func dismissWizard() {
        onSkip()
    }

    private func finishWizard() {
        onComplete()
    }
}
