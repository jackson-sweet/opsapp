//
//  TeamMemberMapAnnotation.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import SwiftUI
import MapKit

// Custom annotation view for team members on the map
struct TeamMemberMapAnnotation: View {
    let user: User
    let isSelected: Bool
    let onTap: () -> Void
    let onMessageTap: () -> Void
    
    @State private var showPopup = false
    
    // Size configuration
    private var circleSize: CGFloat {
        if isSelected {
            return 32
        } else {
            return 26
        }
    }
    
    var body: some View {
        ZStack {
            // The marker
            ZStack {
                // Pulse animation for selected user
                if isSelected {
                    Circle()
                        .fill(user.roleColor.opacity(0.3))
                        .frame(width: circleSize * 1.3, height: circleSize * 1.3)
                        .scaleEffect(showPopup ? 1.3 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 1.5)
                                .repeatForever(autoreverses: true),
                            value: showPopup
                        )
                }
                
                // Circle background with role color
                Circle()
                    .fill(user.roleColor)
                    .frame(width: circleSize, height: circleSize)
                    .overlay(
                        Circle()
                            .stroke(
                                Color.white,
                                lineWidth: isSelected ? 2 : 0
                            )
                    )
                    .shadow(
                        color: Color.black.opacity(isSelected ? 0.4 : 0.2),
                        radius: isSelected ? 4 : 2,
                        x: 0,
                        y: isSelected ? 2 : 1
                    )
                
                // User initials
                Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                    .font(.system(size: isSelected ? 14 : 12, weight: .bold))
                    .foregroundColor(.white)
            }
            .onTapGesture {
                // Toggle popup state
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    showPopup.toggle()
                }
                
                // Call the parent handler
                onTap()
                
                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()
            }
            
            // Popup only shown when selected and popup state is true
            if isSelected && showPopup {
                TeamMemberPopup(user: user, onMessageTap: onMessageTap)
                    .offset(y: -160) // Offset above the marker
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
                    .zIndex(100)
            }
        }
    }
}

// Popup view that appears when tapping a team member marker
struct TeamMemberPopup: View {
    let user: User
    let onMessageTap: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // User info header
            HStack(spacing: 8) {
                // Avatar
                ZStack {
                    if let imageData = user.profileImageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 40, height: 40)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(user.roleColor)
                            .frame(width: 40, height: 40)
                            .overlay(
                                Text(user.firstName.prefix(1) + user.lastName.prefix(1))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                }
                
                // User details
                VStack(alignment: .leading, spacing: 4) {
                    Text(user.fullName)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(user.roleDisplay)
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                
                Spacer()
            }
            
            Divider()
                .background(OPSStyle.Colors.secondaryText.opacity(0.3))
            
            // Location info row with a small map
            if let coordinate = user.coordinate, let locationName = user.locationName {
                HStack(spacing: 8) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 16))
                        .foregroundColor(user.roleColor)
                    
                    Text(locationName)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .lineLimit(1)
                    
                    Spacer()
                }
            }
            
            // Action buttons
            HStack(spacing: 12) {
                Spacer()
                
                // Message button
                Button(action: onMessageTap) {
                    HStack {
                        Image(systemName: "message.fill")
                            .font(.system(size: 12))
                        Text("Text")
                            .font(OPSStyle.Typography.smallCaption)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(user.roleColor)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
                
                // Call button
                if let phone = user.phone, !phone.isEmpty {
                    Button(action: {
                        if let url = URL(string: "tel:\(phone.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression))") {
                            UIApplication.shared.open(url)
                        }
                    }) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .font(.system(size: 12))
                            Text("Call")
                                .font(OPSStyle.Typography.smallCaption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(OPSStyle.Colors.secondaryAccent)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(OPSStyle.Colors.cardBackground.opacity(0.9))
                .shadow(color: Color.black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
        .frame(width: 220)
    }
}

// Custom annotation class for team members
class TeamMemberAnnotation: NSObject, MKAnnotation {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let isSelected: Bool
    var user: User
    
    init(id: String, coordinate: CLLocationCoordinate2D, isSelected: Bool, user: User) {
        self.id = id
        self.coordinate = coordinate
        self.isSelected = isSelected
        self.user = user
        super.init()
    }
}