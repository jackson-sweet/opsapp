//
//  MapSettingsView.swift
//  OPS
//
//  Map settings — style, 3D buildings, camera behavior, navigation, location.
//

import SwiftUI
import SwiftData
import CoreLocation

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var locationManager: LocationManager

    // ── Voice info alert ──
    @State private var showingVoiceInfo = false

    // ── Task types (dynamic legend) ──
    @Query(sort: \TaskType.displayOrder) private var allTaskTypes: [TaskType]

    /// Task types for the current user's company, filtered to non-deleted
    /// records, used to render the project marker outer-ring legend.
    private var companyTaskTypes: [TaskType] {
        guard let companyId = dataController.currentUser?.companyId else { return [] }
        return allTaskTypes
            .filter { $0.companyId == companyId && $0.deletedAt == nil }
            .sorted { $0.displayOrder < $1.displayOrder }
    }

    // ── Map Appearance ──
    @AppStorage("map3DBuildings") private var map3DBuildings = true

    // ── Camera Behavior ──
    @AppStorage("mapOrientation") private var mapOrientationRaw = "northUp"
    @AppStorage("mapAutoZoom") private var mapAutoZoom = true
    @AppStorage("mapZoomLevel") private var mapZoomLevel = "medium"
    @AppStorage("mapAutoCenter") private var mapAutoCenter = true
    @AppStorage("mapAutoCenterTime") private var mapAutoCenterTime = "10"

    // ── Default Filter ──
    @AppStorage("mapDefaultFilter") private var mapDefaultFilter = ""

    // ── Navigation ──
    @AppStorage("mapSpeedZoom") private var mapSpeedZoom = true

    // Bug e33aa336 — settings search deep-link anchors and spotlight.
    private enum AnchorID {
        static let mapAppearance = "map_appearance"
        static let defaultView = "default_view"
        static let camera = "camera"
        static let navigation = "navigation"
    }

    @State private var highlightedSection: String? = nil

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Maps",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 24) {

                        // ── LOCATION ──
                        locationStatusCard

                        // ── PROJECT MARKER LEGEND ──
                        markerLegendSection

                        // ── MAP APPEARANCE ──
                        settingsSection(title: "MAP APPEARANCE") {

                            // 3D Buildings
                            SettingsToggle(
                                title: "3D Buildings",
                                description: "Buildings appear in 3D when you tilt the map",
                                isOn: $map3DBuildings
                            )
                        }
                        .id(AnchorID.mapAppearance)
                        .deepLinkSpotlight(highlightedSection == AnchorID.mapAppearance)

                        // ── DEFAULT VIEW ──
                        settingsSection(title: "DEFAULT VIEW") {
                            settingsRow(
                                title: "Default Filter",
                                description: "Which projects show when you open the map"
                            ) {
                                SegmentedControl(
                                    selection: $mapDefaultFilter,
                                    options: [
                                        ("", "Auto"),
                                        ("today", "Today"),
                                        ("active", "Active"),
                                        ("all", "All")
                                    ]
                                )
                            }
                        }
                        .id(AnchorID.defaultView)
                        .deepLinkSpotlight(highlightedSection == AnchorID.defaultView)

                        // ── CAMERA BEHAVIOR ──
                        settingsSection(title: "CAMERA") {

                            // Default Orientation
                            settingsRow(title: "Default Orientation", description: "Map rotation behavior") {
                                SegmentedControl(
                                    selection: $mapOrientationRaw,
                                    options: [
                                        ("northUp", "North Up"),
                                        ("courseUp", "Track Up")
                                    ]
                                )
                            }

                            settingsDivider

                            // Auto Center
                            SettingsToggle(
                                title: "Auto Center",
                                description: "Re-center map when switching between projects",
                                isOn: $mapAutoCenter
                            )

                            settingsDivider

                            // Auto Re-center Time
                            settingsRow(
                                title: "Re-center Delay",
                                description: "Time before map automatically re-centers"
                            ) {
                                SegmentedControl(
                                    selection: $mapAutoCenterTime,
                                    options: [
                                        ("off", "Off"),
                                        ("2", "2s"),
                                        ("5", "5s"),
                                        ("10", "10s")
                                    ]
                                )
                                .disabled(!mapAutoCenter)
                                .opacity(mapAutoCenter ? 1.0 : 0.5)
                            }

                            settingsDivider

                            // Auto Zoom
                            SettingsToggle(
                                title: "Auto Zoom",
                                description: "Zoom to fit project markers automatically",
                                isOn: $mapAutoZoom
                            )

                            settingsDivider

                            // Zoom Level
                            settingsRow(
                                title: "Default Zoom Level",
                                description: "How close the map zooms to projects"
                            ) {
                                SegmentedControl(
                                    selection: $mapZoomLevel,
                                    options: [
                                        ("close", "Close"),
                                        ("medium", "Medium"),
                                        ("far", "Far")
                                    ]
                                )
                                .disabled(!mapAutoZoom)
                                .opacity(mapAutoZoom ? 1.0 : 0.5)
                            }
                        }
                        .id(AnchorID.camera)
                        .deepLinkSpotlight(highlightedSection == AnchorID.camera)

                        // ── NAVIGATION ──
                        settingsSection(title: "NAVIGATION") {

                            SettingsToggle(
                                title: "Speed-Based Zoom",
                                description: "Zoom out at highway speed, zoom in when slow",
                                isOn: $mapSpeedZoom
                            )

                            settingsDivider

                            voiceGuidanceRow
                        }
                        .id(AnchorID.navigation)
                        .deepLinkSpotlight(highlightedSection == AnchorID.navigation)

                        // ── RESET ──
                        SettingsButton(
                            title: "Reset to Defaults",
                            icon: "arrow.clockwise",
                            style: .secondary
                        ) {
                            resetToDefaults()
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                    .padding(.vertical, 24)
                }
                // Bug e33aa336 — scroll to + spotlight the section the
                // search result targeted, then clear the highlight.
                .onReceive(NotificationCenter.default.publisher(for: SettingsDeepLink.map)) { notification in
                    guard let section = notification.userInfo?[SettingsDeepLink.userInfoSectionKey] as? String else { return }
                    let anchor: String?
                    switch section {
                    case "map_appearance": anchor = AnchorID.mapAppearance
                    case "default_view":   anchor = AnchorID.defaultView
                    case "camera":         anchor = AnchorID.camera
                    case "navigation":     anchor = AnchorID.navigation
                    default: anchor = nil
                    }
                    guard let anchor else { return }

                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(OPSStyle.Animation.smooth) {
                        proxy.scrollTo(anchor, anchor: .top)
                    }
                    withAnimation(.easeIn(duration: 0.2).delay(0.15)) {
                        highlightedSection = anchor
                    }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_600_000_000)
                        await MainActor.run {
                            withAnimation(OPSStyle.Animation.fast) {
                                highlightedSection = nil
                            }
                        }
                    }
                }
                }
            }
        }
        .trackScreen("Settings.Map")
        .navigationBarBackButtonHidden(true)
        .onAppear {
            locationManager.requestPermissionIfNeeded(requestAlways: false)
        }
    }

    // MARK: - Project Marker Legend

    private var markerLegendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROJECT MARKERS")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                // Large marker example
                VStack(spacing: 16) {
                    markerDiagram
                        .padding(.top, 8)

                    // Explanation text
                    Text("Each pin on the map represents a project. The center dot shows the project's pipeline status. The outer ring is divided into segments — one for each task type assigned to the project.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)

                Divider().background(OPSStyle.Colors.cardBorder)

                // Pipeline status colors — iterates Status.allCases so the
                // list stays in sync with the enum automatically.
                VStack(alignment: .leading, spacing: 12) {
                    Text("CENTER DOT — PIPELINE STATUS")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    legendColorGrid(items: Status.allCases.map { status in
                        (status.displayName, OPSStyle.Colors.statusColor(for: status))
                    })
                }
                .padding(16)

                Divider().background(OPSStyle.Colors.cardBorder)

                // Task type colors — pulled live from the user's company
                // task types. Shows an empty-state when none are configured.
                VStack(alignment: .leading, spacing: 12) {
                    Text("OUTER RING — TASK TYPES")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    if companyTaskTypes.isEmpty {
                        Text("No task types configured yet. Add them in Settings → Task Types.")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        legendColorGrid(items: companyTaskTypes.map { taskType in
                            (
                                taskType.display,
                                Color(hex: taskType.color) ?? OPSStyle.Colors.primaryAccent
                            )
                        })

                        Text("Task type colors are customizable in Settings → Task Types.")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(16)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, 20)
    }

    /// Large visual diagram of a project marker with labels.
    /// The outer ring uses the first three live task type colors from
    /// the company so the illustration matches what the user actually
    /// sees on the map. Falls back to OPSStyle accents when the
    /// company has fewer than three task types configured.
    private var markerDiagram: some View {
        HStack(spacing: 24) {
            // Large rendered marker
            ZStack {
                // Outer ring — segmented (up to 3 segments drawn)
                let ringColors = diagramRingColors
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(ringColors[0], lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.33, to: 0.63)
                    .stroke(ringColors[1], lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.66, to: 0.96)
                    .stroke(ringColors[2], lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                // Center dot — status color
                Circle()
                    .fill(OPSStyle.Colors.pipelineStageColor(for: .quoting))
                    .frame(width: 32, height: 32)
            }

            // Labels
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("OUTER RING = TASK TYPES")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }

                HStack(spacing: 8) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    Text("CENTER DOT = STATUS")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
            }
        }
    }

    /// Three colors for the marker diagram's outer ring. Prefers the
    /// company's first three task types so the illustration matches the
    /// real map. Falls back to OPSStyle accents when fewer exist.
    private var diagramRingColors: [Color] {
        let fallback: [Color] = [
            OPSStyle.Colors.successStatus,
            OPSStyle.Colors.primaryAccent,
            OPSStyle.Colors.errorStatus
        ]
        let live = companyTaskTypes
            .prefix(3)
            .map { Color(hex: $0.color) ?? OPSStyle.Colors.primaryAccent }
        // Pad with fallbacks if the company has fewer than 3 types.
        var result: [Color] = Array(live)
        while result.count < 3 {
            result.append(fallback[result.count])
        }
        return result
    }

    /// Grid of color swatches with labels.
    private func legendColorGrid(items: [(String, Color)]) -> some View {
        let columns = [
            GridItem(.flexible(), spacing: 8),
            GridItem(.flexible(), spacing: 8)
        ]

        return LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items, id: \.0) { item in
                HStack(spacing: 8) {
                    Circle()
                        .fill(item.1)
                        .frame(width: 10, height: 10)

                    Text(item.0)
                        .font(OPSStyle.Typography.cardBody)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Voice Guidance Row

    /// Inline row inside the NAVIGATION section that explains how to
    /// upgrade the turn-by-turn voice. iOS has no public API to
    /// deep-link directly to `Settings → Accessibility → Spoken Content
    /// → Voices`, and the private `App-Prefs:` path schemes are
    /// unreliable on iOS 17/18 (they land on arbitrary Settings pages
    /// or do nothing at all). Instead we show a confirmation alert
    /// with exact step-by-step instructions, then open iOS Settings
    /// via the public `openSettingsURLString` — which lands on OPS's
    /// own Settings page. The user taps the "< Settings" back chevron
    /// once to reach root, then follows the steps.
    private var voiceGuidanceRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Guidance")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Turn-by-turn voice uses whatever iOS voice you have installed. Apple doesn't allow apps to deep-link to the voice picker directly, so you'll need to navigate there manually.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showingVoiceInfo = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    Text("HOW TO DOWNLOAD VOICES")
                        .font(OPSStyle.Typography.captionBold)
                }
                .foregroundColor(OPSStyle.Colors.primaryAccent)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: OPSStyle.Layout.Border.standard)
                )
            }
            .buttonStyle(PlainButtonStyle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .alert("Download a Premium Voice", isPresented: $showingVoiceInfo) {
            Button("Open Settings") {
                openSettingsRoot()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("In Settings, navigate:\n\n• Accessibility\n• Spoken Content\n• Voices\n• English\n\nDownload any voice labelled Premium — Ava, Zoe, Evan, or Nathan are the best. OPS will pick it up on your next navigation session.")
        }
    }

    /// Try to open iOS Settings at the root (so the user lands on the
    /// main Settings list and can tap Accessibility directly). Apple's
    /// public API (`UIApplication.openSettingsURLString`) only opens
    /// the app's own settings page, so we first try the unofficial
    /// `App-prefs:` root scheme. If iOS blocks it (uncommon for the
    /// bare root variant, common for path-suffixed variants) we fall
    /// back to the public URL and the user can tap the back arrow once
    /// to reach Settings root.
    private func openSettingsRoot() {
        if let rootURL = URL(string: "App-prefs:"),
           UIApplication.shared.canOpenURL(rootURL) {
            UIApplication.shared.open(rootURL)
            return
        }
        if let appSettings = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(appSettings)
        }
    }

    // MARK: - Reusable Section Builders

    /// Section with a header label and a card body.
    @ViewBuilder
    private func settingsSection<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)

            VStack(spacing: 0) {
                content()
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .padding(.horizontal, 20)
    }

    /// A row inside a section card: title + description + custom control.
    @ViewBuilder
    private func settingsRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(description)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            control()
        }
        .padding(16)
    }

    /// Standard divider between rows inside a section card.
    private var settingsDivider: some View {
        Divider()
            .background(OPSStyle.Colors.cardBorder)
            .padding(.vertical, 4)
    }

    // MARK: - Location Status Card

    private var isLocationAuthorized: Bool {
        locationManager.authorizationStatus == .authorizedAlways ||
        locationManager.authorizationStatus == .authorizedWhenInUse
    }

    private var locationStatusCard: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            Circle()
                .fill(isLocationAuthorized
                      ? OPSStyle.Colors.successStatus
                      : OPSStyle.Colors.errorStatus)
                .frame(width: OPSStyle.Layout.Indicator.dotMD,
                       height: OPSStyle.Layout.Indicator.dotMD)

            VStack(alignment: .leading, spacing: 2) {
                Text(locationStatusText)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text(locationStatusDescription)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }

            Spacer()

            Button {
                handleLocationAction()
            } label: {
                Text(locationActionText)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(isLocationAuthorized
                                     ? OPSStyle.Colors.primaryAccent
                                     : OPSStyle.Colors.invertedText)
                    .padding(.horizontal, OPSStyle.Layout.spacing2_5)
                    .padding(.vertical, OPSStyle.Layout.spacing1)
                    .background(isLocationAuthorized
                                ? Color.clear
                                : OPSStyle.Colors.primaryText)
                    .cornerRadius(OPSStyle.Layout.cornerRadius)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                            .stroke(isLocationAuthorized
                                    ? OPSStyle.Colors.primaryAccent
                                    : Color.clear,
                                    lineWidth: OPSStyle.Layout.Border.standard)
                    )
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
        )
        .padding(.horizontal, 20)
    }

    // MARK: - Location Helpers

    private var locationStatusText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:  return "LOCATION ALWAYS ENABLED"
        case .authorizedWhenInUse: return "LOCATION WHEN IN USE"
        case .denied, .restricted: return "LOCATION DISABLED"
        case .notDetermined:     return "LOCATION NOT SET"
        @unknown default:        return "LOCATION STATUS UNKNOWN"
        }
    }

    private var locationStatusDescription: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways:  return "Full location access enabled"
        case .authorizedWhenInUse: return "Location available when app is open"
        case .denied, .restricted: return "Enable to see your location on map"
        case .notDetermined:     return "Grant permission to use location"
        @unknown default:        return "Check location settings"
        }
    }

    private var locationActionText: String {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return "MANAGE"
        case .denied, .restricted: return "ENABLE"
        case .notDetermined:       return "ALLOW"
        @unknown default:          return "SETTINGS"
        }
    }

    private func handleLocationAction() {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse, .restricted:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        case .denied, .notDetermined:
            locationManager.requestPermissionIfNeeded(requestAlways: true)
        @unknown default:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
    }

    // MARK: - Reset

    private func resetToDefaults() {
        map3DBuildings = true
        mapDefaultFilter = ""
        mapOrientationRaw = "northUp"
        mapAutoZoom = true
        mapZoomLevel = "medium"
        mapAutoCenter = true
        mapAutoCenterTime = "10"
        mapSpeedZoom = true
    }
}

#Preview {
    MapSettingsView()
        .environmentObject(DataController())
}
