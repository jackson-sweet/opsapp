//
//  OpportunityPickerView.swift
//  OPS
//
//  Searchable opportunity list with inline "+ New Lead" creation.
//  Used inside LogActivitySheet for selecting which lead to log against.
//

import SwiftUI

struct OpportunityPickerView: View {
    @ObservedObject var viewModel: LogActivityViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Search bar
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .font(.system(size: 16))

                TextField("Search leads...", text: $viewModel.opportunitySearchText)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .autocorrectionDisabled()

                if !viewModel.opportunitySearchText.isEmpty {
                    Button {
                        viewModel.opportunitySearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2_5)

            Divider()
                .padding(.top, OPSStyle.Layout.spacing2_5)

            // Opportunity list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(viewModel.filteredOpportunities) { opp in
                        opportunityRow(opp)
                        Divider()
                            .padding(.leading, OPSStyle.Layout.spacing3_5)
                    }

                    // + New Lead row
                    newLeadRow()
                }
            }
        }
        .background(OPSStyle.Colors.background)
    }

    // MARK: - Opportunity Row

    @ViewBuilder
    private func opportunityRow(_ opp: Opportunity) -> some View {
        Button {
            viewModel.selectedOpportunity = opp
            viewModel.isCreatingNewLead = false
            viewModel.showOpportunityPicker = false
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                // Contact initial circle
                ZStack {
                    Circle()
                        .fill(OPSStyle.Colors.cardBackgroundDark)
                        .frame(width: 40, height: 40)
                    Text(String(opp.contactName.prefix(1)).uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(opp.contactName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    if let desc = opp.descriptionText, !desc.isEmpty {
                        Text(desc)
                            .font(OPSStyle.Typography.caption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Stage badge
                Text(opp.stage.displayName)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(OPSStyle.Colors.cardBackgroundDark)
                    .cornerRadius(OPSStyle.Layout.chipRadius)

                // Checkmark if selected
                if viewModel.selectedOpportunity?.id == opp.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(OPSStyle.Colors.successStatus)
                        .font(.system(size: 20))
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - New Lead Row

    @ViewBuilder
    private func newLeadRow() -> some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(OPSStyle.Animation.panel) {
                    viewModel.isCreatingNewLead.toggle()
                    if viewModel.isCreatingNewLead {
                        viewModel.selectedOpportunity = nil
                    }
                }
            } label: {
                HStack(spacing: OPSStyle.Layout.spacing2_5) {
                    ZStack {
                        Circle()
                            .fill(OPSStyle.Colors.successStatus.opacity(0.2))
                            .frame(width: 40, height: 40)
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(OPSStyle.Colors.successStatus)
                    }

                    Text("New Lead")
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.successStatus)

                    Spacer()

                    Image(systemName: viewModel.isCreatingNewLead ? "chevron.up" : "chevron.down")
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Inline create form
            if viewModel.isCreatingNewLead {
                VStack(spacing: OPSStyle.Layout.spacing2_5) {
                    inlineField(label: "Name", text: $viewModel.newLeadName, placeholder: "Contact name *")
                    inlineField(label: "Phone", text: $viewModel.newLeadPhone, placeholder: "Phone (optional)")
                    inlineField(label: "Email", text: $viewModel.newLeadEmail, placeholder: "Email (optional)")
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    @ViewBuilder
    private func inlineField(label: String, text: Binding<String>, placeholder: String) -> some View {
        TextField(placeholder, text: text)
            .font(OPSStyle.Typography.body)
            .foregroundColor(OPSStyle.Colors.primaryText)
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.vertical, OPSStyle.Layout.spacing2_5)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}
