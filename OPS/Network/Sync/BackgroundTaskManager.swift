//
//  BackgroundTaskManager.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-21.
//


import Foundation
import UIKit

/// Manages background tasks for sync operations
/// Allows app to continue critical operations briefly when entering background
class BackgroundTaskManager {
    
    /// Start a background task with expiration handler
    /// - Parameter expirationHandler: Handler called if background time expires
    /// - Returns: Identifier for the background task
    @discardableResult
    func beginTask(expirationHandler: @escaping () -> Void) -> UIBackgroundTaskIdentifier {
        let taskID = UIApplication.shared.beginBackgroundTask { 
            // If we run out of time, call the expiration handler
            expirationHandler()
        }
        // End the task
        UIApplication.shared.endBackgroundTask(taskID)
        
        // Start a timer to end the task after 25 seconds (just before the system limit)
        DispatchQueue.global().asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.endTask(taskID)
        }
        
        return taskID
    }
    
    /// End a background task
    /// - Parameter taskID: The task identifier to end
    func endTask(_ taskID: UIBackgroundTaskIdentifier) {
        // Only end valid tasks
        if taskID != .invalid {
            UIApplication.shared.endBackgroundTask(taskID)
        }
    }
}
