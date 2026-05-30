//
//  NavigationHeader.swift
//  OPS
//
//  Navigation UI displayed during active turn-by-turn navigation.
//  Split into two components like Uber/Apple Maps:
//    - NavigationManeuverCard: Top card showing the current maneuver.
//      Tap the destination row to expand into a full turn-by-turn list.
//    - NavigationTripStrip: Compact bottom strip with time/distance/ETA.
//

import SwiftUI
import MapKit
import CoreLocation

// MARK: - Maneuver Card (Top)

/// Large card showing the current maneuver instruction. Expandable — tap
/// the destination row (or the chevron) to reveal the full upcoming turn
/// list. Positioned at the top of the screen during active navigation.
struct NavigationManeuverCard: View {

    @ObservedObject var navigationManager: OPSNavigationManager
    var destinationName: String?
    @Binding var isExpanded: Bool

    var body: some View {
        if navigationManager.hasArrived {
            arrivedBanner
        } else {
            maneuverCard
        }
    }

    // MARK: - Active Maneuver

    private var maneuverCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            // Destination row doubles as the expansion tab. Tapping
            // anywhere on it toggles the turn-by-turn list. The chevron
            // rotates 180° when expanded as an affordance.
            if shouldShowDestinationRow {
                thinHorizontalDivider
                    .padding(.top, 12)
                    .padding(.bottom, 10)

                destinationRow
            }

            // Expanded turn list — scrollable, capped at 280pt.
            if isExpanded {
                thinHorizontalDivider
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                turnList
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
    }

    // MARK: - Top row (current maneuver)

    private var topRow: some View {
        HStack(spacing: 12) {
            Image(systemName: navigationManager.maneuverIcon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .fill(OPSStyle.Colors.primaryAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDistanceShort(navigationManager.distanceToNextManeuver))
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(.white)

                Text(navigationManager.currentInstruction)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer()

            // Voice toggle — kept on top row so it's always reachable
            // regardless of expansion state.
            Button {
                navigationManager.toggleVoice()
            } label: {
                Image(systemName: navigationManager.isVoiceEnabled
                      ? "speaker.wave.2.fill"
                      : "speaker.slash.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Destination row (expansion tab)

    private var shouldShowDestinationRow: Bool {
        if let name = destinationName, !name.isEmpty { return true }
        return false
    }

    private var destinationRow: some View {
        Button(action: toggleExpanded) {
            HStack(spacing: 8) {
                Image(OPSStyle.Icons.address)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white.opacity(0.55))

                Text((destinationName ?? "").uppercased())
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(0.4)
                    .foregroundColor(Color.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.tail)

                Spacer(minLength: 8)

                Image(OPSStyle.Icons.chevronDown)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.7))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(OPSStyle.Animation.spring, value: isExpanded)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isExpanded ? "Collapse turn list" : "Expand turn list")
        .accessibilityAddTraits(.isButton)
    }

    private func toggleExpanded() {
        // Discovery beat — selection feedback is the right weight for a
        // lightweight disclosure toggle (not a commit-grade decision).
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(OPSStyle.Animation.spring) {
            isExpanded.toggle()
        }
    }

    // MARK: - Expanded turn list

    @ViewBuilder
    private var turnList: some View {
        // Drop the current step (already shown in the top row) and render
        // the rest. If nothing remains, show a placeholder so the panel
        // isn't blank.
        let remaining = Array(navigationManager.upcomingSteps.dropFirst())

        if remaining.isEmpty {
            Text("NO MORE TURNS")
                .font(OPSStyle.Typography.miniLabel)
                .tracking(0.4)
                .foregroundColor(Color.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 10)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(remaining.enumerated()), id: \.offset) { index, step in
                        turnRow(step: step)

                        if index < remaining.count - 1 {
                            Rectangle()
                                .fill(Color.white.opacity(0.06))
                                .frame(height: 1)
                                .padding(.leading, 44) // align with text column
                        }
                    }
                }
            }
            .frame(maxHeight: 280)
        }
    }

