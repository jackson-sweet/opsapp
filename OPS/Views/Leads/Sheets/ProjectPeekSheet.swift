//
//  ProjectPeekSheet.swift
//  OPS
//
//  A read-only look at a project, layered OVER the convert sheet.
//
//  Bug ced5b3cb-A: the convert sheet's project chips used to DISMISS the sheet
//  and navigate away. An operator who tapped one to check whether the address
//  matched lost their typed value, notes, and selection with no warning and no
//  way back. Inspecting is not navigating.
//
//  The peek answers exactly one question — "is this the same job?" — and then
//  gets out of the way. CLOSE returns to the conversion with everything
//  intact. OPEN PROJECT exists for the genuinely blocked case (every
//  same-address match already belongs to another lead, so there is nothing to
//  convert here until someone resolves that), and it says plainly that it
//  leaves the conversion behind.
//

import SwiftUI
import SwiftData

struct ProjectPeekSheet: View {
    let projectId: String
    let fallbackTitle: String
    let fallbackAddress: String?
    let linkNote: String?
    let companyId: String
    let onOpenProject: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var title: String = ""
    @State private var address: String?
    @State private var status: Status?
    @State private var createdAt: Date?
    @State private var isHydrating = true

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    SheetTitleLabel(title: "PROJECT", size: .half)
                    SheetCloseButton { dismiss() }
                }
                .padding(.leading, OPSStyle.Layout.spacing3_5)
                .padding(.trailing, 6)
                .padding(.top, OPSStyle.Layout.spacing2)
                .padding(.bottom, OPSStyle.Layout.spacing1)

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
                        identityCard
                        if let linkNote {
                            noteLine(linkNote)
                        }
                    }
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.top, OPSStyle.Layout.spacing1)
                }
                .scrollIndicators(.hidden)

                footer
            }
        }
        .preferredColorScheme(.dark)
        .task { await hydrate() }
    }

    // MARK: - Content

    private var identityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("EXISTING PROJECT")
                    .foregroundColor(OPSStyle.Colors.tanTextM)
                if let createdAt {
                    Text("  ·  ")
                        .foregroundColor(OPSStyle.Colors.textMute)
                    Text(relativeText(for: createdAt).uppercased())
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .kerning(1.6)
            .textCase(.uppercase)

            Text(displayTitle)
                .font(OPSStyle.Typography.bodyBold)
                .foregroundColor(OPSStyle.Colors.text)
                .lineLimit(2)

            HStack(spacing: OPSStyle.Layout.spacing2) {
                if let status {
                    StatusBadge(
                        status: status.displayName.uppercased(),
                        color: status.color,
                        size: .small
                    )
                } else if isHydrating {
                    Text("CHECKING")
                        .font(OPSStyle.Typography.miniLabel)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
                if let resolvedAddress, !resolvedAddress.isEmpty {
                    Text(resolvedAddress)
                        .font(OPSStyle.Typography.miniLabel)
                        .kerning(1.0)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(2)
                        .textCase(.uppercase)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .commandCard()
    }

    private func noteLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("// ")
                .foregroundColor(OPSStyle.Colors.textMute)
            Text(text)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .font(OPSStyle.Typography.miniLabel)
        .kerning(0.4)
        .lineSpacing(2)
        .padding(.vertical, OPSStyle.Layout.spacing2_5)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                .strokeBorder(OPSStyle.Colors.line, lineWidth: 1)
        )
    }

    private var footer: some View {
        VStack(spacing: OPSStyle.Layout.spacing1) {
            SheetFooterButtonRow {
                // "OPEN" not "OPEN PROJECT" — the longer label wraps to two
                // lines in the secondary slot. The caption below carries the
                // consequence, and the card above says what is being opened.
                SheetCTAButton(
                    label: "OPEN",
                    variant: .secondary,
                    action: {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onOpenProject(projectId)
                    }
                )
                .accessibilityLabel("Open this project and leave the conversion")
            } primary: {
                SheetCTAButton(
                    label: "CLOSE",
                    variant: .primary,
                    action: { dismiss() }
                )
            }

            Text("Opening the project leaves this conversion.")
                .font(OPSStyle.Typography.miniLabel)
                .kerning(0.4)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, 28)
    }

    // MARK: - Hydration

    private var displayTitle: String {
        let resolved = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !resolved.isEmpty { return resolved }
        let fallback = fallbackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Untitled project" : fallback
    }

    private var resolvedAddress: String? { address ?? fallbackAddress }

    /// Network first (canonical), then local SwiftData, then the preflight
    /// values we already hold — the peek must render offline.
    private func hydrate() async {
        defer { isHydrating = false }

        if let dto = try? await ProjectRepository(companyId: companyId).fetchOne(projectId) {
            let model = dto.toModel()
            title = model.title
            address = model.address
            status = model.status
            createdAt = model.createdAt
            return
        }

        let localId = projectId
        var descriptor = FetchDescriptor<Project>(
            predicate: #Predicate<Project> { $0.id == localId }
        )
        descriptor.fetchLimit = 1
        if let local = (try? modelContext.fetch(descriptor))?.first {
            title = local.title
            address = local.address
            status = local.status
            createdAt = local.createdAt
        }
    }

    private func relativeText(for date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
