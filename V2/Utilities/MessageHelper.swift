//
//  MessageHelper.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-04.
//

import Foundation
import UIKit
import MessageUI

class MessageHelper {
    
    /// Shared instance for easy access
    static let shared = MessageHelper()
    
    private init() { }
    
    /// Opens the Messages app to send a text message to the specified phone number
    /// - Parameters:
    ///   - phoneNumber: The phone number to text as a string (can include formatting)
    ///   - message: Optional message body to pre-populate
    ///   - viewController: The view controller to present the message composer from (if using MFMessageComposeViewController)
    ///   - completion: Optional completion handler that gets called when the operation is complete
    func sendTextMessage(to phoneNumber: String, withMessage message: String? = nil, from viewController: UIViewController? = nil, completion: ((Bool) -> Void)? = nil) {
        
        // First, clean the phone number of any formatting
        let cleanedNumber = phoneNumber.replacingOccurrences(of: "[^0-9+]", with: "", options: .regularExpression)
        
        // Check if we can use the built-in Messages app
        if MFMessageComposeViewController.canSendText() && viewController != nil {
            // Use the built-in Messages UI
            let messageController = MFMessageComposeViewController()
            messageController.messageComposeDelegate = MessageDelegate.shared
            
            MessageDelegate.shared.completionHandler = completion
            
            messageController.recipients = [cleanedNumber]
            if let message = message {
                messageController.body = message
            }
            
            viewController?.present(messageController, animated: true)
        } else {
            // Use URL scheme as fallback
            openMessagesAppWithURL(phoneNumber: cleanedNumber, message: message)
            completion?(true)
        }
    }
    
    /// Opens the Messages app via URL scheme
    private func openMessagesAppWithURL(phoneNumber: String, message: String? = nil) {
        var urlString = "sms:\(phoneNumber)"
        
        // Add message body if provided
        if let message = message, let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) {
            urlString += "&body=\(encodedMessage)"
        }
        
        if let url = URL(string: urlString) {
            DispatchQueue.main.async {
                UIApplication.shared.open(url)
            }
        }
    }
}

/// Helper class to handle the message compose delegate
class MessageDelegate: NSObject, MFMessageComposeViewControllerDelegate {
    /// Shared instance
    static let shared = MessageDelegate()
    
    /// Completion handler to be called when the message compose view is dismissed
    var completionHandler: ((Bool) -> Void)?
    
    private override init() {
        super.init()
    }
    
    /// Called when the message compose view is dismissed
    func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
        // Dismiss the message compose view
        controller.dismiss(animated: true) {
            // Call the completion handler with success status
            let success = result == .sent
            self.completionHandler?(success)
            self.completionHandler = nil
        }
    }
}

/// SwiftUI extension to access the current UIViewController
extension UIApplication {
    /// Get the top-most view controller
    class func topViewController(controller: UIViewController? = UIApplication.shared.windows.first?.rootViewController) -> UIViewController? {
        if let navigationController = controller as? UINavigationController {
            return topViewController(controller: navigationController.visibleViewController)
        }
        if let tabController = controller as? UITabBarController, 
           let selected = tabController.selectedViewController {
            return topViewController(controller: selected)
        }
        if let presented = controller?.presentedViewController {
            return topViewController(controller: presented)
        }
        return controller
    }
}