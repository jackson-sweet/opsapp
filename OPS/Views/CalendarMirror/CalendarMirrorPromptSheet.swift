//
//  CalendarMirrorPromptSheet.swift
//  OPS
//
//  First-event-save explainer for the iPhone Calendar Mirror feature.
//  Shown at most once per install; gated on hasShownPrompt UserDefault.
//

import SwiftUI

struct CalendarMirrorPromptSheet: View {
    @Binding var isPresented: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("// MIRROR TO iPHONE CALENDAR")
                .font(OPSStyle.Typography.captionBold)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .padding(.top, 32)

            Text("See your OPS schedule alongside your personal calendar. One-way: edits in OPS, sync to your phone.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack(spacing: 12) {
                Button {
                    Task { await dismissNotNow() }
                } label: {
                    Text("NOT NOW")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(OPSStyle.Colors.separator, lineWidth: 1)
                        )
                }
                .disabled(isWorking)

                Button {
                    Task { await enableMirror() }
                } label: {
                    Text(isWorking ? "WORKING…" : "ENABLE")
                        .font(OPSStyle.Typography.bodyBold)
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .foregroundColor(.white)
                        .background(OPSStyle.Colors.opsAccent)
                        .cornerRadius(8)
                }
                .disabled(isWorking)
            }
            .padding(.bottom, 24)
        }
        .padding(.horizontal, 24)
        .background(OPSStyle.Colors.backgroundGradient.ignoresSafeArea())
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func enableMirror() async {
        isWorking = true
        defer { isWorking = false }
        CalendarMirrorService.shared.hasShownPrompt = true
        do {
            try await CalendarMirrorService.shared.enable()
        } catch {
            // Silent — Settings card surfaces failure state.
        }
        isPresented = false
    }

    @MainActor
    private func dismissNotNow() async {
        CalendarMirrorService.shared.hasShownPrompt = true
        isPresented = false
    }
}
