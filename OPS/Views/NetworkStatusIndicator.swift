//
//  NetworkStatusIndicator.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


//
//  NetworkStatusIndicator.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//

import SwiftUI

struct NetworkStatusIndicator: View {
    @EnvironmentObject private var dataController: DataController
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 4) {
            // Connection icon
            Image(systemName: connectionIcon)
                .font(.system(size: 12))
                .foregroundColor(connectionColor)
                .opacity(isAnimating ? 0.5 : 1.0)
                .animation(
                    isAnimating ? 
                        Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : 
                        nil, 
                    value: isAnimating
                )
            
            // Connection type text (only show on non-compact layouts)
            if !isCompact {
                Text(connectionText)
                    .font(OPSStyle.Typography.smallCaption)
                    .foregroundColor(connectionColor)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(OPSStyle.Colors.cardBackground.opacity(0.7))
        )
        .onAppear {
            // Only animate when offline or syncing
            isAnimating = !dataController.isConnected || dataController.isSyncing
        }
        .onChange(of: dataController.isConnected) { _, isConnected in
            isAnimating = !isConnected || dataController.isSyncing
        }
    }
    
    // Current environment width
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    private var isCompact: Bool {
        horizontalSizeClass == .compact
    }
    
    // Connection icon based on state
    private var connectionIcon: String {
        if dataController.isSyncing {
            return "arrow.triangle.2.circlepath"
        }
        
        if !dataController.isConnected {
            return "wifi.slash"
        }
        
        switch dataController.connectionType {
        case .wifi:
            return "wifi"
        case .cellular:
            return "antenna.radiowaves.left.and.right"
        case .wiredEthernet:
            return "network"
        case .none:
            return "wifi.slash"
        }
    }
    
    // Connection text based on state
    private var connectionText: String {
        if dataController.isSyncing {
            return "Syncing..."
        }
        
        if !dataController.isConnected {
            return "Offline"
        }
        
        switch dataController.connectionType {
        case .wifi:
            return "Wi-Fi"
        case .cellular:
            return "Cellular"
        case .wiredEthernet:
            return "Ethernet"
        case .none:
            return "Offline"
        }
    }
    
    // Connection color based on state
    private var connectionColor: Color {
        if dataController.isSyncing {
            return OPSStyle.Colors.warningStatus
        }
        
        if !dataController.isConnected {
            return OPSStyle.Colors.secondaryText
        }
        
        return OPSStyle.Colors.successStatus
    }
}

#Preview {
    NetworkStatusIndicator()
        .environmentObject(DataController())
        .preferredColorScheme(.dark)
}
