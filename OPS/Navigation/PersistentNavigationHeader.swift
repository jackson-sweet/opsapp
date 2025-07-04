//
//  PersistentNavigationHeader.swift
//  OPS
//
//  Persistent navigation header that shows across all app views
//  Designed to match Apple Maps navigation experience

import SwiftUI
import MapKit

struct PersistentNavigationHeader: View {
    @ObservedObject var inProgressManager = InProgressManager.shared
    let selectedTab: Int
    
    var body: some View {
        Group {
            if inProgressManager.isRouting {
                if selectedTab == 0 {
                    // Home tab - push content down
                    VStack(spacing: 0) {
                        // Main Navigation Bar
                        navigationBar
                        
                        Divider()
                            .background(Color(OPSStyle.Colors.primaryText))
                            .padding(.horizontal, 8)
                        
                        // Navigation info (TIME, DISTANCE, ARRIVAL)
                        navigationInfoView
                    }
                    .background(
                        ZStack {
                            // Blur effect
                            BlurView(style: .systemUltraThinMaterialDark).opacity(0.6)
                            
                            // Semi-transparent overlay
                            Color(OPSStyle.Colors.cardBackgroundDark)
                                .opacity(0.5)
                            
                        }
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    )
                    .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                    .padding(.horizontal, 12)
                    
                } else if selectedTab == 1 {
                    // Other tabs (Schedule) - overlay with semi-transparent background
                    VStack {
                        VStack(spacing: 0) {
                            // Main Navigation Bar
                            navigationBar
                                
                        }
                        .background(
                            ZStack {
                                // Blur effect
                                BlurView(style: .systemUltraThinMaterialDark)
                                
                                // Semi-transparent overlay
                                Color(OPSStyle.Colors.cardBackgroundDark)
                                    .opacity(0.5)
                                
                            }
                                .cornerRadius(OPSStyle.Layout.cornerRadius)
                        )
                        .shadow(color: Color.black.opacity(0.3), radius: 10, y: 5)
                        .padding(.horizontal, 12)
                        
                        Spacer()
                    }
                }
            }
        }
    }
    
    // MARK: - Progress Bar
    
    private var progressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                
                // Progress fill
                Rectangle()
                    .fill(Color.white)
                    .frame(width: progressWidth(in: geometry.size.width))
            }
        }
        .frame(height: 3)
        .padding(.top, 8)
        .padding(.horizontal, 24)
    }
    
    // MARK: - Navigation Bar
    
    private var navigationBar: some View {
        HStack(spacing: 16) {
            
            VStack {
                // Turn icon
                Image(systemName: turnIconName)
                    .font(.system(size: 36, weight: .regular))
                    .foregroundColor(.white)
                    //.frame(width: 50, height: 50)
                // Distance
                Text(formatDistance(inProgressManager.distanceToNextStep))
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
            }
            Spacer()
            // Instructions
            VStack(alignment: .trailing, spacing: 2) {
                Text(currentInstruction)
                    .font(OPSStyle.Typography.cardTitle)
                    .foregroundColor(.white)
                    .lineLimit(1)
                
                if let nextInstruction = nextInstruction {
                    Text("Then \(nextInstruction)")
                        .font(OPSStyle.Typography.cardSubtitle)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }
            }
            

            
            
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
    }
    
    // MARK: - Turn Icon
    
    private var turnIconName: String {
        guard let step = inProgressManager.currentNavStep else {
            return "location.fill"
        }
        
        let instruction = step.instruction.lowercased()
        
        if instruction.contains("left") {
            return "arrow.turn.up.left"
        } else if instruction.contains("right") {
            return "arrow.turn.up.right"
        } else if instruction.contains("straight") || instruction.contains("continue") {
            return "arrow.up"
        } else if instruction.contains("arrive") || instruction.contains("destination") {
            return "mappin.circle"
        } else if instruction.contains("roundabout") || instruction.contains("rotary") {
            return "arrow.triangle.circlepath"
        } else if instruction.contains("merge") {
            return "arrow.merge"
        } else if instruction.contains("exit") {
            return "arrow.turn.up.right"
        } else {
            return "arrow.up"
        }
    }
    
    // MARK: - Computed Properties
    
    private var currentInstruction: String {
        inProgressManager.currentNavStep?.instruction ?? "Continue to destination"
    }
    
    private var nextInstruction: String? {
        guard inProgressManager.remainingSteps.count > 1 else { return nil }
        let next = inProgressManager.remainingSteps[1].instruction
        // Extract just the key part of the instruction
        if let turnRange = next.range(of: "turn", options: .caseInsensitive) {
            let afterTurn = String(next[turnRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            return afterTurn.lowercased()
        }
        return next
    }
    
    // MARK: - Helpers
    
    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard let route = inProgressManager.activeRoute else { return 0 }
        
        let totalDistance = route.distance
        let remainingDistance = inProgressManager.remainingSteps.reduce(0) { $0 + $1.distanceValue }
        let progress = max(0, min(1, 1 - (remainingDistance / totalDistance)))
        
        return totalWidth * CGFloat(progress)
    }
    
    private func formatDistance(_ distance: CLLocationDistance) -> String {
        let formatter = MKDistanceFormatter()
        formatter.unitStyle = .abbreviated
        formatter.units = .metric
        
        return formatter.string(fromDistance: distance)
    }
    
    // MARK: - Navigation Info View
    
    private var navigationInfoView: some View {
        HStack {
            // Time remaining
            VStack(alignment: .leading, spacing: 4) {
                Text("TIME")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                if let travelTime = inProgressManager.activeRoute?.expectedTravelTime {
                    Text(formatTime(travelTime))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                } else {
                    Text("--")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                }
            }
            
            Spacer()
            
            // Distance remaining
            VStack(alignment: .center, spacing: 4) {
                Text("DISTANCE")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                if let distance = inProgressManager.activeRoute?.distance {
                    Text(formatDistanceKm(distance))
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                } else {
                    Text("--")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                }
            }
            
            Spacer()
            
            // Arrival time
            VStack(alignment: .trailing, spacing: 4) {
                Text("ARRIVAL")
                    .font(OPSStyle.Typography.caption)
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                
                if let arrival = inProgressManager.estimatedArrival {
                    Text(arrival.components(separatedBy: " ").first ?? arrival)
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                } else {
                    Text("--:--")
                        .font(OPSStyle.Typography.title)
                        .foregroundColor(OPSStyle.Colors.primaryText).opacity(0.8)
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 24)
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
    
    private func formatDistanceKm(_ distance: CLLocationDistance) -> String {
        if distance < 1000 {
            return String(format: "%.0f m", distance)
        } else {
            return String(format: "%.1f km", distance / 1000)
        }
    }
}

// MARK: - Preview

struct PersistentNavigationHeader_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PersistentNavigationHeader(selectedTab: 0)
            Spacer()
        }
        .background(Color.gray)
    }
}
