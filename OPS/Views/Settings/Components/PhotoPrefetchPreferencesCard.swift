//
//  PhotoPrefetchPreferencesCard.swift
//  OPS
//
//  Two-toggle card wrapping PhotoPrefetchService preferences:
//   1. Auto-download new photos (master on/off)
//   2. Allow on cellular (default off — WiFi only)
//
//  Used in both PhotoStorageManagementView and DataStorageSettingsView.
//

import SwiftUI

struct PhotoPrefetchPreferencesCard: View {
    @ObservedObject private var prefetchService = PhotoPrefetchService.shared

    var body: some View {
        VStack(spacing: 0) {
            Toggle(isOn: Binding(
                get: { prefetchService.isEnabled },
                set: { prefetchService.isEnabled = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Auto-download new photos")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("After each sync, download photos from your most recent projects")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .tint(OPSStyle.Colors.text)
            .padding()

            OPSStyle.Colors.separator.frame(height: 1)

            Toggle(isOn: Binding(
                get: { prefetchService.allowCellular },
                set: { prefetchService.allowCellular = $0 }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow on cellular")
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    Text("Default off — only download over WiFi")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .tint(OPSStyle.Colors.text)
            .padding()
        }
    }
}
