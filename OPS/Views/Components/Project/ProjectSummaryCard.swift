//
//  ProjectSummaryCard.swift
//  OPS
//
//  Compact summary card with map and key project info for ProjectDetailsView
//

import SwiftUI
import MapKit

/// Compact project summary card with tappable map and key info
///
/// Features:
/// - Compact map view (~80pt) with location pin
/// - Tap map to open directions in Maps app
/// - Info row below: address, date range, team count, status badge
struct ProjectSummaryCard: View {
    let project: Project

    // MARK: - Computed Properties
    private var dateRangeText: String {
        let startDate = project.computedStartDate
        let endDate = project.computedEndDate

        if let start = startDate, let end = endDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        } else if let start = startDate {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "From \(formatter.string(from: start))"
        } else {
            return "Not scheduled"
        }
    }

    private var teamCount: Int {
        // Get unique team member count from all tasks
        let uniqueIds = Set(project.tasks.flatMap { $0.getTeamMemberIds() })
        return uniqueIds.count
    }

    private var shortAddress: String {
        guard let address = project.address, !address.isEmpty else {
            return "No address"
        }
        // Return first line of address (street address)
        return address.components(separatedBy: ",").first ?? address
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Map Section
            compactMapView
                .frame(height: 80)

            // MARK: - Info Row
            infoRow
        }
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Compact Map View
    private var compactMapView: some View {
        Button(action: {
            openInMaps(coordinate: project.coordinate, address: project.address ?? "")
        }) {
            ZStack {
                if let coordinate = project.coordinate {
                    // Map with location
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))) {
                        Annotation("", coordinate: coordinate) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                        }
                    }
                    .mapStyle(.standard(elevation: .flat))
                    .allowsHitTesting(false)
                    .disabled(true)
                } else {
                    // No location fallback
                    OPSStyle.Colors.cardBackground
                        .overlay(
                            HStack(spacing: 8) {
                                Image(systemName: "map.slash")
                                    .font(.system(size: 16))
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                                Text("NO LOCATION")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.tertiaryText)
                            }
                        )
                }

                // Directions hint overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                                .font(.system(size: 10))
                            Text("DIRECTIONS")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.9))
                        .cornerRadius(4)
                        .padding(8)
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: OPSStyle.Layout.cornerRadius,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 0,
                topTrailingRadius: OPSStyle.Layout.cornerRadius
            )
        )
    }

    // MARK: - Info Row
    private var infoRow: some View {
        HStack(spacing: 16) {
            // Address
            HStack(spacing: 4) {
                Image(systemName: "mappin.circle")
                    .font(.system(size: 11))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(shortAddress.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .lineLimit(1)
            }

            Spacer()

            // Date range
            HStack(spacing: 4) {
                Image(systemName: OPSStyle.Icons.calendar)
                    .font(.system(size: 11))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text(dateRangeText.uppercased())
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(project.computedStartDate != nil ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
            }

            // Team count
            HStack(spacing: 4) {
                Image(systemName: OPSStyle.Icons.personTwo)
                    .font(.system(size: 11))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)

                Text("\(teamCount)")
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(teamCount > 0 ? OPSStyle.Colors.secondaryText : OPSStyle.Colors.tertiaryText)
            }

            // Status badge
            Text(project.status.displayName.uppercased())
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(project.status.color)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(project.status.color.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(project.status.color.opacity(0.3), lineWidth: 1)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(OPSStyle.Colors.cardBackgroundDark)
    }
}
