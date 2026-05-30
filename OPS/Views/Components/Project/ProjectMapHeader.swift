//
//  ProjectMapHeader.swift
//  OPS
//
//  Map background only — no nav bar, no gradient.
//  Nav bar is in ProjectDetailsView (Layer 3) for reliable tap targets.
//  Gradient is in the scroll content layer so it scrolls with the title.
//

import SwiftUI
import MapKit

struct ProjectMapHeader: View {
    let project: Project
    let taskColorHexes: [String]
    let pinLabel: String
    let nearbyProjects: [NearbyProjectPin]
    let onMapTap: () -> Void

    static let mapHeight: CGFloat = 320

    var body: some View {
        ZStack(alignment: .bottom) {
            mapView
            // Gradient at bottom — just enough to cover Mapbox watermark
            LinearGradient(
                gradient: Gradient(stops: [
                    .init(color: .clear, location: 0),
                    .init(color: OPSStyle.Colors.background.opacity(0.6), location: 0.5),
                    .init(color: OPSStyle.Colors.background, location: 1.0)
                ]),
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 40)
            .allowsHitTesting(false)
        }
        .frame(height: Self.mapHeight)
    }

    // MARK: - Map

    private var mapView: some View {
        Group {
            if let coordinate = project.coordinate {
                ProjectLocationMapView(
                    coordinate: coordinate,
                    projectName: pinLabel,
                    status: project.status,
                    taskColorHexes: taskColorHexes,
                    isInteractive: false,
                    zoomLevel: 13.0,
                    nearbyProjects: nearbyProjects,
                    showUserLocation: true
                )
                .frame(height: Self.mapHeight)
                .contentShape(Rectangle())
                .onTapGesture { onMapTap() }
            } else {
                Rectangle()
                    .fill(OPSStyle.Colors.cardBackgroundDark)
                    .frame(height: Self.mapHeight)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(OPSStyle.Icons.map)
                                .font(.system(size: OPSStyle.Layout.IconSize.xxl))
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                            Text("No location set")
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.tertiaryText)
                        }
                    )
            }
        }
    }
}

// MARK: - Title Overlay (used in scrollable content)

struct ProjectTitleOverlay: View {
    let project: Project
    var isEditingTitle: Bool = false
    @Binding var editedTitle: String
    var canEdit: Bool = false
    var onStartEditingTitle: (() -> Void)? = nil
    var onSaveTitle: (() -> Void)? = nil
    var onClientLongPress: (() -> Void)? = nil

    @FocusState private var titleFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isEditingTitle {
                // Editable title field
                HStack(spacing: 8) {
                    TextField("", text: $editedTitle)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .textInputAutocapitalization(.characters)
                        .focused($titleFieldFocused)
                        .onAppear { titleFieldFocused = true }
                        .onSubmit {
                            onSaveTitle?()
                        }

                    Button(action: { onSaveTitle?() }) {
                        Text("SAVE")
                            .font(OPSStyle.Typography.captionBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(OPSStyle.Colors.primaryAccent.opacity(0.15))
                            .cornerRadius(OPSStyle.Layout.buttonRadius)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.bottom, 2)
            } else {
                // Static title — long press to edit
                Text(project.title.uppercased())
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .lineLimit(2)
                    .onLongPressGesture {
                        if canEdit {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            onStartEditingTitle?()
                        }
                    }
            }

            // Client name — long press to change
            Text(project.effectiveClientName.uppercased())
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .lineLimit(1)
                .onLongPressGesture {
                    if canEdit {
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                        onClientLongPress?()
                    }
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// Convenience init for backward compatibility (no editing)
extension ProjectTitleOverlay {
    init(project: Project) {
        self.project = project
        self._editedTitle = .constant("")
    }
}
