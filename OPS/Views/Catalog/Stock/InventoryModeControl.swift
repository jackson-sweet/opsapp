//
//  InventoryModeControl.swift
//  OPS
//
//  Shared on/off control for company inventory tracking. Rendered in two
//  surfaces (Catalog Setup review step and Company Settings) per Phase 6
//  Closed PM Decision 4. Visibility/enablement is gated to `catalog.manage`
//  using the app's granular permission check — never by role.
//
//  Turning tracking OFF releases open projected demand server-side and writes a
//  release snapshot, so the control always confirms before turning off and
//  explains that history is preserved.
//

import SwiftUI

/// Drives an `InventoryModeControl`. Owns the loaded mode, the in-flight RPC
/// state, and the confirmation gate. `@MainActor` because it publishes UI state.
@MainActor
final class InventoryModeViewModel: ObservableObject {
    enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    @Published private(set) var mode: InventoryMode = .off
    @Published private(set) var loadState: LoadState = .idle
    @Published private(set) var isSaving: Bool = false
    /// Surfaced when an RPC write fails so the surface can show a tactical error.
    @Published private(set) var actionError: String?
    /// True while the off-confirmation dialog should be presented.
    @Published var showingDisableConfirmation: Bool = false

    private let client: InventoryModeClient?

    init(client: InventoryModeClient?) {
        self.client = client
    }

    var isTracked: Bool { mode == .tracked }

    /// The toggle is interactive only when a client exists and no write is
    /// in-flight. Permission gating is handled by the surface (visibility).
    var isInteractive: Bool {
        client != nil && !isSaving && loadState == .loaded
    }

    func load() async {
        guard let client else {
            loadState = .failed("No company")
            return
        }
        loadState = .loading
        actionError = nil
        do {
            mode = try await client.fetchInventoryMode()
            loadState = .loaded
        } catch {
            loadState = .failed(error.localizedDescription)
        }
    }

    /// Called when the user flips the toggle. Turning on applies immediately;
    /// turning off must route through the confirmation gate first.
    func handleToggle(requestedOn: Bool) {
        guard isInteractive else { return }
        if requestedOn {
            guard !isTracked else { return }
            beginCommit(.tracked, toast: Feedback.Catalog.inventoryModeUpdated)
        } else {
            guard isTracked else { return }
            showingDisableConfirmation = true
        }
    }

    /// User confirmed turning tracking off.
    func confirmDisable() {
        showingDisableConfirmation = false
        beginCommit(.off, toast: Feedback.Catalog.inventoryTrackingOff)
    }

    /// Flips `isSaving` synchronously so the toggle shows progress immediately
    /// (and so callers can reliably observe the in-flight state) before the
    /// async write is scheduled.
    private func beginCommit(_ target: InventoryMode, toast: Toast) {
        isSaving = true
        actionError = nil
        Task { await commit(target, toast: toast) }
    }

    /// User backed out of turning tracking off — leave it on.
    func cancelDisable() {
        showingDisableConfirmation = false
    }

    /// Called by the `.errorToast` binding setter when the toast clears the error.
    func clearActionError(_ newValue: String?) {
        if newValue == nil { actionError = nil }
    }

    private func commit(_ target: InventoryMode, toast: Toast) async {
        guard let client else {
            isSaving = false
            return
        }
        do {
            let response = try await client.setInventoryMode(target)
            mode = response.mode
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            ToastCenter.shared.present(toast)
        } catch {
            actionError = error.localizedDescription
            // Re-read so the UI never drifts from server truth after a failure.
            if let fresh = try? await client.fetchInventoryMode() {
                mode = fresh
            }
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        isSaving = false
    }
}

/// The visual control. Self-contained card matching the catalog setup/settings
/// surfaces. Caller is responsible for `catalog.manage` visibility gating; this
/// view assumes it is only shown to a manager.
struct InventoryModeControl: View {
    @StateObject private var viewModel: InventoryModeViewModel

    init(client: InventoryModeClient?) {
        _viewModel = StateObject(wrappedValue: InventoryModeViewModel(client: client))
    }

    /// Binding bridge so `.errorToast` can read and clear `viewModel.actionError`.
    private var actionErrorBinding: Binding<String?> {
        Binding(
            get: { viewModel.actionError },
            set: { viewModel.clearActionError($0) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            header
            statusLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opsCardStyle()
        .task { await viewModel.load() }
        .errorToast(actionErrorBinding, label: Feedback.Err.operationFailed)
        .confirmationDialog(
            "Turn off inventory tracking",
            isPresented: $viewModel.showingDisableConfirmation,
            titleVisibility: .visible
        ) {
            Button("Turn off tracking", role: .destructive) {
                viewModel.confirmDisable()
            }
            Button("Keep tracking", role: .cancel) {
                viewModel.cancelDisable()
            }
        } message: {
            Text("Open material demand is released. Your stock history, snapshots, and past deductions stay on record. Turn it back on anytime.")
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("INVENTORY TRACKING")
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Spacer()
            toggle
        }
    }

    @ViewBuilder
    private var toggle: some View {
        if viewModel.isSaving || viewModel.loadState == .loading {
            ProgressView()
                .tint(OPSStyle.Colors.loadingSpinner)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, minHeight: OPSStyle.Layout.touchTargetMin)
        } else {
            Toggle(
                "",
                isOn: Binding(
                    get: { viewModel.isTracked },
                    set: { viewModel.handleToggle(requestedOn: $0) }
                )
            )
            .labelsHidden()
            .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
            .disabled(!viewModel.isInteractive)
            .accessibilityLabel("Inventory tracking")
            .accessibilityValue(viewModel.isTracked ? "On" : "Off")
            .accessibilityHint("Tracks stock against booked jobs. Turning off releases open material demand and keeps history.")
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch viewModel.loadState {
        case .idle, .loading:
            Text("SYS :: LOADING")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
        case .failed:
            // A read failure must not permanently lock the control: the status
            // line carries a RETRY that re-runs the fetch. We never enable blind
            // toggling while the mode is unknown — recovery is an explicit retry.
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text("SYS :: MODE UNAVAILABLE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                Spacer(minLength: OPSStyle.Layout.spacing2)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    Task { await viewModel.load() }
                } label: {
                    Text("RETRY")
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(minWidth: OPSStyle.Layout.touchTargetMin,
                               minHeight: OPSStyle.Layout.touchTargetMin)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Retry")
                .accessibilityHint("Re-checks inventory tracking status.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .loaded:
            Text(viewModel.isTracked
                 ? "On. Accepted estimates project material demand. Completed tasks deduct stock."
                 : "Off. No material demand, warnings, or stock deduction. History stays intact.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
