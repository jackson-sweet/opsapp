//
//  ActiveProjectCard.swift
//  OPS
//
//  Top-of-screen overlay shown when the user is in project mode but is
//  NOT actively routing (e.g. after arriving on site, or after stopping
//  navigation mid-project). Visually parallel to NavigationManeuverCard:
//  same blurred material, same 4pt radius, same icon block + title stack.
//
//  The EXIT affordance lives below this card (rendered by OPSMapContainer)
//  so both the static and the routing cards share one control.
//

import SwiftUI

struct ActiveProjectCard: View {

    let project: Project

    var body: some View {
        HStack(spacing: 12) {
            // Icon block — matches NavigationManeuverCard's maneuver icon
            // so the transition between routing and non-routing states
            // feels like one card swapping content, not two different UIs.
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .fill(OPSStyle.Colors.primaryAccent)
                )

            // Title + subtitle stack
            VStack(alignment: .leading, spacing: 2) {
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.heading)
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                if !subtitleText.isEmpty {
                    Text(subtitleText)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(Color.white.opacity(0.85))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.chipRadius))
    }

    /// Client name + address joined with a middot, skipping empty parts.
    private var subtitleText: String {
        var parts: [String] = []
        let client = project.effectiveClientName
        if !client.isEmpty {
            parts.append(client)
        }
        if let address = project.address, !address.isEmpty {
            parts.append(address.formatAsSimpleAddress())
        }
        return parts.joined(separator: " · ")
    }
}
