//
//  UIApplication+Extensions.swift
//  OPS
//
//  Created by Assistant on 2025-01-16.
//
//  UIApplication utility extensions

import UIKit

extension UIApplication {
    /// Get the current key window
    func currentUIWindow() -> UIWindow? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        return windowScene?.windows.first(where: { $0.isKeyWindow })
    }
    
    /// Get the root view controller
    var rootViewController: UIViewController? {
        return currentUIWindow()?.rootViewController
    }
}