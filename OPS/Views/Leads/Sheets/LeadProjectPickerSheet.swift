//
//  LeadProjectPickerSheet.swift
//  OPS
//
//  LINK PROJECT — associate an existing project with a lead (or unlink it).
//  Presented from the lead document's PROJECT row. Local-store search over
//  the company's synced projects; selection returns the id and the caller
//  owns the network write. UNLINK appears only when a link exists — the rare
//  verb earns a row only when it means something.
//

import SwiftUI
import SwiftData

struct LeadProjectPickerSheet: View {
    /// The lead's currently linked project id, if any.
    let currentProjectId: String?
    /// Called with the chosen project id, or nil for UNLINK. The sheet
    /// dismisses itself; the caller performs the write + haptic.
    let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var searchText = ""
    @State private var projects: [Project] = []

    var body: some View {
        NavigationStack {
            ZStack {
                OPSStyle.Colors.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    searchField
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.top, OPSStyle.Layout.spacing3)
                        .padding(.bottom, OPSStyle.Layout.spacing2_5)

                    ScrollView {
                        LazyVStack(spacing: 0) {
                            if currentProjectId != nil, searchText.isEmpty {
                                unlinkRow
                                rowDivider
                            }
                            ForEach(filtered) { project in
                                projectRow(project)
                                if project.id != filtered.last?.id {
                                    rowDivider
                                }
                            }
                            if filtered.isEmpty {
                                Text(searchText.isEmpty ? "No projects yet" : "No matches")
                                    .font(OPSStyle.Typography.caption)
                                    .foregroundColor(OPSStyle.Colors.textMute)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, OPSStyle.Layout.spacing5)
                            }
                        }
                        .commandCard()
                        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                        .padding(.bottom, OPSStyle.Layout.spacing5)
                    }
                }
            }
            .navigationTitle("LINK PROJECT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(OPSStyle.Typography.bodyEmphasis)
                        .foregroundColor(OPSStyle.Colors.text)
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear(perform: loadProjects)
    }

    // MARK: - Rows

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(OPSStyle.Colors.text3)
            TextField("Search projects", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .frame(height: 44)
        .background(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous).fill(OPSStyle.Colors.surfaceInput))
        .overlay(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous).strokeBorder(OPSStyle.Colors.line, lineWidth: 1))
    }

    private var unlinkRow: some View {
        Button {
            onSelect(nil)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "link.badge.plus")
                    .symbolRenderingMode(.monochrome)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("UNLINK PROJECT")
                    .font(.custom("JetBrainsMono-Medium", size: 10))
                    .tracking(0.9)
                    .foregroundColor(OPSStyle.Colors.textMute)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Unlink the current project")
    }

    private func projectRow(_ project: Project) -> some View {
        Button {
            onSelect(project.id)
            dismiss()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.title)
                        .font(.custom("Mohave-Medium", size: 15))
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if let address = project.address, !address.isEmpty {
                        Text(address)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                Spacer(minLength: 0)
                if project.id == currentProjectId {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Link project \(project.title)")
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.lineSoft)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    // MARK: - Data

    private var filtered: [Project] {
        let query = searchText.trimmingCharacters(in: .whitespaces).lowercased()
        guard !query.isEmpty else { return projects }
        return projects.filter {
            $0.title.lowercased().contains(query)
            || ($0.address ?? "").lowercased().contains(query)
        }
    }

    private func loadProjects() {
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.deletedAt == nil }
        )
        descriptor.sortBy = [SortDescriptor(\.createdAt, order: .reverse)]
        projects = (try? modelContext.fetch(descriptor)) ?? []
    }
}
