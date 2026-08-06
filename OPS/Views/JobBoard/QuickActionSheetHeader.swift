//
//  QuickActionSheetHeader.swift
//  OPS
//
//  Reusable header component for quick action sheets
//

import SwiftUI

struct QuickActionSheetHeader: View {
    let title: String
    let canSave: Bool
    let isSaving: Bool
    let onDismiss: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            OPSScreenHeader(
                title,
                leading: {
                    OPSHeaderCloseButton(action: onDismiss)
                },
                trailing: {
                    Button(action: onSave) {
                        Group {
                            if isSaving {
                                ProgressView()
                                    .progressViewStyle(
                                        CircularProgressViewStyle(
                                            tint: OPSStyle.Colors.primaryText
                                        )
                                    )
                            } else {
                                Text("SAVE")
                                    .font(OPSStyle.Typography.buttonLabel)
                                    .foregroundColor(
                                        canSave
                                            ? OPSStyle.Colors.primaryAccent
                                            : OPSStyle.Colors.tertiaryText
                                    )
                            }
                        }
                        .frame(
                            minWidth: OPSStyle.Layout.touchTargetMin,
                            minHeight: OPSStyle.Layout.touchTargetMin
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSave || isSaving)
                    .accessibilityLabel(isSaving ? "Saving" : "Save")
                }
            )
            .background(OPSStyle.Colors.background)

            Divider()
                .background(OPSStyle.Colors.separator)
        }
    }
}

struct QuickActionContextHeader: View {
    let clientName: String?
    let projectAddress: String?
    let projectName: String
    let taskName: String?
    let accentColor: Color?

    @EnvironmentObject private var dataController: DataController

    private var formattedAddress: String? {
        guard let address = projectAddress else { return nil }

        let components = address.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        if components.count >= 3 {
            return components.dropLast(2).joined(separator: ", ")
        }

        return address
    }

    private var defaultColor: Color {
        if let companyId = dataController.currentUser?.companyId,
           let company = dataController.getCompany(id: companyId),
           let color = Color(hex: company.defaultProjectColor) {
            return color
        }
        return OPSStyle.Colors.primaryAccent
    }

    var body: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                Rectangle()
                    .fill(accentColor ?? defaultColor)
                    .frame(width: 3, height: 60)

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    if let taskName = taskName {
                        Text("TASK: \(taskName.uppercased())")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    } else {
                        Text("PROJECT: \(projectName.uppercased())")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }

                    if let clientName = clientName {
                        Text(clientName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if taskName != nil {
                        Text(projectName.uppercased())
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }

                    if let address = formattedAddress {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Image(systemName: OPSStyle.Icons.locationFill)
                                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)

                            Text(address)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    }
                }

                Spacer()
            }
            .padding(OPSStyle.Layout.spacing3)
            .glassSurface()
        }
    }
}
