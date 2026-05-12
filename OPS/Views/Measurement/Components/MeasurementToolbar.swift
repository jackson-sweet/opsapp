//
//  MeasurementToolbar.swift
//  OPS
//
//  Bottom toolbar on `DimensionedAnnotationView` (spec §5.2). Six tools
//  + UNDO/REDO history buttons. Field-first: 60 pt tool height on screens
//  ≥375 pt, 50 pt on iPhone SE 1st-gen (<375 pt). No overflow menu.
//
//    [UNDO][REDO]   MEASURE   AUTO   CALIBRATE   MARK   NOTE   EXPORT
//
//  Per spec §5.2:
//    • `AUTO` is HIDDEN entirely (not greyed) when no opening detected
//      at capture — remaining 5 tools shift left to fill.
//    • `CALIBRATE` is hidden on `noDepth` capability per §3.8 truth
//      table (manual-scale-only path).
//    • `EXPORT` is disabled when `measurementsCount == 0`.
//    • Active tool: rgba(255,255,255,0.08) background, label in `text`.
//      Inactive label in `text3`.
//
//  Spec reference:
//    ops-software-bible/specs/2026-05-10-lidar-dimensioned-photo-capture-design.md §5.2
//

import SwiftUI
import UIKit

public enum MeasurementTool: String, Equatable, CaseIterable {
    case measure, auto, calibrate, mark, note, export
}

public struct MeasurementToolbarConfig: Equatable {
    public var hasAuto: Bool        // opening detected at capture
    public var hasCalibrate: Bool   // capability ≠ .noDepth
    public var canExport: Bool      // measurementsCount > 0
    public var canUndo: Bool
    public var canRedo: Bool

    public init(hasAuto: Bool, hasCalibrate: Bool, canExport: Bool,
                canUndo: Bool, canRedo: Bool) {
        self.hasAuto = hasAuto
        self.hasCalibrate = hasCalibrate
        self.canExport = canExport
        self.canUndo = canUndo
        self.canRedo = canRedo
    }
}

public struct MeasurementToolbar: View {

    @Binding public var activeTool: MeasurementTool
    public let config: MeasurementToolbarConfig
    public var onSelect: (MeasurementTool) -> Void
    public var onUndo: () -> Void
    public var onRedo: () -> Void

    public init(
        activeTool: Binding<MeasurementTool>,
        config: MeasurementToolbarConfig,
        onSelect: @escaping (MeasurementTool) -> Void,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void
    ) {
        self._activeTool = activeTool
        self.config = config
        self.onSelect = onSelect
        self.onUndo = onUndo
        self.onRedo = onRedo
    }

    public var body: some View {
        GeometryReader { geo in
            let compact = geo.size.width < 375
            HStack(spacing: compact ? 6 : 4) {
                undoButton
                redoButton
                Spacer(minLength: 8)
                ForEach(visibleTools(), id: \.self) { tool in
                    toolButton(tool, compact: compact)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 8 : 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
        }
        .frame(height: 78)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Rectangle()
                        .frame(height: 0.5)
                        .foregroundColor(OPSStyle.Colors.line),
                    alignment: .top
                )
        )
    }

    // MARK: - Tool visibility (§5.2 + §3.8)

    func visibleTools() -> [MeasurementTool] {
        var tools: [MeasurementTool] = [.measure]
        if config.hasAuto { tools.append(.auto) }
        if config.hasCalibrate { tools.append(.calibrate) }
        tools.append(.mark)
        tools.append(.note)
        tools.append(.export)
        return tools
    }

    func isDisabled(_ tool: MeasurementTool) -> Bool {
        switch tool {
        case .export: return !config.canExport
        default:      return false
        }
    }

    // MARK: - Tool button

    @ViewBuilder
    private func toolButton(_ tool: MeasurementTool, compact: Bool) -> some View {
        let active = activeTool == tool
        let disabled = isDisabled(tool)
        let size: CGFloat = compact ? 50 : 60

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeTool = tool
            onSelect(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: compact ? 20 : 22, weight: .regular))
                    .frame(width: size, height: size * 0.45)
                Text(tool.label)
                    .font(.custom("CakeMono-Light", size: compact ? 9 : 10))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(active ? OPSStyle.Colors.surfaceActive : Color.clear)
            )
            .foregroundColor(
                disabled
                    ? OPSStyle.Colors.textMute
                    : (active ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
            )
        }
        .disabled(disabled)
        .accessibilityLabel(tool.label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Undo / Redo

    private var undoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onUndo()
        } label: {
            Image(systemName: "arrow.uturn.backward")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(config.canUndo ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: 44, height: 44)
        }
        .disabled(!config.canUndo)
        .accessibilityLabel("Undo")
    }

    private var redoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRedo()
        } label: {
            Image(systemName: "arrow.uturn.forward")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(config.canRedo ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: 44, height: 44)
        }
        .disabled(!config.canRedo)
        .accessibilityLabel("Redo")
    }
}

// MARK: - Tool metadata

extension MeasurementTool {
    public var label: String {
        switch self {
        case .measure:   return "MEASURE"
        case .auto:      return "AUTO"
        case .calibrate: return "CALIBRATE"
        case .mark:      return "MARK"
        case .note:      return "NOTE"
        case .export:    return "EXPORT"
        }
    }

    public var sfSymbol: String {
        switch self {
        case .measure:   return "ruler"
        case .auto:      return "viewfinder.rectangular"
        case .calibrate: return "creditcard"
        case .mark:      return "pencil.tip"
        case .note:      return "text.bubble"
        case .export:    return "square.and.arrow.up"
        }
    }
}
