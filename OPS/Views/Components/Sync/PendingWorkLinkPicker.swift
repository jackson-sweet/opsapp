//
//  PendingWorkLinkPicker.swift
//  OPS
//
//  SYNC RECOVERY · T6 — the half-sheet that re-homes an orphaned deck design
//  onto a lead or a job (spec §4 "Link picker"). Pure: results come from an
//  injected async search provider so the view is snapshot-testable and the screen
//  wrapper owns the real SwiftData queries. Selection hands a target back; the
//  wrapper enqueues the offline-safe link op.
//

import SwiftUI

/// Which surface the operator is linking the design to. A client is a route to
/// its lead, never a separate target here (spec §4).
enum PendingWorkLinkScope: Hashable {
    case leads
    case projects
}

/// One selectable link destination, flattened for the pure picker.
struct PendingWorkLinkTarget: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String?
    let scope: PendingWorkLinkScope
}

struct PendingWorkLinkPicker: View {
    /// Real queries injected by the wrapper: `(query, scope) → targets`.
    let searchProvider: (String, PendingWorkLinkScope) async -> [PendingWorkLinkTarget]
    let onSelect: (PendingWorkLinkTarget) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scope: PendingWorkLinkScope = .leads
    @State private var searchText: String = ""
    @State private var results: [PendingWorkLinkTarget] = []
    @State private var isLoading = false
    @State private var reloadTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle

            Text(SyncStatusCopy.PendingWork.linkPickerTitle)
                .font(OPSStyle.Typography.section)
                .textCase(.uppercase)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3_5)

            searchField
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.top, OPSStyle.Layout.spacing3)

            SegmentedControl(
                selection: $scope,
                options: [(PendingWorkLinkScope.leads, "Leads"), (PendingWorkLinkScope.projects, "Jobs")]
            )
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2_5)

            resultsList
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .preferredColorScheme(.dark)
        .onAppear { reload() }
        .onChange(of: scope) { _, _ in reload() }
        .onChange(of: searchText) { _, _ in reload() }
    }

    // MARK: - Handle

    private var handle: some View {
        Capsule()
            .fill(OPSStyle.Colors.text.opacity(0.30))
            .frame(width: 36, height: 5)
            .frame(maxWidth: .infinity)
            .padding(.top, OPSStyle.Layout.spacing2)
    }

    // MARK: - Search field (48pt · MOBILE §9)

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.text3)

            TextField("Search", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.text3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: OPSStyle.Layout.inputHeight)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    // MARK: - Results

    private var resultsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if isLoading && results.isEmpty {
                    ProgressView()
                        .tint(OPSStyle.Colors.text3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, OPSStyle.Layout.spacing5)
                } else if results.isEmpty {
                    emptyState
                } else {
                    ForEach(results) { target in
                        targetRow(target)
                        Divider()
                            .background(OPSStyle.Colors.lineSoft)
                            .padding(.leading, OPSStyle.Layout.spacing3_5)
                    }
                }
            }
            .padding(.top, OPSStyle.Layout.spacing2_5)
        }
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("—")
                .font(OPSStyle.Typography.title)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(searchText.isEmpty ? "// NOTHING TO LINK" : "// NO MATCHES")
                .font(OPSStyle.Typography.metadata)
                .tracking(0.8)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing5)
    }

    private func targetRow(_ target: PendingWorkLinkTarget) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(target)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.surfaceInput)
                        .frame(width: 40, height: 40)
                    Text(String(target.name.prefix(1)).uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    if let subtitle = target.subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(OPSStyle.Typography.metadata)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                Text(target.scope == .leads ? "LEAD" : "JOB")
                    .font(OPSStyle.Typography.nanoLabel)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .fill(OPSStyle.Colors.surfaceInput)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                            .stroke(OPSStyle.Colors.line, lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Data

    private func reload() {
        reloadTask?.cancel()
        let query = searchText
        let currentScope = scope
        reloadTask = Task { @MainActor in
            isLoading = true
            // Light debounce so a fast typist doesn't fire a query per keystroke.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if Task.isCancelled { return }
            let fetched = await searchProvider(query, currentScope)
            if Task.isCancelled { return }
            results = fetched
            isLoading = false
        }
    }
}
