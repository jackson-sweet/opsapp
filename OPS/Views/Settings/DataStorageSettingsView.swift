//
//  DataStorageSettingsView.swift
//  OPS
//
//  The "Data & Storage" settings screen. Top of the hierarchy for anything
//  storage or sync related:
//   - Synchronization toggles (sync on launch, background sync, historical
//     data range) — real UserDefaults bindings read elsewhere
//   - Photo storage budget — real capacity system (StorageProfiler +
//     PhotoStorageBudgetCard). Replaces the previous mocked estimatedStorageUsed
//     slider that generated random numbers and never mutated anything.
//   - Photo prefetch preferences — PhotoPrefetchPreferencesCard
//   - Data management — Clear Image Cache (real) + Clear All Offline Data
//

import SwiftUI

struct DataStorageSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController

    // Sync preferences — real @AppStorage bindings consumed by sync engine
    @AppStorage("syncOnLaunch") private var syncOnLaunch = true
    @AppStorage("backgroundSyncEnabled") private var backgroundSyncEnabled = true
    @AppStorage("historicalDataMonths") private var historicalDataMonths = 6

    @State private var showClearCacheConfirmation = false

    // Bug e33aa336 — settings search deep-link anchors and spotlight.
    private enum AnchorID {
        static let synchronization = "synchronization"
        static let photoStorage = "photo_storage"
        static let autoDownload = "auto_download"
        static let dataManagement = "data_management"
    }

    @State private var highlightedSection: String? = nil

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Data & Storage",
                    onBackTapped: { dismiss() }
                )

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        synchronizationSection
                            .id(AnchorID.synchronization)
                            .deepLinkSpotlight(highlightedSection == AnchorID.synchronization)

                        photoStorageBudgetSection
                            .id(AnchorID.photoStorage)
                            .deepLinkSpotlight(highlightedSection == AnchorID.photoStorage)

                        autoDownloadSection
                            .id(AnchorID.autoDownload)
                            .deepLinkSpotlight(highlightedSection == AnchorID.autoDownload)

                        dataManagementSection
                            .id(AnchorID.dataManagement)
                            .deepLinkSpotlight(highlightedSection == AnchorID.dataManagement)
                    }
                    .padding(.vertical, OPSStyle.Layout.spacing4)
                }
                .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.dataStorage)) { notification in
                    guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
                    let anchor: String?
                    switch section {
                    case "synchronization": anchor = AnchorID.synchronization
                    case "photo_storage":   anchor = AnchorID.photoStorage
                    case "auto_download":   anchor = AnchorID.autoDownload
                    case "data_management": anchor = AnchorID.dataManagement
                    default: anchor = nil
                    }
                    guard let anchor else { return }

                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(OPSStyle.Animation.standard) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                    withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                        highlightedSection = anchor
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await MainActor.run {
                            withAnimation(.easeOut(duration: 0.4)) {
                                highlightedSection = nil
                            }
                        }
                    }
                }
                }
            }
        }
        .trackScreen("Settings.DataStorage")
        .navigationBarBackButtonHidden(true)
        .alert("Clear Image Cache?", isPresented: $showClearCacheConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                PhotoDownloadManager.shared.clearAllCachedPhotos()
            }
        } message: {
            Text("Removes all cached photos from this device. Photos stay available in the cloud and re-download on demand.")
        }
    }

    // MARK: - Synchronization Section

    private var synchronizationSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("SYNCHRONIZATION")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                SettingsToggle(
                    title: "Sync on App Launch",
                    description: "Get data from online when app starts",
                    isOn: $syncOnLaunch
                )

                Divider()
                    .background(OPSStyle.Colors.cardBorder)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                SettingsToggle(
                    title: "Background Sync",
                    description: "Get data from online when app is not open",
                    isOn: $backgroundSyncEnabled
                )

                Divider()
                    .background(OPSStyle.Colors.cardBorder)
                    .padding(.vertical, OPSStyle.Layout.spacing2)

                historicalDataRangeControl
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private var historicalDataRangeControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("Historical Data Range")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)

            Text("Sync projects and tasks from the past \(historicalDataMonths) months")
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: OPSStyle.Layout.spacing2) {
                let monthOptions = [1, 3, 6, 12, 24, 36, -1]
                let sliderSteps = Double(monthOptions.count - 1)

                Slider(value: Binding(
                    get: {
                        if let index = monthOptions.firstIndex(of: historicalDataMonths) {
                            return Double(index)
                        }
                        return 2.0
                    },
                    set: { newValue in
                        let index = Int(round(newValue))
                        if index >= 0 && index < monthOptions.count {
                            historicalDataMonths = monthOptions[index]
                        }
                    }
                ), in: 0...sliderSteps, step: 1)
                .accentColor(OPSStyle.Colors.primaryAccent)

                HStack(alignment: .center, spacing: 0) {
                    ForEach(0..<monthOptions.count, id: \.self) { index in
                        if index > 0 {
                            Spacer(minLength: 0)
                        }

                        Text(formatMonthsLabel(monthOptions[index]))
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .frame(width: index == 0 || index == monthOptions.count - 1 ? 20 : 40)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)

                        if index == 0 {
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing2)
                .frame(height: 20)
            }

            HStack {
                Spacer()
                Text(formatMonthsRange(historicalDataMonths))
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.primaryText)
            }

            if historicalDataMonths == -1 {
                Text("Sync all historical data. This may take longer on first sync.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            } else if historicalDataMonths == 1 {
                Text("Only sync data from the past month. Reduces data usage.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .padding(.top, OPSStyle.Layout.spacing1)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
    }

    // MARK: - Photo Storage Budget Section

    private var photoStorageBudgetSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("PHOTO STORAGE")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            PhotoStorageBudgetCard()
                .environmentObject(dataController)
                .padding(OPSStyle.Layout.spacing3)
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Auto-Download Section

    private var autoDownloadSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("AUTO-DOWNLOAD")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            PhotoPrefetchPreferencesCard()
                .background(OPSStyle.Colors.cardBackgroundDark)
                .cornerRadius(OPSStyle.Layout.cornerRadius)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
                )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Data Management Section

    private var dataManagementSection: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("DATA MANAGEMENT")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: OPSStyle.Layout.spacing3) {
                SettingsButton(
                    title: "Clear Image Cache",
                    icon: OPSStyle.Icons.photo,
                    style: .secondary,
                    action: {
                        showClearCacheConfirmation = true
                    }
                )
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    // MARK: - Formatting Helpers

    private func formatMonthsLabel(_ months: Int) -> String {
        if months == -1 { return "All" }
        if months == 1 { return "1m" }
        if months == 12 { return "1y" }
        if months == 24 { return "2y" }
        if months == 36 { return "3y" }
        return "\(months)m"
    }

    private func formatMonthsRange(_ months: Int) -> String {
        if months == -1 { return "All Data" }
        if months == 1 { return "1 Month" }
        if months == 12 { return "1 Year" }
        if months == 24 { return "2 Years" }
        if months == 36 { return "3 Years" }
        return "\(months) Months"
    }
}

#Preview {
    DataStorageSettingsView()
        .preferredColorScheme(.dark)
        .environmentObject(DataController())
}
