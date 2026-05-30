//
//  ExportSheet.swift
//  OPS
//
//  Bottom sheet for the EXPORT tool action on `DimensionedAnnotationView`
//  (spec §5.2 Export flow). Two rows:
//
//    SAVE TO PROJECT    — uploads as project_photos row (default action)
//    EXPORT PDF          — generates single-page PDF, opens system share sheet
//
//  Direct "save to Photos library" is deferred per spec (would require
//  NSPhotoLibraryAddUsageDescription).
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2 §3.7
//

import SwiftUI
import UIKit

public struct ExportSheet: View {

    public var onSaveToProject: () -> Void
    public var onExportPDF: () -> Void
    public var onCancel: () -> Void

    public init(onSaveToProject: @escaping () -> Void,
                onExportPDF: @escaping () -> Void,
                onCancel: @escaping () -> Void) {
        self.onSaveToProject = onSaveToProject
        self.onExportPDF = onExportPDF
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("// EXPORT")
                .font(.custom("CakeMono-Light", size: 14))
                .tracking(1)
                .foregroundColor(OPSStyle.Colors.text)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            row(symbol: "tray.and.arrow.down",
                title: "SAVE TO PROJECT",
                isDefault: true,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSaveToProject()
                })
                .accessibilityIdentifier("export.saveToProject")

            Divider()
                .background(OPSStyle.Colors.line)
                .padding(.horizontal, 12)

            row(symbol: "doc.richtext",
                title: "EXPORT PDF",
                isDefault: false,
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onExportPDF()
                })
                .accessibilityIdentifier("export.pdf")

            Button {
                onCancel()
            } label: {
                Text("CANCEL")
                    .font(.custom("CakeMono-Light", size: 13))
                    .tracking(1)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
        .presentationDetents([.height(260)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func row(symbol: String, title: String, isDefault: Bool,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundColor(isDefault ? OPSStyle.Colors.opsAccent : OPSStyle.Colors.text)
                    .frame(width: 28, height: 28)
                Text(title)
                    .font(.custom("CakeMono-Light", size: 14))
                    .tracking(1)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                Image("ops.chevron-right")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.text3)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
