//
//  MapControlsView.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Map control buttons and overlays

import SwiftUI
import MapKit

struct MapControlsView: View {
    @ObservedObject var coordinator: MapCoordinator
    
    var body: some View {
        VStack {
            Spacer()
            
            // Center controls aligned to right
            HStack {
                Spacer()
                
                VStack(spacing: 12) {
                // Overview button - shows route during navigation or all projects otherwise
                if coordinator.projects.count > 1 || coordinator.isNavigating {
                    Button(action: {
                        coordinator.fitAllInView()
                    }) {
                        ZStack {
                            BlurView(style: .systemUltraThinMaterialDark)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            
                            // Semi-transparent overlay
                            Color(OPSStyle.Colors.cardBackgroundDark)
                                .opacity(0.5)
                                .frame(width: 44, height: 44)
                                .clipShape(Circle())
                            
                            // Use different icon based on navigation state
                            Image(systemName: coordinator.isNavigating ? "point.topleft.down.to.point.bottomright.filled.curvepath" : "map.fill")
                                .font(.system(size: coordinator.isNavigating ? 18 : 20, weight: .medium))
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }
                    .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                }
                
                // Recenter on user button
                Button(action: {
                    coordinator.recenterOnUser()
                }) {
                    ZStack {
                        BlurView(style: .systemUltraThinMaterialDark)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        
                        // Semi-transparent overlay
                        Color(OPSStyle.Colors.cardBackgroundDark)
                            .opacity(0.5)
                            .frame(width: 44, height: 44)
                            .clipShape(Circle())
                        
                        Image(systemName: "location.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(locationButtonColor)
                    }
                }
                .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                
                    if coordinator.isNavigating {
                        // Map orientation toggle button
                        Button(action: {
                            coordinator.toggleOrientationMode()
                        }) {
                            ZStack {
                                BlurView(style: .systemUltraThinMaterialDark)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                
                                // Semi-transparent overlay
                                Color(OPSStyle.Colors.cardBackgroundDark)
                                    .opacity(0.5)
                                    .frame(width: 44, height: 44)
                                    .clipShape(Circle())
                                
                                Image(systemName: coordinator.mapOrientationMode == "north" ? "location.north.line" : "location")
                                    .font(.system(size: 20, weight: .medium))
                                    .foregroundColor(orientationButtonColor)
                            }
                        }
                        .shadow(color: .black.opacity(0.2), radius: 3, x: 0, y: 2)
                    }

                }
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    private var locationButtonColor: Color {
        if coordinator.locationAuthorizationStatus == .denied ||
           coordinator.locationAuthorizationStatus == .restricted {
            return OPSStyle.Colors.errorStatus
        } else if coordinator.userLocation != nil {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.secondaryText
        }
    }
    
    private var orientationButtonColor: Color {
        // Show active color when in course mode, secondary when in north mode
        if coordinator.mapOrientationMode == "course" {
            return OPSStyle.Colors.primaryText
        } else {
            return OPSStyle.Colors.primaryText
        }
    }
}
