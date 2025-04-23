//
//  FieldErrorHandler.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import Foundation
import SwiftUI

/// Simple error handler with field-worker friendly messages
enum FieldErrorHandler {
    
    /// Convert any error to a user-friendly message
    static func userFriendlyMessage(for error: Error) -> String {
        // Handle API errors
        if let apiError = error as? APIError {
            return apiError.localizedDescription
        }
        
        // Handle auth errors
        if let authError = error as? AuthError {
            return authError.localizedDescription
        }
        
        // Common network failures with simplified explanations
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            switch nsError.code {
            case NSURLErrorNotConnectedToInternet:
                return "No internet connection. Check your signal."
            case NSURLErrorTimedOut:
                return "Connection timed out. Try moving to a better signal area."
            case NSURLErrorNetworkConnectionLost:
                return "Connection dropped. The app will keep trying when signal returns."
            default:
                return "Network issue. Try again when you have better reception."
            }
        }
        
        // Default for unknown errors
        return "Something went wrong. The app will keep working offline."
    }
    
    /// Alert to show for an error
    static func alert(for error: Error, retry: (() -> Void)? = nil) -> Alert {
        let message = userFriendlyMessage(for: error)
        
        if let retry = retry {
            return Alert(
                title: Text("Issue Detected"),
                message: Text(message),
                primaryButton: .default(Text("Try Again"), action: retry),
                secondaryButton: .cancel(Text("Continue Offline"))
            )
        } else {
            return Alert(
                title: Text("Issue Detected"),
                message: Text(message),
                dismissButton: .default(Text("Continue"))
            )
        }
    }
    
    /// Toast-style view for non-blocking error feedback
    struct ToastError: View {
        let message: String
        let isNetworkError: Bool
        
        init(error: Error) {
            self.message = FieldErrorHandler.userFriendlyMessage(for: error)
            
            // Check if it's network related
            if let apiError = error as? APIError, 
               case .networkError = apiError {
                isNetworkError = true
            } else if (error as NSError).domain == NSURLErrorDomain {
                isNetworkError = true
            } else {
                isNetworkError = false
            }
        }
        
        var body: some View {
            HStack(spacing: 12) {
                // Icon based on error type
                Image(systemName: isNetworkError ? "wifi.slash" : "exclamationmark.triangle")
                    .foregroundColor(.white)
                
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white)
                
                Spacer()
            }
            .padding()
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)
            .padding(.horizontal)
        }
    }
}
