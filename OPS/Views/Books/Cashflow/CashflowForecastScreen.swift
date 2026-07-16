//
//  CashflowForecastScreen.swift
//  OPS
//
//  Full RUNWAY screen — the command-grid tile's deep-link destination.
//  Rebuilt 2026-07-01 in the grid's language: tactical full-screen header
//  (Cake Mono title + 44pt close, MOBILE.md §6.3 — no system nav chrome),
//  Mohave-Light hero with the ON TRACK / WATCH / DANGER badge, the projection
//  chart, an inset-pill horizon control, and flat hairline layer rows.
//  Tap a data point to drill into the week breakdown sheet.
//

import SwiftUI

struct CashflowForecastScreen: View {
    @ObservedObject var viewModel: CashflowForecastViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedWeek: WeeklyProjection?
    @State private var showSettings = false
    @State private var showUpdateBalance = false

    var body: some View {
        VStack(spacing: 0) {
            screenHeader

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let r = viewModel.result {
                        hero(r)
                        chartSection(r)
                            .padding(.top, OPSStyle.Layout.spacing4)
                        horizonControl
                            .padding(.top, OPSStyle.Layout.spacing4)
                        layerRows
                            .padding(.top, OPSStyle.Layout.spacing4)
                    } else if viewModel.isLoading {
                        BooksSheetSkeleton()
                            .padding(.top, OPSStyle.Layout.spacing3)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .sheet(item: $selectedWeek) { week in
            WeekBreakdownSheet(week: week)
        }
        .sheet(isPresented: $showSettings) {
            ForecastSettingsSheet(viewModel: viewModel)
        }
        .sheet(isPresented: $showUpdateBalance) {
            UpdateCurrentBalanceSheet(viewModel: viewModel)
        }
        .task { await viewModel.load() }
        .onChange(of: viewModel.result?.state) { _, newState in
            // Fire .warning haptic on the first render this session where the
            // forecast lands on .danger. Per-session flag prevents spam on
            // every refresh.
            guard !reduceMotion else { return }
            if newState == .danger && !ForecastNotificationDispatcher.sessionHasShownDipHaptic {
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
                ForecastNotificationDispatcher.sessionHasShownDipHaptic = true
            }
        }
    }

    // MARK: - Header (full-screen tactical chrome)

    private var screenHeader: some View {
        HStack(alignment: .center, spacing: OPSStyle.Layout.spacing2) {
            HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2) {
                Text("//")
                    .font(.custom("JetBrainsMono-Regular", size: 15))
                    .foregroundColor(OPSStyle.Colors.textMute)
                Text("RUNWAY")
                    .font(.custom("CakeMono-Light", size: 22))
                    .tracking(1.76)
                    .foregroundColor(OPSStyle.Colors.text)
            }
            .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Forecast settings")

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                dismiss()
            } label: {
                Image(systemName: OPSStyle.Icons.close)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundColor(OPSStyle.Colors.secondaryText)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
        .padding(.leading, OPSStyle.Layout.spacing3_5)
        .padding(.trailing, OPSStyle.Layout.spacing2)
        .padding(.top, OPSStyle.Layout.spacing2)
        .padding(.bottom, OPSStyle.Layout.spacing2)
        .overlay(alignment: .bottom) {
            Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
        }
    }

    // MARK: - Hero

    private var stateBadge: (text: String, color: Color)? {
        switch viewModel.result?.state {
        case .healthy:  return ("ON TRACK", OPSStyle.Colors.olive)
        case .lowWater: return ("WATCH", OPSStyle.Colors.tan)
        case .danger:   return ("DANGER", OPSStyle.Colors.rose)
        case nil:       return nil
        }
    }

    @ViewBuilder
    private func hero(_ r: ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing2) {
                Text("ENDING BALANCE · \(r.weeks.count)W")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(2.0)
                    .foregroundColor(OPSStyle.Colors.text3)
                Spacer(minLength: 0)
                if let badge = stateBadge {
                    BooksPillView(pill: BooksPill(text: badge.text, color: badge.color))
                }
            }

            Text(BooksFormat.currency(r.endingBalance))
                .font(.custom("Mohave-Light", size: 40))
                .foregroundColor(r.state == .danger ? OPSStyle.Colors.rose : OPSStyle.Colors.text)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .contentTransition(.numericText())
                .padding(.top, OPSStyle.Layout.spacing1 + 2)

            Text("LOW \(BooksFormat.currency(r.lowestBalance)) · WK \(r.lowestWeekIndex + 1)")
                .font(.custom("JetBrainsMono-Medium", size: 10.5))
                .tracking(0.8)
                .foregroundColor(stateBadge?.color ?? OPSStyle.Colors.text3)
                .monospacedDigit()
                .padding(.top, OPSStyle.Layout.spacing1)

            // Balance anchor — one quiet line; stale/unset pulls tan attention.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showUpdateBalance = true
            } label: {
                Group {
                    if let asOf = r.startingBalanceAsOf {
                        Text("BALANCE AS OF \(formatRelative(asOf)) · UPDATE →")
                    } else {
                        Text("SET CURRENT BALANCE →")
                    }
                }
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(1.0)
                .foregroundColor(OPSStyle.Colors.tan)
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -14)
            .padding(.top, OPSStyle.Layout.spacing2)
        }
        .padding(.top, OPSStyle.Layout.spacing3)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Chart

