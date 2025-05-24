//
//  StorageOptionSlider.swift
//  OPS
//
//  Storage options slider with incremental values for offline caching
//

import SwiftUI

struct StorageOptionSlider: View {
    @Binding var selectedStorageIndex: Int
    
    let storageOptions: [(value: String, description: String)] = [
        ("No Storage", "Stream everything online. No offline access."),
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
                        .font(.title)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                    
                    Text(storageOptions[selectedStorageIndex].description)
                        .font(.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer()
            }
            .padding()
            .background(OPSStyle.Colors.cardBackground)
            .cornerRadius(OPSStyle.Layout.cornerRadius)
            
            // Slider
            VStack(spacing: 8) {
                // Custom slider with snap points
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Track
                        RoundedRectangle(cornerRadius: 4)
                            .fill(OPSStyle.Colors.cardBackgroundDark)
                            .frame(height: 8)
                        
                        // Fill
                        RoundedRectangle(cornerRadius: 4)
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(
                                width: geometry.size.width * CGFloat(selectedStorageIndex) / CGFloat(storageOptions.count - 1),
                                height: 8
                            )
                        
                        // Snap points
                        HStack(spacing: 0) {
                            ForEach(0..<storageOptions.count, id: \.self) { index in
                                if index > 0 {
                                    Spacer()
                                }
                                
                                Circle()
                                    .fill(index <= selectedStorageIndex ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.cardBackgroundDark)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle()
                                            .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                                    )
                                    .onTapGesture {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedStorageIndex = index
                                        }
                                    }
                                
                                if index == storageOptions.count - 1 {
                                    Spacer()
                                        .frame(width: 0)
                                }
                            }
                        }
                        
                        // Thumb
                        Circle()
                            .fill(OPSStyle.Colors.primaryAccent)
                            .frame(width: 24, height: 24)
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                            .offset(x: geometry.size.width * CGFloat(selectedStorageIndex) / CGFloat(storageOptions.count - 1) - 12)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        let newIndex = Int(round(value.location.x / geometry.size.width * CGFloat(storageOptions.count - 1)))
                                        selectedStorageIndex = max(0, min(storageOptions.count - 1, newIndex))
                                    }
                            )
                    }
                }
                .frame(height: 24)
                
                // Labels
                HStack {
                    Text(storageOptions.first?.value ?? "")
                        .font(.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                    
                    Spacer()
                    
                    Text(storageOptions.last?.value ?? "")
                        .font(.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
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