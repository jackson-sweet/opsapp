//
//  ComebackChooserSheet.swift
//  OPS
//
//  Compact comeback date chooser (Leads redesign spec §2.2) — presented from
//  the chase strip's ADJUST and from the HANDLED toast's ADJUST action.
//  Half sheet: three preset rows + PICK DATE unfolding an inline graphical
//  calendar. On pick: adjustComeback, success haptic, dismiss. Quiet by
//  design — the strip's new BACK date is the confirmation.
//

import SwiftUI

struct ComebackChooserSheet: View {
    let lead: Opportunity
    let viewModel: PipelineViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var showingDatePicker = false
    @State private var pickedDate =
        Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("// ").foregroundColor(OPSStyle.Colors.textMute)
                Text("NEXT TOUCH").foregroundColor(OPSStyle.Colors.text3)
            }
            .font(OPSStyle.Typography.miniLabelBold)
            .tracking(1.6)
            .textCase(.uppercase)
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing3_5)
            .padding(.bottom, OPSStyle.Layout.spacing2_5)

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

                SheetCTAButton(label: "SET DATE", variant: .primary, isLoading: isSaving) {
                    commit(pickedDate)
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                .padding(.bottom, OPSStyle.Layout.spacing3)
            }

            Spacer(minLength: 0)
        }
        .background(OPSStyle.Colors.background.ignoresSafeArea())
        .presentationDetents(showingDatePicker ? [.large] : [.height(280)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.dark)
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
            commit(date)
        } label: {
            HStack {
                Text(label)
                    .font(.custom("JetBrainsMono-Medium", size: 11))
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text)
                Spacer()
                Text(LeadChaseStrip.comebackLabel(date))
                    .font(OPSStyle.Typography.miniLabel)
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundColor(OPSStyle.Colors.text3)
                    .monospacedDigit()
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .frame(minHeight: 48)
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
                    .font(.custom("JetBrainsMono-Medium", size: 11))
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
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .accessibilityLabel("Pick a date, \(showingDatePicker ? "expanded" : "collapsed")")
    }

    private func commit(_ date: Date) {
        guard !isSaving else { return }
        isSaving = true
        Task {
            do {
                try await viewModel.adjustComeback(opportunityId: lead.id, to: date)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                dismiss()
            } catch {
                isSaving = false
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
