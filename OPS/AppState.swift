//
//  AppState.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// AppState.swift
import Foundation
import Combine
import SwiftUI
import SwiftData

class AppState: ObservableObject {
    @Published var activeProjectID: String?
    @Published var activeProject: Project?
    
    var isInProjectMode: Bool {
        activeProject != nil
    }
    
    func enterProjectMode(projectID: String) {
        print("AppState: Setting activeProjectID to \(projectID)")
        self.activeProjectID = projectID
        
        // When using this function directly, we need to make sure
        // the DataController retrieves the project
        NotificationCenter.default.post(
            name: Notification.Name("FetchActiveProject"),
            object: nil,
            userInfo: ["projectID": projectID]
        )
    }
    
    func setActiveProject(_ project: Project) {
        print("AppState: Setting activeProject to \(project.id) - \(project.title)")
        self.activeProject = project
        self.activeProjectID = project.id
    }
    
    func exitProjectMode() {
        print("AppState: Clearing activeProject and activeProjectID")
        self.activeProject = nil
        self.activeProjectID = nil
    }
}