//
//  IconBadge.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI

/// A reusable icon badge component for consistent styling across the app
struct IconBadge: View {
    var iconName: String
    var size: CGFloat = 50
    var color: Color = OPSStyle.Colors.primaryAccent
    var useStroke: Bool = true
    var isDisabled: Bool = false
    
    var body: some View {
        ZStack {
            if useStroke {
                Circle()
                    .stroke(
                        isDisabled ? 
                            OPSStyle.Colors.tertiaryText.opacity(0.3) : 
                            color.opacity(0.5),
                        lineWidth: 1.5
                    )
                    .frame(width: size, height: size)
            } else {
                Circle()
                    .fill(isDisabled ? color.opacity(0.1) : color.opacity(0.2))
                    .frame(width: size, height: size)
            }
            
            Image(systemName: iconName)
                .font(size > 40 ? OPSStyle.Typography.bodyEmphasis : OPSStyle.Typography.body)
                .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : color)
        }
    }
}

struct IconBadgePreview: View {
    var body: some View {
        VStack(spacing: 20) {
            IconBadge(iconName: "person.fill")
            
            IconBadge(iconName: "building.2.fill", useStroke: false)
            
            IconBadge(iconName: "gearshape.fill", size: 40, isDisabled: true)
            
            IconBadge(iconName: "bell.fill", size: 60, color: OPSStyle.Colors.warningStatus, useStroke: false)
        }
        .padding()
        .background(OPSStyle.Colors.backgroundGradient)
        .preferredColorScheme(.dark)
    }
}

#if swift(>=5.9)
#Preview {
    IconBadgePreview()
}
#else
struct IconBadgePreview_Previews: PreviewProvider {
    static var previews: some View {
        IconBadgePreview()
    }
}
#endif