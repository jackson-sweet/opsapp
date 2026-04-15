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
                    VStack(spacing: 3) {
                        Image(systemName: preset.iconName)
                            .font(.system(size: OPSStyle.Layout.IconSize.md, weight: .medium))
                            .foregroundColor(OPSStyle.Colors.primaryAccent)

                        Text(preset.displayName)
                            .font(OPSStyle.Typography.miniLabel)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    .frame(width: OPSStyle.Layout.touchTargetStandard, height: OPSStyle.Layout.touchTargetMin)
                }
            }
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .padding(.vertical, OPSStyle.Layout.spacing2)
        .background(OPSStyle.Colors.cardBackground)
    }
}
