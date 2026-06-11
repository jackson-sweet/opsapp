//
//  ExpenseCategorySettingsView.swift
//  OPS
//
//  Manage expense categories — add, reorder, toggle active state.
//

import SwiftUI

struct ExpenseCategorySettingsView: View {
    @ObservedObject var viewModel: ExpenseViewModel
    @EnvironmentObject private var dataController: DataController
    @State private var showAddCategory = false
    @State private var newCategoryName = ""
    @State private var newCategoryIcon = "tag.fill"
    @State private var isCreating = false

    private let iconOptions: [String] = [
        "tag.fill", "car.fill", "fork.knife", "house.fill", "wrench.fill",
        "shippingbox.fill", "phone.fill", "laptopcomputer", "airplane",
        "fuelpump.fill", "creditcard.fill", "cart.fill", "bolt.fill",
        "wifi", "printer.fill", "person.fill", "building.fill"
    ]

    var body: some View {
        ZStack(alignment: .bottom) {
            OPSStyle.Colors.background.ignoresSafeArea()

            if viewModel.isLoading && viewModel.categories.isEmpty {
                VStack {
                    Spacer()
                    TacticalLoadingBarAnimated()
                    Spacer()
                }
            } else {
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        sectionHeader("CATEGORIES")
                            .padding(.top, OPSStyle.Layout.spacing3)

                        categoriesList
                    }
                    .padding(.bottom, 80)
                }
            }

            addCategoryButton
        }
        .navigationTitle("EXPENSE CATEGORIES")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAddCategory) {
            addCategorySheet
        }
        .task {
            if let companyId = dataController.currentUser?.companyId, !companyId.isEmpty {
                viewModel.setup(companyId: companyId)
                await viewModel.loadCategories()
            }
        }
        .errorToast($viewModel.error, label: Feedback.Err.categoryUpdateFailed)
    }

    // MARK: - Categories List

    private var categoriesList: some View {
        VStack(spacing: 0) {
            ForEach(viewModel.categories) { category in
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    // Drag handle
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)

                    // Icon
                    if let icon = category.icon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: OPSStyle.Layout.IconSize.lg)
                    } else {
                        Image(systemName: "tag.fill")
                            .font(.system(size: OPSStyle.Layout.IconSize.md))
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .frame(width: OPSStyle.Layout.IconSize.lg)
                    }

                    // Name
                    VStack(alignment: .leading, spacing: 2) {
                        Text(category.name)
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(
                                (category.isActive ?? true)
                                ? OPSStyle.Colors.primaryText
                                : OPSStyle.Colors.tertiaryText
                            )
                        if category.isDefault ?? false {
                            Text("DEFAULT")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }

                    Spacer()

                    // Active toggle (default categories can be toggled but not deleted)
                    Toggle("", isOn: Binding(
                        get: { category.isActive ?? true },
                        set: { newValue in
                            Task {
                                await viewModel.toggleCategory(category.id, isActive: newValue)
                            }
                        }
                    ))
                    .labelsHidden()
                    .tint(OPSStyle.Colors.text)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

                if category.id != viewModel.categories.last?.id {
                    Divider().background(OPSStyle.Colors.cardBorder)
                }
            }
        }
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }

    // MARK: - Add Category Button

    private var addCategoryButton: some View {
        Button {
            showAddCategory = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: OPSStyle.Layout.IconSize.lg, weight: .medium))
                .foregroundColor(OPSStyle.Colors.primaryText)
                .frame(width: OPSStyle.Layout.touchTargetLarge, height: OPSStyle.Layout.touchTargetLarge)
                .background(OPSStyle.Colors.primaryAccent)
                .clipShape(Circle())
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .accessibilityLabel("Add Category")
    }

    // MARK: - Add Category Sheet

    private var addCategorySheet: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                OPSStyle.Colors.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing3) {
                        sectionHeader("CATEGORY DETAILS")
                            .padding(.top, OPSStyle.Layout.spacing3)

                        // Name + icon fields
                        VStack(spacing: 0) {
                            HStack {
                                Text("NAME")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(width: 100, alignment: .leading)
                                TextField("Category name", text: $newCategoryName)
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .multilineTextAlignment(.trailing)
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)

                            Divider().background(OPSStyle.Colors.cardBorder)

                            HStack {
                                Text("ICON")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .frame(width: 100, alignment: .leading)
                                Spacer()
                                Image(systemName: newCategoryIcon)
                                    .font(.system(size: OPSStyle.Layout.IconSize.md))
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }
                            .padding(.horizontal, OPSStyle.Layout.spacing3)
                            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
                        }
                        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                        )
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                        // Icon picker grid
                        sectionHeader("CHOOSE ICON")

                        LazyVGrid(
                            columns: Array(repeating: GridItem(.flexible(), spacing: OPSStyle.Layout.spacing2), count: 6),
                            spacing: OPSStyle.Layout.spacing2
                        ) {
                            ForEach(iconOptions, id: \.self) { icon in
                                Button {
                                    newCategoryIcon = icon
                                } label: {
                                    Image(systemName: icon)
                                        .font(.system(size: OPSStyle.Layout.IconSize.md))
                                        .foregroundColor(
                                            newCategoryIcon == icon
                                            ? OPSStyle.Colors.primaryText
                                            : OPSStyle.Colors.secondaryText
                                        )
                                        .frame(width: OPSStyle.Layout.touchTargetMin, height: OPSStyle.Layout.touchTargetMin)
                                        .background(
                                            newCategoryIcon == icon
                                            ? OPSStyle.Colors.primaryAccent.opacity(0.2)
                                            : OPSStyle.Colors.cardBackgroundDark.opacity(0.6)
                                        )
                                        .cornerRadius(OPSStyle.Layout.cardCornerRadius)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                                                .stroke(
                                                    newCategoryIcon == icon
                                                    ? OPSStyle.Colors.primaryAccent
                                                    : OPSStyle.Colors.cardBorder,
                                                    lineWidth: OPSStyle.Layout.Border.standard
                                                )
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                    }
                    .padding(.bottom, 100)
                }

                // Footer
                HStack(spacing: OPSStyle.Layout.spacing3) {
                    if isCreating {
                        ProgressView()
                            .tint(OPSStyle.Colors.primaryAccent)
                            .frame(maxWidth: .infinity)
                    } else {
                        Button("CREATE CATEGORY") {
                            guard !newCategoryName.isEmpty else { return }
                            isCreating = true
                            Task {
                                defer { isCreating = false }
                                let companyId = dataController.currentUser?.companyId ?? ""
                                await viewModel.createCategory(
                                    companyId: companyId,
                                    name: newCategoryName,
                                    icon: newCategoryIcon
                                )
                                if viewModel.error == nil {
                                    newCategoryName = ""
                                    newCategoryIcon = "tag.fill"
                                    showAddCategory = false
                                }
                            }
                        }
                        .opsPrimaryButtonStyle()
                        .disabled(newCategoryName.isEmpty)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.vertical, OPSStyle.Layout.spacing2)
                .background(OPSStyle.Colors.background)
            }
            .navigationTitle("ADD CATEGORY")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CANCEL") { showAddCategory = false }
                        .font(OPSStyle.Typography.captionBold)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
        }
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Spacer()
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
    }
}
