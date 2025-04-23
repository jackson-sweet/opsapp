//
//  AppState.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-22.
//


// AppState.swift
import Foundation
import Combine

class AppState: ObservableObject {
    @Published var activeProjectID: String?
    
    var isInProjectMode: Bool {
        activeProjectID != nil
    }
    
    func enterProjectMode(projectID: String) {
        self.activeProjectID = projectID
    }
    
    func exitProjectMode() {
        self.activeProjectID = nil
    }
}