//
//  ProjectLinkPickerSheet.swift
//  OPS
//
//  The searchable half of ONE question: "which project is this?"
//
//  `ConvertToProjectSheet` shows the top-ranked candidates inline, which
//  answers the question outright almost every time — the project a won lead
//  becomes is nearly always at the same address or under the same client, and
//  the server ranks those first. This sheet is the rest of that SAME list, for
//  the case the shortlist cannot serve: a lead whose address is junk
//  ("Gordon Head", "500 is close") normalizes to empty server-side, so nothing
//  ranks by address and the right project can be anywhere in a company that
//  carries hundreds of them.
//
//  It is deliberately NOT a second question with a second rule. Same source
//  (`get_manual_project_link_candidates`), same server order, same one rule:
//  every row here is selectable. Selecting returns the choice to the convert
//  sheet — it never commits. The footer CTA over there still owns the
//  transaction.
//

import SwiftUI

struct ProjectLinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let candidates: [ConvertToProjectSheet.ProjectLinkCandidate]
    let selectedProjectId: String?
    let onSelect: (String) -> Void

    @State private var searchText: String = ""

    /// Filtered, never re-sorted — the server's ranking is the ranking.
    private var filtered: [ConvertToProjectSheet.ProjectLinkCandidate] {
        candidates.filter { $0.matches(searchText) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    searchField

                    if filtered.isEmpty {
                        emptyState
                    } else {
                        // `.listRow` is the opaque fill for long scrolling
                        // lists — a real company carries hundreds of projects.
                        projectList
                            .glassSurface(.listRow)
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                }
                .padding(.bottom, OPSStyle.Layout.spacing3_5)
            }
            .scrollIndicators(.hidden)
            .background(OPSStyle.Colors.background)
            .standardSheetToolbar(
                title: "Link Project",
                actionText: "",
                isActionEnabled: false,
                onCancel: { dismiss() },
                onAction: {}
            )
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Search

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.magnifyingglass)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.text3)

            TextField("Search projects", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: OPSStyle.Icons.xmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.text3)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, OPSStyle.Layout.spacing2_5)
        .padding(.trailing, searchText.isEmpty ? OPSStyle.Layout.spacing2_5 : 0)
        .frame(minHeight: 48)
        .background(OPSStyle.Colors.surfaceInput)
        .cornerRadius(OPSStyle.Layout.buttonRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.top, OPSStyle.Layout.spacing3)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    private var emptyState: some View {
        VStack(spacing: OPSStyle.Layout.spacing2) {
            Text("No projects match")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text2)

            Text("Close this and create a new project instead.")
                .font(OPSStyle.Typography.miniLabel)
                .kerning(0.4)
                .foregroundColor(OPSStyle.Colors.text3)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, OPSStyle.Layout.spacing3_5)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - List

    private var projectList: some View {
        VStack(spacing: 0) {
            ForEach(filtered) { candidate in
                projectRow(candidate)
                if candidate.id != filtered.last?.id {
                    Rectangle()
                        .fill(OPSStyle.Colors.line)
                        .frame(height: 1)
                        .padding(.leading, OPSStyle.Layout.spacing3)
                }
            }
        }
    }

    private func projectRow(
        _ candidate: ConvertToProjectSheet.ProjectLinkCandidate
    ) -> some View {
        let isSelected = candidate.id == selectedProjectId

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onSelect(candidate.id)
            dismiss()
        } label: {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2_5) {
                Circle()
                    .fill(candidate.statusColor)
                    .frame(width: 5, height: 5)
                    .padding(.top, 7)

                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.displayTitle)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    if let address = candidate.address, !address.isEmpty {
                        Text(address)
                            .font(OPSStyle.Typography.miniLabel)
                            .kerning(1.0)
                            .foregroundColor(OPSStyle.Colors.text3)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textCase(.uppercase)
                    }

                    if let evidence = candidate.evidenceLabel {
                        Text(evidence)
                            .font(OPSStyle.Typography.miniLabel)
                            .kerning(1.0)
                            .foregroundColor(
                                candidate.sameAddress
                                    ? OPSStyle.Colors.tanTextM
                                    : OPSStyle.Colors.text3
                            )
                            .textCase(.uppercase)
                    }
                }

                Spacer(minLength: OPSStyle.Layout.spacing2)

                if isSelected {
                    Image(systemName: OPSStyle.Icons.checkmarkCircleFill)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                        .foregroundColor(OPSStyle.Colors.oliveTextM)
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .accessibilityLabel(
            isSelected
                ? "Selected project \(candidate.displayTitle)"
                : "Link lead to project \(candidate.displayTitle)"
        )
    }
}
