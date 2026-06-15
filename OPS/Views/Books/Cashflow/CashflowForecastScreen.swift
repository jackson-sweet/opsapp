//
//  CashflowForecastScreen.swift
//  OPS
//
//  Full forecast screen. Hero number + chart + horizon toggle + layer toggles.
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                    if let r = viewModel.result {
                        header(r)
                        chartSection(r)
                        horizonToggle
                        layerToggles
                    } else if viewModel.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.top, 100)
                    } else {
                        emptyState
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, OPSStyle.Layout.spacing5)
            }
            .background(OPSStyle.Colors.background.ignoresSafeArea())
            .navigationTitle("// CASH FORECAST")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("CLOSE") { dismiss() }
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                }
            }
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
    }

    @ViewBuilder
    private func header(_ r: ForecastResult) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text(formatCurrency(r.endingBalance))
                .font(.system(size: 28, weight: .light, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(r.state == .danger ? OPSStyle.Colors.errorStatus : OPSStyle.Colors.primaryText)
            Text("LOWEST \(formatCurrency(r.lowestBalance)) · WK \(r.lowestWeekIndex + 1)")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            if let asOf = r.startingBalanceAsOf {
                Button(action: { showUpdateBalance = true }) {
                    Text("BALANCE AS OF \(formatRelative(asOf))  ·  UPDATE →")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            } else {
                Button(action: { showUpdateBalance = true }) {
                    Text("SET CURRENT BALANCE  →")
                        .font(OPSStyle.Typography.microLabel)
                        .foregroundColor(OPSStyle.Colors.warningStatus)
                }
            }
        }
    }

    private func chartSection(_ r: ForecastResult) -> some View {
        CashflowChart(result: r, onTapWeek: { selectedWeek = $0 })
            .frame(height: 200)
    }

    private var horizonToggle: some View {
        HStack(spacing: 0) {
            ForEach([4, 13], id: \.self) { weeks in
                Button(action: {
                    viewModel.setHorizon(weeks: weeks)
                    Task { await viewModel.load() }
                }) {
                    Text("\(weeks)W")
                        .font(OPSStyle.Typography.sectionLabel)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, OPSStyle.Layout.spacing2_5)
                        .foregroundColor(viewModel.result?.weeks.count == weeks ? OPSStyle.Colors.primaryText : OPSStyle.Colors.secondaryText)
                        .background(viewModel.result?.weeks.count == weeks ? OPSStyle.Colors.surfaceActive : Color.clear)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.smallCornerRadius)
                .stroke(OPSStyle.Colors.cardBackgroundDark, lineWidth: OPSStyle.Layout.Border.standard)
        )
    }

    private var layerToggles: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("LAYERS")
                .font(OPSStyle.Typography.microLabel)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            ForEach(ForecastLayer.allCases, id: \.self) { layer in
                Toggle(layer.displayName, isOn: Binding(
                    get: { viewModel.layerSet.contains(layer) },
                    set: { included in
                        viewModel.setLayer(layer, included: included)
                        Task { await viewModel.load() }
                    }
                ))
                .font(OPSStyle.Typography.sectionLabel)
                .toggleStyle(SwitchToggleStyle(tint: OPSStyle.Colors.text))
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// SET YOUR CURRENT BALANCE TO BEGIN")
                .font(OPSStyle.Typography.bodyEmphasis)
                .foregroundColor(OPSStyle.Colors.primaryText)
            Text("The forecast projects your cash position week by week. Enter your current bank balance to anchor the line.")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.secondaryText)
            Button(action: { showUpdateBalance = true }) {
                Text("SET BALANCE")
                    .font(OPSStyle.Typography.button)
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.vertical, OPSStyle.Layout.spacing2_5)
                    .background(OPSStyle.Colors.primaryAccent)
                    .foregroundColor(.black)
                    .cornerRadius(OPSStyle.Layout.buttonRadius)
            }
        }
        .padding(.top, 80)
    }

    private func formatCurrency(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: v)) ?? "$0"
    }

    private func formatRelative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date()).uppercased()
    }
}
