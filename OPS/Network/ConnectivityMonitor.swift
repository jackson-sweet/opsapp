//
//  ConnectivityMonitor.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation
import Network

// MARK: - Connectivity Monitor
// Tracks network availability for offline-first operations

class ConnectivityMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")
    
    // Notification name for connectivity changes
    static let connectivityChangedNotification = Notification.Name("ConnectivityMonitorDidChangeConnectivity")
    
    // Current connectivity state
    private(set) var isConnected = false
    private(set) var connectionType: ConnectionType = .none
    
    // Callback for when connectivity changes
    var onConnectionTypeChanged: ((ConnectionType) -> Void)?
    
    // Connection types - more specific than just boolean connected/disconnected
    enum ConnectionType {
        case none
        case wifi
        case cellular
        case wiredEthernet
    }
    
    init() {
        setupMonitor()
    }
    
    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            // Update isConnected status
            self.isConnected = path.status == .satisfied
            
            // Determine connection type
            let newConnectionType: ConnectionType
            if path.usesInterfaceType(.wifi) {
                newConnectionType = .wifi
            } else if path.usesInterfaceType(.cellular) {
                newConnectionType = .cellular
            } else if path.usesInterfaceType(.wiredEthernet) {
                newConnectionType = .wiredEthernet
            } else {
                newConnectionType = .none
            }
            
            // Only notify if connection type changed
            if self.connectionType != newConnectionType {
                self.connectionType = newConnectionType
                
                // Execute callback on main thread
                DispatchQueue.main.async {
                    self.onConnectionTypeChanged?(newConnectionType)
                    
                    // Post notification for observers
                    NotificationCenter.default.post(
                        name: ConnectivityMonitor.connectivityChangedNotification,
                        object: self,
                        userInfo: ["connectionType": newConnectionType]
                    )
                }
            }
        }
        
        // Start monitoring
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}