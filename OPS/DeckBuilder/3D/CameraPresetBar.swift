// OPS/OPS/DeckBuilder/3D/CameraPresetBar.swift

import SwiftUI

struct CameraPresetBar: View {
    let onPreset: (CameraPreset) -> Void

    var body: some View {
        HStack(spacing: 16) {
            ForEach(CameraPreset.allCases) { preset in
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPreset(preset)
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: preset.iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        Text(preset.displayName)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetMin)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OPSStyle.Colors.cardBackground)
    }
}
