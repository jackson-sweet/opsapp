//
//  GoogleSignInManager.swift
//  OPS
//
//  Created by OPS Team on 2025-06-17.
//

import Foundation
import GoogleSignIn
import SwiftUI

/// Manages Google Sign-In authentication flow
class GoogleSignInManager: ObservableObject {
    static let shared = GoogleSignInManager()
    
    @Published var isSigningIn = false
    @Published var errorMessage: String?
    
    private init() {
        // First try to load from GoogleService-Info.plist if it exists
        if let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
           let plist = NSDictionary(contentsOfFile: path),
           let clientId = plist["CLIENT_ID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        }
        // Fallback to Info.plist configuration
        else if let path = Bundle.main.path(forResource: "Info", ofType: "plist"),
                let plist = NSDictionary(contentsOfFile: path),
                let clientId = plist["GIDClientID"] as? String {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientId)
        } else {
        }
    }
    
    /// Sign in with Google
    func signIn(presenting viewController: UIViewController) async throws -> GIDGoogleUser {
        isSigningIn = true
        errorMessage = nil
        
        do {
            // Perform Google Sign-In
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: viewController)
            let user = result.user
            
            
            isSigningIn = false
            return user
        } catch {
            isSigningIn = false
            
            // Handle specific Google Sign-In errors
            if let gidError = error as? GIDSignInError {
                switch gidError.code {
                case .canceled:
                    errorMessage = "Sign in was canceled"
                case .hasNoAuthInKeychain:
                    errorMessage = "No previous sign in found"
                case .EMM:
                    errorMessage = "Enterprise Mobility Management error"
                case .scopesAlreadyGranted:
                    errorMessage = "Requested scopes already granted"
                default:
                    errorMessage = "Google Sign-In failed: \(error.localizedDescription)"
                }
            } else {
                errorMessage = "Sign in failed: \(error.localizedDescription)"
            }
            
            throw error
        }
    }
    
    /// Sign out from Google
    func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
    
    /// Check if user has previously signed in
    func restorePreviousSignIn() async -> GIDGoogleUser? {
        do {
            let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
            return user
        } catch {
            print("No previous Google sign-in to restore")
            return nil
        }
    }
    
    /// Handle URL for Google Sign-In callback
    static func handle(_ url: URL) -> Bool {
        return GIDSignIn.sharedInstance.handle(url)
    }
}