//
//  CompletionViewPreview.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-07.
//

import SwiftUI

// MARK: - Preview for CompletionView
struct CompletionViewPreview: View {
    @State private var demoMode = true
    
    var body: some View {
        VStack {
            CompletionView {
                print("Preview: Completion callback triggered")
                demoMode.toggle()
            }
            
            // Add controls for Xcode adjustments
            if demoMode {
                VStack {
                    Text("Preview Controls")
                        .font(.headline)
                    
                    Divider()
                    
                    Button("Run Animation Again") {
                        demoMode.toggle()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            demoMode.toggle()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.vertical, 8)
                }
                .padding()
                .background(Color.gray.opacity(0.2))
                .cornerRadius(8)
                .padding()
            }
        }
        .background(Color.black)
        .environmentObject(OnboardingPreviewHelpers.PreviewStyles())
        .environment(\.colorScheme, .dark)
    }
}

#Preview("Completion Screen") {
    CompletionViewPreview()
}