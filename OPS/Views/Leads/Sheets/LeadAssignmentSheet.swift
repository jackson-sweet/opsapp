//
//  LeadAssignmentSheet.swift
//  OPS
//
//  Server-guarded lead assignee picker. The list is intentionally sourced only
//  from `list_opportunity_assignment_candidates`.
//

import SwiftUI

struct LeadAssignmentSheet: View {
    @ObservedObject var viewModel: LeadAssignmentViewModel

    let isOnline: Bool
    var onMutation: (LeadAssignmentMutationOutcome) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var pendingTarget: String?

    private var filteredCandidates: [OpportunityAssignmentCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return viewModel.candidates }
        return viewModel.candidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                if viewModel.isLoading {
                    loadingState
                } else {
                    assignmentContent
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(viewModel.isSaving)
        .task {
            await viewModel.loadCandidates(isOnline: isOnline)
        }
        .opsSheet()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                SheetTitleLabel(title: "ASSIGN LEAD", size: .half)
                SheetCloseButton { dismiss() }
                    .disabled(viewModel.isSaving)
            }

            HStack(spacing: 0) {
                Text("// ")
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("SELECT RESPONSIBLE TEAM MEMBER")
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.metadata)
            .textCase(.uppercase)
        }
    }

    @ViewBuilder
    private var assignmentContent: some View {
        if let errorMessage = viewModel.errorMessage {
            errorState(errorMessage)
        } else if viewModel.candidates.isEmpty && !viewModel.canUnassign {
            emptyState
        } else {
            searchField

            ScrollView {
                candidateList
            }
            .scrollIndicators(.hidden)
        }
    }

    private var loadingState: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            ProgressView()
                .tint(OPSStyle.Colors.text2)
            Text("LOADING TEAM")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetLarge,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }

    private func errorState(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            Text(message)
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.roseTextM)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Assignment error. \(message)")

            SheetCTAButton(
                label: "RETRY",
                icon: OPSStyle.Icons.arrowClockwise,
                variant: .secondary,
                action: {
                    Task {
                        await viewModel.loadCandidates(isOnline: isOnline)
                    }
                }
            )
            .disabled(viewModel.isLoading || viewModel.isSaving)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: OPSStyle.Layout.touchTargetLarge,
            alignment: .leading
        )
    }

    private var emptyState: some View {
        Text("NO ELIGIBLE TEAM MEMBERS")
            .font(OPSStyle.Typography.category)
            .foregroundColor(OPSStyle.Colors.text2)
            .frame(
                maxWidth: .infinity,
                minHeight: OPSStyle.Layout.touchTargetLarge,
                alignment: .leading
            )
    }

    private var searchField: some View {
        HStack(spacing: OPSStyle.Layout.spacing2) {
            Image(systemName: OPSStyle.Icons.search)
                .font(.system(size: OPSStyle.Layout.IconSize.sm))
                .foregroundColor(OPSStyle.Colors.text3)

            TextField("SEARCH TEAM", text: $searchText)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: OPSStyle.Icons.close)
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.text2)
                        .frame(
                            width: OPSStyle.Layout.touchTargetMin,
                            height: OPSStyle.Layout.touchTargetMin
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, OPSStyle.Layout.spacing3)
        .padding(.trailing, OPSStyle.Layout.spacing1)
        .frame(height: OPSStyle.Layout.inputHeight)
        .background(OPSStyle.Colors.surfaceInput)
        .clipShape(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.buttonRadius,
                style: .continuous
            )
            .strokeBorder(
                OPSStyle.Colors.line,
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
    }

    @ViewBuilder
    private var candidateList: some View {
        if filteredCandidates.isEmpty && !searchText.isEmpty {
            Text("NO MATCHES")
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(
                    maxWidth: .infinity,
                    minHeight: OPSStyle.Layout.touchTargetLarge,
                    alignment: .leading
                )
        } else {
            VStack(spacing: 0) {
                if viewModel.canUnassign {
                    assignmentRow(
                        candidate: nil,
                        showDivider: !filteredCandidates.isEmpty
                    )
                }

                ForEach(Array(filteredCandidates.enumerated()), id: \.element.id) { index, candidate in
                    assignmentRow(
                        candidate: candidate,
                        showDivider: index < filteredCandidates.count - 1
                    )
                }
            }
            .nestedCard()
        }
    }

    private func assignmentRow(
        candidate: OpportunityAssignmentCandidate?,
        showDivider: Bool
    ) -> some View {
        let targetId = candidate?.id
        let isCurrent = normalized(targetId) == normalized(viewModel.opportunity.assignedTo)
        let displayName = candidate.map { candidateDisplayName($0) } ?? "UNASSIGNED"

        return VStack(spacing: 0) {
            Button {
                pendingTarget = targetId
                Task {
                    let outcome = await viewModel.changeAssignment(
                        to: targetId,
                        isOnline: isOnline
                    )
                    pendingTarget = nil
                    onMutation(outcome)
                    if outcome == .unchanged {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    if let candidate {
                        UserAvatar(
                            firstName: candidate.firstName ?? "",
                            lastName: candidate.lastName ?? "",
                            imageURL: candidate.profileImageURL,
                            size: OPSStyle.Layout.touchTargetMin,
                            backgroundColor: candidate.userColor.flatMap { Color(hex: $0) }
                                ?? OPSStyle.Colors.text3
                        )
                    } else {
                        Image(systemName: OPSStyle.Icons.personCircle)
                            .font(.system(size: OPSStyle.Layout.IconSize.lg))
                            .foregroundColor(OPSStyle.Colors.text3)
                            .frame(
                                width: OPSStyle.Layout.touchTargetMin,
                                height: OPSStyle.Layout.touchTargetMin
                            )
                    }

                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                        Text(displayName)
                            .font(OPSStyle.Typography.bodyEmphasis)
                            .foregroundColor(OPSStyle.Colors.text)
                            .lineLimit(1)

                        if isCurrent {
                            Text("CURRENT")
                                .font(OPSStyle.Typography.metadata)
                                .foregroundColor(OPSStyle.Colors.text3)
                        }
                    }

                    Spacer(minLength: OPSStyle.Layout.spacing2)

                    if viewModel.isSaving && normalized(pendingTarget) == normalized(targetId) {
                        ProgressView()
                            .tint(OPSStyle.Colors.text2)
                    } else if isCurrent {
                        Image(systemName: OPSStyle.Icons.checkmark)
                            .font(.system(size: OPSStyle.Layout.IconSize.sm))
                            .foregroundColor(OPSStyle.Colors.text2)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isSaving)
            .accessibilityLabel(
                candidate == nil
                    ? "Unassign lead"
                    : "Assign lead to \(displayName)"
            )
            .accessibilityValue(isCurrent ? "Current assignee" : "")

            if showDivider {
                Divider()
                    .overlay(OPSStyle.Colors.lineSoft)
                    .padding(.leading, OPSStyle.Layout.touchTargetMin + OPSStyle.Layout.spacing3 + OPSStyle.Layout.spacing2_5)
            }
        }
    }

    private func candidateDisplayName(
        _ candidate: OpportunityAssignmentCandidate
    ) -> String {
        candidate.displayName.isEmpty ? "TEAM MEMBER" : candidate.displayName.uppercased()
    }

    private func normalized(_ value: String?) -> String? {
        value?.lowercased()
    }
}
