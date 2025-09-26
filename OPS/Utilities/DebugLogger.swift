//
//  DebugLogger.swift
//  OPS
//
//  Debug logging to track SwiftData model access
//

import Foundation
import SwiftData

class DebugLogger {
    static let shared = DebugLogger()
    var projectInfo: String
    private init() {projectInfo = ""}
    
    func logProjectAccess(project: Project?, location: String, projectId: String? = nil) {

        if let project = project {
            // Use a different approach to check if valid - wrap in autoreleasepool
            autoreleasepool {
                do {
                    // Try to access the ID to see if it's valid
                    _ = project.id
                    projectInfo = "Project(\(project.id))"
                } catch {
                    projectInfo = "INVALIDATED PROJECT (caught error)"
                }
            }
        } else {
            projectInfo = "nil"
        }
        
        print("[PROJECT ACCESS] \(location): \(projectInfo) (requested: \(projectId ?? "none"))")
        
        // Log call stack to see where this is being called from
        Thread.callStackSymbols.prefix(10).forEach { symbol in
            if symbol.contains("OPS") && !symbol.contains("DebugLogger") {
                print("  -> \(symbol)")
            }
        }
    }
    
    func logModelStorage(type: String, location: String, count: Int? = nil) {
        if let count = count {
            print("[MODEL STORAGE] \(location): Storing \(count) \(type) models")
        } else {
            print("[MODEL STORAGE] \(location): Storing \(type) model")
        }
        
        // Log call stack
        Thread.callStackSymbols.prefix(5).forEach { symbol in
            if symbol.contains("OPS") && !symbol.contains("DebugLogger") {
                print("  -> \(symbol)")
            }
        }
    }
    
    func logCritical(_ message: String, location: String) {
        print("[CRITICAL] \(location): \(message)")
        
        // Log full call stack for critical issues
        print("[CALL STACK]")
        Thread.callStackSymbols.prefix(15).forEach { symbol in
            print("  \(symbol)")
        }
    }
}
