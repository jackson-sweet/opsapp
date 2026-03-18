//
//  InventorySnapshotSetupView.swift
//  OPS
//
//  Educational + action screen for the inventory setup wizard (Step 4).
//  Explains what snapshots are, takes the first snapshot, then lets the
//  user pick an auto-snapshot frequency.
//

import SwiftUI
import SwiftData

struct InventorySnapshotSetupView: View {
    // MARK: - Inputs

    let companyId: String
    let items: [InventoryItem]
    let onComplete: () -> Void

    // MARK: - Environment

    @EnvironmentObject private var dataController: DataController

    // MARK: - State

    @State private var phase: Phase = .initial
    @State private var selectedFrequency: SnapshotFrequency = .monthly
    @State private var isTakingSnapshot = false
    @State private var errorMessage: String?

    // MARK: - Phase

    private enum Phase {
        case initial          // Show explanation + take snapshot button
        case snapshotTaken    // Checkmark animation, then frequency picker
    }

    // MARK: - Frequency options (excluding .off)

    private let frequencyOptions: [SnapshotFrequency] = [.weekly, .monthly, .quarterly]

    // MARK: - Body

    var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                iconSection
                titleSection
                descriptionSection

                if phase == .snapshotTaken {
                    frequencySection
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }

                Spacer()

                bottomSection

                // Error message
                if let errorMessage {
                    Text(errorMessage)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.errorStatus)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .padding(.bottom, OPSStyle.Layout.spacing2)
                }
            }
        }
        .animation(OPSStyle.Animation.standard, value: phase)
    }

    // MARK: - Icon

    private var iconSection: some View {
        Group {
            if phase == .initial {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
            } else {
                // Checkmark after snapshot taken
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56, weight: .light))
                    .foregroundColor(OPSStyle.Colors.successStatus)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                    .transition(.scale.combined(with: .opacity))
            }
        }
    }

    // MARK: - Title

    private var titleSection: some View {
        Text(phase == .initial ? "TAKE YOUR FIRST SNAPSHOT" : "SNAPSHOT TAKEN")
            .font(OPSStyle.Typography.headingBold)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .multilineTextAlignment(.center)
            .padding(.bottom, OPSStyle.Layout.spacing2)
    }

    // MARK: - Description

    private var descriptionSection: some View {
        Text(phase == .initial
            ? "Snapshots record your inventory levels over time. OPS uses them to show consumption trends and predict when you'll run out of materials."
            : "Your inventory levels have been recorded. Set how often OPS should auto-snapshot."
        )
            .font(OPSStyle.Typography.caption)
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .multilineTextAlignment(.center)
            .lineSpacing(3)
            .padding(.horizontal, OPSStyle.Layout.spacing5)
            .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Frequency Picker

    private var frequencySection: some View {
        VStack(spacing: OPSStyle.Layout.spacing3) {
            Text("HOW OFTEN SHOULD OPS AUTO-SNAPSHOT?")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                ForEach(frequencyOptions, id: \.self) { frequency in
                    frequencyPill(frequency)
                }
            }
        }
    }

    private func frequencyPill(_ frequency: SnapshotFrequency) -> some View {
        let isSelected = selectedFrequency == frequency

        return Button {
            TutorialHaptics.lightTap()
            selectedFrequency = frequency
        } label: {
            Text(frequency.displayName.uppercased())
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(isSelected ? OPSStyle.Colors.invertedText : OPSStyle.Colors.secondaryText)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(height: OPSStyle.Layout.touchTargetMin)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .fill(isSelected ? OPSStyle.Colors.primaryAccent : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(
                            isSelected ? Color.clear : OPSStyle.Colors.cardBorder,
                            lineWidth: OPSStyle.Layout.Border.standard
                        )
                )
        }
        .animation(OPSStyle.Animation.fast, value: isSelected)
    }

    // MARK: - Bottom Section

    private var bottomSection: some View {
        VStack(spacing: OPSStyle.Layout.spacing2_5) {
            if phase == .initial {
                // TAKE SNAPSHOT button
                Button {
                    TutorialHaptics.lightTap()
                    takeSnapshot()
                } label: {
                    HStack(spacing: OPSStyle.Layout.spacing2) {
                        if isTakingSnapshot {
                            ProgressView()
                                .tint(OPSStyle.Colors.invertedText)
                                .scaleEffect(0.8)
                        }

                        Text(isTakingSnapshot ? "TAKING SNAPSHOT..." : "TAKE SNAPSHOT")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.invertedText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: OPSStyle.Layout.touchTargetStandard)
                    .background(OPSStyle.Colors.primaryAccent)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .disabled(isTakingSnapshot)
                .disabledButtonStyle(isDisabled: isTakingSnapshot)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            } else {
                // CONTINUE button
                Button {
                    TutorialHaptics.lightTap()
                    saveFrequencyAndComplete()
                } label: {
                    Text("CONTINUE")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.invertedText)
                        .frame(maxWidth: .infinity)
                        .frame(height: OPSStyle.Layout.touchTargetStandard)
                        .background(OPSStyle.Colors.primaryAccent)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
        }
        .padding(.bottom, OPSStyle.Layout.spacing4)
    }

    // MARK: - Actions

    private func takeSnapshot() {
        guard !isTakingSnapshot else { return }
        isTakingSnapshot = true
        errorMessage = nil

        let activeItems = items.filter { $0.deletedAt == nil }

        Task {
            do {
                guard let repo = dataController.inventoryRepository else {
                    throw NSError(domain: "OPS", code: -1, userInfo: [NSLocalizedDescriptionKey: "No inventory repository available"])
                }

                // Build snapshot items from current inventory
                let snapshotItems = activeItems.map { item in
                    CreateInventorySnapshotItemDTO(
                        snapshotId: "", // will be set by repo
                        originalItemId: item.id,
                        name: item.name,
                        quantity: item.quantity,
                        unitDisplay: item.unit?.display,
                        sku: item.sku,
                        tagsString: item.tagNames.joined(separator: ", "),
                        description: item.itemDescription
                    )
                }

                let userId = dataController.currentUser?.id
                _ = try await repo.createFullSnapshot(
                    userId: userId,
                    isAutomatic: false,
                    items: snapshotItems,
                    notes: "First inventory snapshot (setup wizard)"
                )

                // Update last snapshot date in settings
                var settings = SnapshotSettings.load()
                settings.lastSnapshotDate = Date()
                settings.save()

                await MainActor.run {
                    isTakingSnapshot = false
                    TutorialHaptics.success()

                    // Transition to frequency picker after a brief checkmark display
                    withAnimation(OPSStyle.Animation.standard) {
                        phase = .snapshotTaken
                    }
                }
            } catch {
                await MainActor.run {
                    isTakingSnapshot = false
                    errorMessage = "Failed to take snapshot. Please try again."
                    TutorialHaptics.error()
                    print("[SNAPSHOT_SETUP] Error creating snapshot: \(error)")
                }
            }
        }
    }

    private func saveFrequencyAndComplete() {
        // Save frequency to UserDefaults (same key as InventorySettingsView)
        var settings = SnapshotSettings.load()
        settings.frequency = selectedFrequency
        settings.save()

        onComplete()
    }
}
