//
//  DimensionedAnnotationView.swift
//  OPS
//
//  Phase D STUB — the real implementation is Phase E (§5.2 of the design
//  spec). This placeholder exists so `DimensionedCaptureView` has a typed
//  destination to dismiss-to in flow tests, and so the capture pipeline can
//  be exercised end-to-end before the annotation surface ships.
//
//  When Phase E lands, replace the body with the real measurement tool /
//  Hover-style label rendering / accuracy badge / export sheet UI per §5.2.
//

import SwiftUI

public struct DimensionedAnnotationView: View {

    /// The freshly captured asset triple. Phase E will consume these to seed
    /// the annotation view's initial state (HEIC for the photo, depth + sidecar
    /// for measurements). Phase D doesn't read them — placeholder only.
    public let assets: CapturedAssets

    @Environment(\.dismiss) private var dismiss

    public init(assets: CapturedAssets) {
        self.assets = assets
    }

    public var body: some View {
        ZStack {
            OPSStyle.Colors.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                Text("// PHASE E · TBD")
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundColor(OPSStyle.Colors.text)

                Text("DimensionedAnnotationView lands in Phase E. The capture pipeline saved \(assetSummary).")
                    .font(.smallBody)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                Button("DISMISS") { dismiss() }
                    .font(.buttonLabel)
                    .textCase(.uppercase)
                    .tracking(0.5)
                    .foregroundColor(OPSStyle.Colors.text)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(OPSStyle.Colors.surfaceActive)
                    .clipShape(RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius))
                    .frame(minHeight: 60)
            }
            .padding()
        }
    }

    private var assetSummary: String {
        let id = assets.captureID.uuidString.prefix(8)
        return "capture \(id)"
    }
}