    private func turnRow(step: MKRoute.Step) -> some View {
        HStack(spacing: 12) {
            Image(systemName: navigationManager.icon(for: step))
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .fill(Color.white.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(formatDistanceShort(step.distance))
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(0.3)
                    .foregroundColor(Color.white.opacity(0.55))

                Text(step.instructions)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(Color.white.opacity(0.9))
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
    }

    // MARK: - Shared chrome

    private var thinHorizontalDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(height: 1)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
            .fill(.ultraThinMaterial)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
    }

    // MARK: - Arrived

    private var arrivedBanner: some View {
        HStack(spacing: 10) {
            Image(OPSStyle.Icons.siteVisitPin)
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(OPSStyle.Colors.successStatus)

            Text("ARRIVED")
                .font(OPSStyle.Typography.heading)
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
    }

    // MARK: - Format

    private func formatDistanceShort(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.344
        if miles >= 0.1 {
            return String(format: "%.1f MI", miles)
        } else {
            let feet = meters * 3.28084
            return "\(Int(feet)) FT"
        }
    }
}

// MARK: - Trip Info Strip (Bottom)

/// Floating strip showing time remaining, distance, and ETA. No card
/// chrome — the content sits on a soft vertical gradient fading to
/// `OPSStyle.Colors.background` (which matches the Mapbox dark map
/// land color `#0A0A0A`), so the stats appear to rise out of the map
/// rather than sitting in a boxed card.
struct NavigationTripStrip: View {

    @ObservedObject var navigationManager: OPSNavigationManager

    var body: some View {
        HStack(spacing: 0) {
            statItem(
                value: formatTimeRemaining(navigationManager.timeRemaining),
                label: "TIME"
            )

            thinDivider

            statItem(
                value: formatDistanceShort(navigationManager.distanceRemaining),
                label: "DISTANCE"
            )

            thinDivider

            statItem(
                value: formatArrivalTime(navigationManager.estimatedArrival),
                label: "ARRIVAL"
            )
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background(
            // Soft 4-stop vertical gradient, opaque in the middle and
            // fading to transparent at the top and bottom. Matches the
            // dark land color of the Mapbox style so the bleed blends
            // seamlessly into the map.
            LinearGradient(
                stops: [
                    .init(color: OPSStyle.Colors.background.opacity(0), location: 0),
                    .init(color: OPSStyle.Colors.background.opacity(0.85), location: 0.32),
                    .init(color: OPSStyle.Colors.background.opacity(0.85), location: 0.68),
                    .init(color: OPSStyle.Colors.background.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .padding(.vertical, -18) // extend gradient above/below the text
            .allowsHitTesting(false)
        )
    }

    // MARK: - Stat Item

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(OPSStyle.Typography.heading)
                .foregroundColor(.white)
            Text(label)
                .font(OPSStyle.Typography.caption)
                .tracking(0.6)
                .foregroundColor(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(width: 1, height: 36)
    }

    // MARK: - Format

    private func formatDistanceShort(_ meters: CLLocationDistance) -> String {
        let miles = meters / 1609.344
        if miles >= 0.1 {
            return String(format: "%.1f MI", miles)
        } else {
            let feet = meters * 3.28084
            return "\(Int(feet)) FT"
        }
    }

    private func formatTimeRemaining(_ seconds: TimeInterval) -> String {
        let totalMinutes = Int(seconds) / 60
        if totalMinutes < 60 {
            return "\(max(1, totalMinutes)) MIN"
        } else {
            let hours = totalMinutes / 60
            let mins = totalMinutes % 60
            return "\(hours)H \(mins)M"
        }
    }

    private static let arrivalFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func formatArrivalTime(_ date: Date?) -> String {
        guard let date = date else { return "--" }
        return Self.arrivalFormatter.string(from: date)
    }
}

// MARK: - Legacy wrapper (for backward compat if needed)

struct NavigationHeader: View {
    @ObservedObject var navigationManager: OPSNavigationManager
    var destinationName: String? = nil

    var body: some View {
        NavigationManeuverCard(
            navigationManager: navigationManager,
            destinationName: destinationName,
            isExpanded: .constant(false)
        )
    }
}