    private func chartSection(_ r: ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            BooksSheetSection(label: "PROJECTED BALANCE")
            CashflowChart(result: r, onTapWeek: { selectedWeek = $0 })
                .frame(height: 200)
            Text("[ TAP A WEEK FOR THE BREAKDOWN ]")
                .font(.custom("JetBrainsMono-Regular", size: 9))
                .tracking(0.9)
                .foregroundColor(OPSStyle.Colors.textMute)
        }
    }

    // MARK: - Horizon control (inset-pill segments — no accent on toggles)

    private var horizonControl: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            BooksSheetSection(label: "HORIZON")
            HStack(spacing: 2) {
                ForEach([4, 13], id: \.self) { weeks in
                    let isActive = viewModel.result?.weeks.count == weeks
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        viewModel.setHorizon(weeks: weeks)
                        Task { await viewModel.load() }
                    } label: {
                        Text("\(weeks) WEEKS")
                            .font(.custom("JetBrainsMono-Medium", size: 10.5))
                            .tracking(1.68)
                            .foregroundColor(isActive ? OPSStyle.Colors.text : OPSStyle.Colors.text3)
                            .monospacedDigit()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                Group {
                                    if isActive {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(OPSStyle.Colors.line)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 3)
                                                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                                            )
                                    }
                                }
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(weeks) week horizon\(isActive ? ", selected" : "")")
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .fill(Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                    .strokeBorder(OPSStyle.Colors.lineSoft, lineWidth: 1)
            )
        }
    }

    // MARK: - Layer rows (flat hairline rows, white toggles)

    private var layerRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            BooksSheetSection(label: "LAYERS")
                .padding(.bottom, OPSStyle.Layout.spacing1)
            ForEach(ForecastLayer.allCases, id: \.self) { layer in
                HStack(spacing: OPSStyle.Layout.spacing2) {
                    Text(layer.displayName)
                        .font(.custom("JetBrainsMono-Regular", size: 11))
                        .tracking(1.1)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                    Spacer(minLength: 0)
                    Toggle("", isOn: Binding(
                        get: { viewModel.layerSet.contains(layer) },
                        set: { included in
                            viewModel.setLayer(layer, included: included)
                            Task { await viewModel.load() }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(SwitchToggleStyle(tint: Color.white.opacity(0.25)))
                    .accessibilityLabel("\(layer.displayName) layer")
                }
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(OPSStyle.Colors.lineSoft).frame(height: 1)
                }
            }
        }
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: 0) {
            Text("—")
                .font(.custom("Mohave-Light", size: 40))
                .foregroundColor(OPSStyle.Colors.text3)
            Text("// NO BALANCE SET")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(1.6)
                .foregroundColor(OPSStyle.Colors.textMute)
                .padding(.top, OPSStyle.Layout.spacing2)
            Text("[ THE FORECAST PROJECTS YOUR CASH WEEK BY WEEK — ANCHOR IT WITH YOUR BANK BALANCE ]")
                .font(.custom("JetBrainsMono-Regular", size: 10))
                .tracking(0.4)
                .foregroundColor(OPSStyle.Colors.text3)
                .multilineTextAlignment(.center)
                .padding(.top, OPSStyle.Layout.spacing2_5)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            Button {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                showUpdateBalance = true
            } label: {
                Text("SET BALANCE")
                    .font(OPSStyle.Typography.buttonLabel)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.opsAccent)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.vertical, 11)
                    .overlay(
                        RoundedRectangle(cornerRadius: OPSStyle.Layout.buttonRadius, style: .continuous)
                            .strokeBorder(OPSStyle.Colors.opsAccent, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .padding(.top, OPSStyle.Layout.spacing3 + 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 72)
    }

    private func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date()).uppercased()
    }
}
