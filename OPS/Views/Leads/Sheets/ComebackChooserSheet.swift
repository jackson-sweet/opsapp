//
//  ComebackChooserSheet.swift
//  OPS
//
//  Compact ownership + comeback chooser (Leads redesign spec §2.2) — presented
//  from the chase strip's ADJUST and from the HANDLED toast's ADJUST action.
//  Ownership can be corrected to YOUR MOVE without rewriting correspondence;
//  date rows reschedule the next touch.
//

import SwiftUI

private enum ComebackSaveTarget: Equatable {
    case ownership
    case preset(days: Int)
    case pickedDate
}

enum ComebackChooserLayoutItem: Hashable {
    case container
    case ownership
    case pickDate
}

struct ComebackChooserLayoutSnapshot {
    let container: CGRect
    let ownership: CGRect
    let pickDate: CGRect
}

private struct ComebackChooserLayoutPreferenceKey: PreferenceKey {
    static var defaultValue: [ComebackChooserLayoutItem: CGRect] = [:]

    static func reduce(
        value: inout [ComebackChooserLayoutItem: CGRect],
        nextValue: () -> [ComebackChooserLayoutItem: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct ComebackChooserSheet: View {
    let lead: Opportunity
    let viewModel: PipelineViewModel
    var layoutObserver: ((ComebackChooserLayoutSnapshot) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var showingDatePicker = false
    @State private var pickedDate =
        Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var savingTarget: ComebackSaveTarget?

    private var isSaving: Bool { savingTarget != nil }
    private var isSettingOwnership: Bool { savingTarget == .ownership }
    private static let layoutCoordinateSpace = "comeback-chooser-sheet"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionLabel("OWNERSHIP")
            ownershipRow
            divider
            sectionLabel("NEXT TOUCH")

            presetRow(label: "IN 3 DAYS", days: 3)
            divider
            presetRow(label: "IN 1 WEEK", days: 7)
            divider
            presetRow(label: "IN 2 WEEKS", days: 14)
            divider
            pickDateRow

            if showingDatePicker {
                DatePicker(
                    "",
                    selection: $pickedDate,
                    in: Date()...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(OPSStyle.Colors.opsAccent)
                .padding(.horizontal, OPSStyle.Layout.spacing2_5)

                SheetCTAButton(
                    label: "SET DATE",
                    variant: .primary,
                    isLoading: savingTarget == .pickedDate
                ) {
                    commit(pickedDate, target: .pickedDate)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            Spacer(minLength: 0)
        }
        .background(layoutProbe(.container))
        .coordinateSpace(name: Self.layoutCoordinateSpace)
        .onPreferenceChange(ComebackChooserLayoutPreferenceKey.self) { frames in
            guard
                let container = frames[.container],
                let ownership = frames[.ownership],
                let pickDate = frames[.pickDate]
            else { return }
            layoutObserver?(
                ComebackChooserLayoutSnapshot(
                    container: container,
                    ownership: ownership,
                    pickDate: pickDate
                )
            )
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents(
            showingDatePicker
                ? [.large]
                : [.medium]
        )
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(isSaving)
        .preferredColorScheme(.dark)
    }

    private func sectionLabel(_ label: String) -> some View {
        HStack(spacing: 0) {
            Text("// ").foregroundColor(OPSStyle.Colors.textMute)
            Text(label).foregroundColor(OPSStyle.Colors.text3)
        }
        .font(OPSStyle.Typography.miniLabelBold)
        .tracking(1.6)
        .textCase(.uppercase)
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.top, OPSStyle.Layout.spacing3_5)
        .padding(.bottom, OPSStyle.Layout.spacing2_5)
    }

    private var ownershipRow: some View {
        Button {
            setYourMove()
        } label: {
            HStack {
                Text("YOUR MOVE")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                if isSettingOwnership {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.text3)
                        .accessibilityHidden(true)
                } else {
                    Text("SET")
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .frame(minHeight: OPSStyle.Layout.inputHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Set lead to Your Move")
        .accessibilityValue(isSettingOwnership ? "Saving" : "")
        .background(layoutProbe(.ownership))
    }

    private var divider: some View {
        Rectangle()
            .fill(OPSStyle.Colors.lineSoft)
            .frame(height: 1)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
    }

    private func presetRow(label: String, days: Int) -> some View {
        let date = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? Date()
        return Button {
            commit(date, target: .preset(days: days))
        } label: {
            HStack {
                Text(label)
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                if savingTarget == .preset(days: days) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.text3)
                        .accessibilityHidden(true)
                } else {
                    Text(LeadChaseStrip.comebackLabel(date))
                        .font(OPSStyle.Typography.miniLabel)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .frame(minHeight: OPSStyle.Layout.inputHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("\(label), \(LeadChaseStrip.comebackLabel(date))")
    }

    private var pickDateRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(OPSStyle.Animation.curve(OPSStyle.Animation.durationHover)) {
                showingDatePicker.toggle()
            }
        } label: {
            HStack {
                Text("PICK DATE")
                    .font(OPSStyle.Typography.miniLabelBold)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.text3)
                    .rotationEffect(.degrees(showingDatePicker ? 180 : 0))
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .frame(minHeight: OPSStyle.Layout.inputHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Pick a date, \(showingDatePicker ? "expanded" : "collapsed")")
        .background(layoutProbe(.pickDate))
    }

    private func layoutProbe(_ item: ComebackChooserLayoutItem) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ComebackChooserLayoutPreferenceKey.self,
                value: [
                    item: proxy.frame(
                        in: .named(Self.layoutCoordinateSpace)
                    )
                ]
            )
        }
    }

    private func commit(_ date: Date, target: ComebackSaveTarget) {
        guard !isSaving else { return }
        savingTarget = target
        Task {
            do {
                try await viewModel.adjustComeback(opportunityId: lead.id, to: date)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                savingTarget = nil
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }

    private func setYourMove() {
        guard !isSaving else { return }
        savingTarget = .ownership
        Task {
            do {
                try await viewModel.markOperatorActionRequired(opportunityId: lead.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                savingTarget = nil
                ToastCenter.shared.present(Toast(label: Feedback.Err.saveFailed, tone: .error))
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ComebackChooserSheet") {
    Color.black.sheet(isPresented: .constant(true)) {
        ComebackChooserSheet(
            lead: Opportunity.preview(contactName: "Helen Calloway", stage: .quoted),
            viewModel: .previewLoaded()
        )
    }
}
#endif
