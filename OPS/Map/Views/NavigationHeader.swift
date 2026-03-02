//
//  NavigationHeader.swift
//  OPS
//
//  Navigation UI displayed during active turn-by-turn navigation.
//  Split into two components like Uber/Apple Maps:
//    - ManeuverCard: Large top card showing next turn instruction
//    - TripInfoStrip: Compact bottom strip with time/distance/ETA
//

import SwiftUI
import CoreLocation

// MARK: - Maneuver Card (Top)

/// Large card showing the next maneuver instruction.
/// Positioned below the ProjectHeader, above the map.
struct NavigationManeuverCard: View {

    @ObservedObject var navigationManager: OPSNavigationManager

    var body: some View {
        if navigationManager.hasArrived {
            arrivedBanner
        } else {
            maneuverCard
        }
    }

    // MARK: - Active Maneuver

    private var maneuverCard: some View {
        HStack(spacing: 12) {
            // Maneuver icon — large, prominent
            Image(systemName: navigationManager.maneuverIcon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(OPSStyle.Colors.primaryAccent)
                )

            // Instruction + distance
            VStack(alignment: .leading, spacing: 2) {
                // Distance to next maneuver
                Text(formatDistanceShort(navigationManager.distanceToNextManeuver))
                    .font(Font.custom("Mohave-SemiBold", size: 22))
                    .foregroundColor(.white)

                // Instruction text
                Text(navigationManager.currentInstruction)
                    .font(Font.custom("Mohave-Regular", size: 15))
                    .foregroundColor(Color.white.opacity(0.85))
                    .lineLimit(2)
            }

            Spacer()

            // Voice toggle
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
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Arrived

    private var arrivedBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "mappin.circle.fill")
                .font(.system(size: 24, weight: .medium))
                .foregroundColor(OPSStyle.Colors.successStatus)

            Text("ARRIVED")
                .font(Font.custom("Mohave-SemiBold", size: 20))
                .foregroundColor(.white)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
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

/// Compact strip showing time remaining, distance, and ETA.
/// Positioned above the ProjectActionBar.
struct NavigationTripStrip: View {

    @ObservedObject var navigationManager: OPSNavigationManager

    var body: some View {
        HStack(spacing: 0) {
            // Time remaining
            statItem(
                value: formatTimeRemaining(navigationManager.timeRemaining),
                label: "TIME"
            )

            thinDivider

            // Distance remaining
            statItem(
                value: formatDistanceShort(navigationManager.distanceRemaining),
                label: "DISTANCE"
            )

            thinDivider

            // ETA
            statItem(
                value: formatArrivalTime(navigationManager.estimatedArrival),
                label: "ARRIVAL"
            )
        }
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Stat Item

    private func statItem(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Font.custom("Mohave-SemiBold", size: 16))
                .foregroundColor(.white)
            Text(label)
                .font(Font.custom("Kosugi-Regular", size: 9))
                .tracking(0.3)
                .foregroundColor(Color.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }

    private var thinDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.10))
            .frame(width: 1, height: 28)
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

    var body: some View {
        NavigationManeuverCard(navigationManager: navigationManager)
    }
}
