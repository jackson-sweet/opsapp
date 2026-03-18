//
//  InventoryWizardCoordinator.swift
//  OPS
//
//  Manages the inventory setup wizard flow state.
//  Coordinates between wizard steps and the underlying data operations.
//

import SwiftUI
import SwiftData
import Combine

@MainActor
class InventoryWizardCoordinator: ObservableObject {

    // MARK: - Step Enum

    enum Step: Equatable {
        case chooseMethod
        case addingManually
        case importing
        case setThresholds
        case takeSnapshot
        case complete
    }

    // MARK: - Published Properties

    @Published var currentStep: Step = .chooseMethod
    @Published var showMethodChoice: Bool = true
    @Published var showThresholdSheet: Bool = false
    @Published var showSnapshotSheet: Bool = false

    // MARK: - Dependencies

    weak var dataController: DataController?
    weak var wizardStateManager: WizardStateManager?

    // MARK: - Init

    init(dataController: DataController? = nil, wizardStateManager: WizardStateManager? = nil) {
        self.dataController = dataController
        self.wizardStateManager = wizardStateManager
    }

    // MARK: - Navigation

    /// User chose "Add Items Manually"
    func selectManual() {
        currentStep = .addingManually
        showMethodChoice = false
        // Advance wizard to the add_items step
        wizardStateManager?.completeCurrentStep()
    }

    /// User chose "Import from Spreadsheet"
    func selectImport() {
        currentStep = .importing
        showMethodChoice = false
        // Advance wizard to the add_items step
        wizardStateManager?.completeCurrentStep()
    }

    /// Go back to the method choice screen
    func goBack() {
        currentStep = .chooseMethod
        showMethodChoice = true
    }

    /// Proceed from adding items to threshold setup
    func proceedToThresholds() {
        currentStep = .setThresholds
        showThresholdSheet = true
        // Advance wizard to set_thresholds step
        wizardStateManager?.completeCurrentStep()
    }

    /// Proceed from thresholds to snapshot
    func proceedToSnapshot() {
        currentStep = .takeSnapshot
        showThresholdSheet = false
        showSnapshotSheet = true
        // Advance wizard to take_snapshot step
        wizardStateManager?.completeCurrentStep()
    }

    /// Skip thresholds and go to snapshot
    func skipThresholds() {
        currentStep = .takeSnapshot
        showThresholdSheet = false
        showSnapshotSheet = true
        // Skip the threshold step in wizard
        wizardStateManager?.skipCurrentStep()
    }

    /// Finish the wizard
    func finish() {
        currentStep = .complete
        showSnapshotSheet = false
        // Complete the final wizard step
        wizardStateManager?.completeCurrentStep()
    }

    /// Skip the entire wizard
    func skipWizard() {
        currentStep = .complete
        showMethodChoice = false
        showThresholdSheet = false
        showSnapshotSheet = false
        wizardStateManager?.exitWizard()
    }
}
