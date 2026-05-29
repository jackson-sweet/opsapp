//
//  InventoryTrackingSettingsView.swift
//  OPS
//
//  Company Settings surface for the Phase 6 inventory operating mode
//  (Closed PM Decision 4). Hosts the shared InventoryModeControl. Reached only
//  from the OPERATIONS section, which gates the entry to catalog.manage.
//

import SwiftUI

struct InventoryTrackingSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @ObservedObject private var permissionStore = PermissionStore.shared

    private var companyId: String {
        dataController.currentUser?.companyId ?? ""
    }

    private var canManage: Bool {
        permissionStore.can("catalog.manage")
    }

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    intro

                    if canManage, !companyId.isEmpty {
                        InventoryModeControl(
                            client: CompanyInventoryModeRepository(companyId: companyId)
                        )
                    } else {
                        lockedState
                    }
                }
                .padding(OPSStyle.Layout.spacing3)
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("DONE") { dismiss() }
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }
        }
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// INVENTORY TRACKING")
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Decide whether OPS tracks stock against your jobs. On: accepted estimates project material demand and completed tasks deduct stock. Off: jobs run without touching inventory.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("ACCESS :: LOCKED")
                .font(OPSStyle.Typography.category)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("Managing inventory tracking needs catalog management access.")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .opsCardStyle()
    }
}
