//
//  MapSettingsView.swift
//  OPS
//
//  Map settings — style, 3D buildings, camera behavior, navigation, location.
//

import SwiftUI
import CoreLocation

struct MapSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var dataController: DataController
    @EnvironmentObject private var locationManager: LocationManager

    // ── Map Appearance ──
    @AppStorage("mapStyle") private var mapStyleRaw = "dark"
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

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient.edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Maps",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: 24) {

                        // ── LOCATION ──
                        locationStatusCard

                        // ── PROJECT MARKER LEGEND ──
                        markerLegendSection

                        // ── MAP APPEARANCE ──
                        settingsSection(title: "MAP APPEARANCE") {

                            // Map Style
                            settingsRow(title: "Map Style", description: "Color theme for the map") {
                                SegmentedControl(
                                    selection: $mapStyleRaw,
                                    options: [
                                        ("dark", "Dark"),
                                        ("light", "Light"),
                                        ("classic", "Classic")
                                    ]
                                )
                            }

                            settingsDivider

                            // 3D Buildings
                            SettingsToggle(
                                title: "3D Buildings",
                                description: "Buildings appear in 3D when you tilt the map",
                                isOn: $map3DBuildings
                            )
                        }

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

                // Pipeline status colors
                VStack(alignment: .leading, spacing: 12) {
                    Text("CENTER DOT — PIPELINE STATUS")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    legendColorGrid(items: [
                        ("RFQ", OPSStyle.Colors.statusColor(for: .rfq)),
                        ("Estimated", OPSStyle.Colors.statusColor(for: .estimated)),
                        ("Accepted", OPSStyle.Colors.statusColor(for: .accepted)),
                        ("In Progress", OPSStyle.Colors.statusColor(for: .inProgress)),
                        ("Completed", OPSStyle.Colors.statusColor(for: .completed)),
                        ("Closed", OPSStyle.Colors.statusColor(for: .closed)),
                        ("Archived", OPSStyle.Colors.statusColor(for: .archived)),
                    ])
                }
                .padding(16)

                Divider().background(OPSStyle.Colors.cardBorder)

                // Task type colors
                VStack(alignment: .leading, spacing: 12) {
                    Text("OUTER RING — TASK TYPES")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.3)
                        .foregroundColor(OPSStyle.Colors.secondaryText)

                    legendColorGrid(items: [
                        ("Site Estimate", OPSStyle.Colors.successStatus),
                        ("Quote/Proposal", OPSStyle.Colors.primaryAccent),
                        ("Material Order", OPSStyle.Colors.warningStatus),
                        ("Installation", OPSStyle.Colors.errorStatus),
                        ("Inspection", Color(hex: "#7B68A6") ?? OPSStyle.Colors.primaryAccent),
                        ("Completion", OPSStyle.Colors.tertiaryText),
                    ])

                    Text("Task type colors are customizable in your company settings.")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
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
    private var markerDiagram: some View {
        HStack(spacing: 24) {
            // Large rendered marker
            ZStack {
                // Outer ring — segmented
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(OPSStyle.Colors.successStatus, lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.33, to: 0.63)
                    .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 4)
                    .frame(width: 56, height: 56)
                    .rotationEffect(.degrees(-90))

                Circle()
                    .trim(from: 0.66, to: 0.96)
                    .stroke(OPSStyle.Colors.errorStatus, lineWidth: 4)
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
    /// upgrade the turn-by-turn voice and offers a one-tap jump to the
    /// iOS Settings voice picker. iOS has no public API to deep-link
    /// directly to `Settings → Accessibility → Spoken Content → Voices`,
    /// so we try the private `App-Prefs:` scheme first and fall back to
    /// `UIApplication.openSettingsURLString` (which lands on OPS's own
    /// page — the user can swipe back to root Settings from there).
    private var voiceGuidanceRow: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Voice Guidance")
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)

                Text("Turn-by-turn voice uses whatever iOS voice you have downloaded. For a higher-quality voice, download a Premium or Enhanced voice in iOS Settings → Accessibility → Spoken Content → Voices → English.")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: openVoiceSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.right.square")
                        .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    Text("DOWNLOAD VOICES")
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
    }

    /// Try to deep-link to Settings → Accessibility → Spoken Content →
    /// Voices → English. The `App-Prefs:` scheme is private but widely
    /// used; if iOS blocks it we fall back to the public settings URL.
    private func openVoiceSettings() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        // Private deep-link — opens directly to Spoken Content on iOS 17/18.
        if let deepLink = URL(string: "App-Prefs:ACCESSIBILITY&path=SPEECH"),
           UIApplication.shared.canOpenURL(deepLink) {
            UIApplication.shared.open(deepLink)
            return
        }

        // Public fallback — lands on OPS's own Settings page. The user
        // can tap "< Settings" to reach the root and navigate manually.
        if let fallback = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(fallback)
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
        mapStyleRaw = "dark"
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
