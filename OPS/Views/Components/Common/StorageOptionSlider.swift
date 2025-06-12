//
//  StorageOptionSlider.swift
//  OPS
//
//  Storage options slider with incremental values for offline caching
//

import SwiftUI

struct StorageOptionSlider: View {
    @Binding var selectedStorageIndex: Int
    @EnvironmentObject var viewModel: OnboardingViewModel
    
    let storageOptions: [(value: String, description: String)] = [
        ("0", "Stream everything online. No offline access."),
        ("100 MB", "~50 projects with basic info"),
        ("250 MB", "~125 projects with basic info"),
        ("500 MB", "~250 projects with photos"),
        ("1 GB", "~500 projects with photos"),
        ("5 GB", "~2,500 projects with full media"),
        ("Unlimited", "Store everything offline")
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Current selection display
            HStack {
                Image(systemName: selectedStorageIndex == 0 ? "icloud" : "internaldrive")
                    .font(.system(size: 24))
                    .foregroundColor(OPSStyle.Colors.primaryAccent)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(storageOptions[selectedStorageIndex].value)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.primaryText : OPSStyle.Colors.primaryText)
                    
                    Text(storageOptions[selectedStorageIndex].description)
                        .font(.caption)
                        .foregroundColor(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.secondaryText : OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                        
                }
                
                Spacer()
            }
            .padding()
            .background(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackground.opacity(0.1) : OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            // Slider
            VStack(spacing: 16) {
                // Value labels above slider
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<storageOptions.count, id: \.self) { index in
                        if index > 0 {
                            Spacer()
                        }
                        
                        /*
                        Text(storageOptions[index].value)
                            .font(.caption)
                            .foregroundColor(index == selectedStorageIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText)
                            .multilineTextAlignment(.center)
                            //.frame(width: 60)
                            .animation(.easeInOut(duration: 0.2), value: selectedStorageIndex)
                        
                        if index == storageOptions.count - 1 {
                            Spacer()
                                .frame(width: 0)
                        }
                        */
                    }
                }
                .padding(.horizontal, 4)
                
                // Custom slider with snap points
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track with dots
                        HStack(spacing: 0) {
                            ForEach(0..<storageOptions.count, id: \.self) { index in
                                if index > 0 {
                                    // Line between dots
                                    Rectangle()
                                        .fill(index <= selectedStorageIndex ? OPSStyle.Colors.primaryAccent : (viewModel.shouldUseLightTheme ? OPSStyle.Colors.tertiaryText.opacity(0.3) : OPSStyle.Colors.tertiaryText.opacity(0.3)))
                                        .frame(height: 2)
                                        .animation(.easeInOut(duration: 0.2), value: selectedStorageIndex)
                                }
                                
                                // Dot
                                Circle()
                                    .fill(viewModel.shouldUseLightTheme ? OPSStyle.Colors.Light.background : OPSStyle.Colors.background)
                                    .frame(width: 8, height: 8)
                                    .overlay(
                                        Circle()
                                            .stroke(index <= selectedStorageIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.tertiaryText.opacity(0.3), lineWidth: 2)
                                    )
                                    .animation(.easeInOut(duration: 0.2), value: selectedStorageIndex)
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedStorageIndex = index
                                        }
                                    }
                            }
                        }
                        
                        // Thumb (larger circle)
                        Circle()
                            .fill(viewModel.shouldUseLightTheme ? OPSStyle.Colors.cardBackgroundDark : OPSStyle.Colors.Light.cardBackgroundDark)
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .fill(viewModel.shouldUseLightTheme ? OPSStyle.Colors.primaryText : OPSStyle.Colors.Light.primaryText)
                                    .frame(width: 8, height: 8)
                            )
                            .offset(x: (geometry.size.width / CGFloat(storageOptions.count - 1)) * CGFloat(selectedStorageIndex) - 10)
                            .animation(.easeInOut(duration: 0.2), value: selectedStorageIndex)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let segmentWidth = geometry.size.width / CGFloat(storageOptions.count - 1)
                                        let newIndex = Int(round(value.location.x / segmentWidth))
                                        selectedStorageIndex = max(0, min(storageOptions.count - 1, newIndex))
                                    }
                            )
                    }
                }
                .frame(height: 20)
            }
        }
    }
}

// Preview
struct StorageOptionSlider_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            StorageOptionSlider(selectedStorageIndex: .constant(3))
                .padding()
        }
        .background(OPSStyle.Colors.background)
        .preferredColorScheme(.dark)
    }
}
