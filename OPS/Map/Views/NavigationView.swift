//
//  NavigationView.swift
//  OPS
//
//  Created by Claude on 2025-06-24.
//
//  Navigation overlay showing current step and controls

import SwiftUI
import MapKit
import UIKit

struct MapNavigationView: View {
    @ObservedObject var coordinator: MapCoordinator
    @State private var showFullDirections = false
    @State private var showDirectionsList = false
    
    var body: some View {
        VStack {
            // Bottom navigation info
            navigationInfo
                .padding(.top, 100)
            // Top navigation bar
           // navigationBar
            
            Spacer()
            
          
            
            // Top navigation bar
         //   navigationBar
         //       .padding(.top, 200) // Account for project header
            
         //   Spacer()
            
            // Bottom navigation info
          //  navigationInfo
         //       .padding(.bottom, 90) // Account for tab bar
        }
        .sheet(isPresented: $showDirectionsList) {
            if let route = coordinator.currentRoute {
                DirectionsListView(
                    steps: route.steps.map { step in
                        MapNavigationStep(
                            instruction: step.instructions,
                            distance: step.distance,
                            coordinate: step.polyline.coordinate
                        )
                    },
                    currentStepIndex: coordinator.navigationEngine.currentStepIndex
                )
            }
        }
    }
    
    // MARK: - Components
    
    private var navigationBar: some View {
        VStack(spacing: 0) {
            // Navigation instruction card
            HStack(spacing: 16) {
                // Direction icon
                Image(systemName: directionIcon)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .frame(width: 50, height: 50)
                    .background(
                        Circle()
                            .fill(OPSStyle.Colors.cardBackground)
                    )
                
                // Instruction text
                VStack(alignment: .leading, spacing: 4) {
                    if let step = coordinator.navigationEngine.currentStep {
                        Text(step.instructions)
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(2)
                        
                        Text(formatDistance(step.distance))
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    } else {
                        Text("Calculating route...")
                            .font(OPSStyle.Typography.subtitle)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: OPSStyle.Colors.primaryAccent))
                            .scaleEffect(0.8)
                    }
                }
                
                Spacer()
                
                // Show all directions button
                Button(action: { showDirectionsList = true }) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(OPSStyle.Colors.cardBackground)
                        )
                }
                .padding(.trailing, 8)
            }
            .padding()
            .background(
                ZStack {
                    BlurView(style: .systemUltraThinMaterialDark)
                    //OPSStyle.Colors.cardBackground.opacity(0.3)
                }
            )
        }
        .frame(width: 362, height: 85)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
    
    private var navigationInfo: some View {
        VStack(spacing: 0) {
            // Progress and arrival info
            HStack {
                // Time remaining
                VStack(alignment: .leading, spacing: 4) {
                    Text("TIME")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(formatTime(coordinator.navigationEngine.estimatedTimeRemaining))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                // Distance remaining
                VStack(alignment: .center, spacing: 4) {
                    Text("DISTANCE")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    Text(formatDistance(coordinator.navigationEngine.totalDistance))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                }
                
                Spacer()
                
                // Arrival time
                VStack(alignment: .trailing, spacing: 4) {
                    Text("ARRIVAL")
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    
                    if let arrival = coordinator.navigationEngine.estimatedArrivalTime {
                        Text(formatArrivalTime(arrival))
                            .font(OPSStyle.Typography.title)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    }
                }
            }
            .padding()
            
            /*
            // Action buttons
            HStack(spacing: 16) {
                // Show directions button
                Button(action: { showFullDirections = true }) {
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16))
                        Text("DIRECTIONS")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                    )
                }
                
                // End navigation button
                Button(action: {
                    coordinator.stopNavigation()
                }) {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                        Text("END")
                            .font(OPSStyle.Typography.button)
                    }
                    .foregroundColor(OPSStyle.Colors.errorStatus)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius)
                            .stroke(OPSStyle.Colors.errorStatus, lineWidth: 2)
                    )
                }
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom)
            */
            
        }/*
        .background(
            ZStack {
                BlurView(style: .systemMaterialDark)
            }
        )
        .cornerRadius(OPSStyle.Layout.cornerRadius, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: -5)
        .sheet(isPresented: $showFullDirections) {
            DirectionsListView(steps: coordinator.navigationEngine.remainingSteps)
        }
          */
    }
    
    // MARK: - Helper Properties
    
    private var directionIcon: String {
        // This would be more sophisticated in production
        guard let step = coordinator.navigationEngine.currentStep else { return "arrow.up" }
        
        let instruction = step.instructions.lowercased()
        if instruction.contains("left") {
            return "arrow.turn.left.up"
        } else if instruction.contains("right") {
            return "arrow.turn.right.up"
        } else if instruction.contains("arrive") {
            return "mappin.circle.fill"
        } else {
            return "arrow.up"
        }
    }
    
    // MARK: - Formatting
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 100 {
            return String(format: "%.0f m", distance)
        } else if distance < 1000 {
            return String(format: "%.0f m", (distance / 10).rounded() * 10)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let hours = Int(seconds) / 3600
        let minutes = Int(seconds) % 3600 / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes) min"
        }
    }
    
    private func formatArrivalTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Directions List View

struct DirectionsListView: View {
    let steps: [MapNavigationStep]
    var currentStepIndex: Int = 0
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List(steps.indices, id: \.self) { index in
                DirectionRow(index: index, step: steps[index], isCurrent: index == currentStepIndex)
            }
            .listStyle(.plain)
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0f meters", distance)
        } else {
            return String(format: "%.1f kilometers", distance / 1000)
        }
    }
}

// MARK: - Direction Row

struct DirectionRow: View {
    let index: Int
    let step: MapNavigationStep
    var isCurrent: Bool = false
    
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Step number
            Text("\(index + 1)")
                .font(OPSStyle.Typography.body)
                .foregroundColor(isCurrent ? .black : OPSStyle.Colors.primaryAccent)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(isCurrent ? OPSStyle.Colors.primaryAccent : Color.clear)
                        .overlay(
                            Circle()
                                .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                        )
                )
            
            // Instruction
            VStack(alignment: .leading, spacing: 4) {
                Text(step.instruction)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                Text(formatDistance(step.distance))
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
            }
            
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0f meters", distance)
        } else {
            return String(format: "%.1f kilometers", distance / 1000)
        }
    }
}
