//
//  MeasurementToolbar.swift
//  OPS
//
//  Bottom toolbar on `DimensionedAnnotationView` (spec §5.2). History controls
//  + visible measurement tools. Field-first: every visible control keeps a
//  minimum 44 pt touch target on iPhone widths. No overflow menu.
//
//    [UNDO][REDO]
//    [MEASURE] [AUTO] [CALIBRATE] [EXPORT]
//
//  Per spec §5.2:
//    • `AUTO` is HIDDEN entirely (not greyed) when no opening detected
//      at capture — remaining 5 tools shift left to fill.
//    • `CALIBRATE` is hidden on `noDepth` capability per §3.8 truth
//      table (manual-scale-only path).
//    • `MARK` and `NOTE` stay hidden until this feature can persist/export
//      their output safely.
//    • `EXPORT` is hidden when `measurementsCount == 0`.
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
    public var hasAuto: Bool         // opening detected at capture
    public var hasCalibrate: Bool    // capability ≠ .noDepth
    public var canExport: Bool       // measurementsCount > 0
    public var canUndo: Bool
    public var canRedo: Bool
    public var showsMark: Bool       // hidden until persisted/exported
    public var showsNote: Bool       // hidden until implemented

    public init(hasAuto: Bool, hasCalibrate: Bool, canExport: Bool,
                canUndo: Bool, canRedo: Bool,
                showsMark: Bool = false, showsNote: Bool = false) {
        self.hasAuto = hasAuto
        self.hasCalibrate = hasCalibrate
        self.canExport = canExport
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.showsMark = showsMark
        self.showsNote = showsNote
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
            let tools = visibleTools()
            let metrics = MeasurementToolbarLayout.metrics(
                width: geo.size.width,
                toolCount: tools.count
            )

            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                HStack(spacing: 8) {
                    undoButton
                    redoButton
                    Spacer(minLength: 0)
                }
                .frame(height: MeasurementToolbarLayout.historyButtonSize)

                HStack(spacing: metrics.toolSpacing) {
                    ForEach(tools, id: \.self) { tool in
                        toolButton(tool, metrics: metrics)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, metrics.horizontalPadding)
            .padding(.vertical, metrics.verticalPadding)
            .frame(maxWidth: .infinity)
        }
        .frame(height: MeasurementToolbarLayout.toolbarHeight)
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
        if config.showsMark { tools.append(.mark) }
        if config.showsNote { tools.append(.note) }
        if config.canExport { tools.append(.export) }
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
    private func toolButton(_ tool: MeasurementTool,
                            metrics: MeasurementToolbarLayout.Metrics) -> some View {
        let active = activeTool == tool
        let disabled = isDisabled(tool)
        let size = metrics.toolSize

        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            activeTool = tool
            onSelect(tool)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tool.sfSymbol)
                    .font(.system(size: metrics.iconSize, weight: .regular))
                    .frame(width: size, height: size * 0.45)
                Text(tool.label)
                    .font(.custom("CakeMono-Light", size: metrics.labelSize))
                    .tracking(0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
            }
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardRadius)
                    .fill(active ? OPSStyle.Colors.surfaceActive : Color.clear)
            )
            .foregroundColor(
                disabled
                    ? OPSStyle.Colors.textMute
                    : (active ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
            )
        }
        .disabled(disabled)
        .buttonStyle(.plain)
        .accessibilityLabel(tool.label)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Undo / Redo

    private var undoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onUndo()
        } label: {
            Image("ops.undo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(config.canUndo ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: 44, height: 44)
        }
        .disabled(!config.canUndo)
        .buttonStyle(.plain)
        .accessibilityLabel("Undo")
    }

    private var redoButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onRedo()
        } label: {
            Image("ops.redo")
                .font(.system(size: 18, weight: .regular))
                .foregroundColor(config.canRedo ? OPSStyle.Colors.text : OPSStyle.Colors.textMute)
                .frame(width: 44, height: 44)
        }
        .disabled(!config.canRedo)
        .buttonStyle(.plain)
        .accessibilityLabel("Redo")
    }
}

// MARK: - Layout

enum MeasurementToolbarLayout {
    static let historyButtonSize: CGFloat = 44
    static let toolbarHeight: CGFloat = 126

    struct Metrics {
        let toolSize: CGFloat
        let toolSpacing: CGFloat
        let rowSpacing: CGFloat
        let horizontalPadding: CGFloat
        let verticalPadding: CGFloat

        var compact: Bool { toolSize < 56 }
        var iconSize: CGFloat { compact ? 18 : 22 }
        var labelSize: CGFloat { compact ? 9 : 10 }
    }

    static func metrics(width: CGFloat, toolCount: Int) -> Metrics {
        let compact = width < 375
        let horizontalPadding: CGFloat = compact ? 8 : 12
        let toolSpacing: CGFloat = compact ? 6 : 8
        let preferredToolSize: CGFloat = compact ? 50 : 60
        let count = max(toolCount, 1)
        let availableWidth = max(0, width - (horizontalPadding * 2))
        let totalSpacing = CGFloat(count - 1) * toolSpacing
        let maxToolSize = floor((availableWidth - totalSpacing) / CGFloat(count))
        let toolSize = max(44, min(preferredToolSize, maxToolSize))

        return Metrics(
            toolSize: toolSize,
            toolSpacing: toolSpacing,
            rowSpacing: 6,
            horizontalPadding: horizontalPadding,
            verticalPadding: 8
        )
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
