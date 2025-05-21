//
//  UIKit+Extensions.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI

// This extension provides compatibility functions for iOS version differences
extension View {
    // A workaround for iOS 15 where TextEditor didn't have scrollContentBackground
    @ViewBuilder func compatibleTextEditorBackground(_ color: Color) -> some View {
        if #available(iOS 16.0, *) {
            self
                .scrollContentBackground(.hidden)
                .background(color)
        } else {
            self
                .background(color)
        }
    }
}