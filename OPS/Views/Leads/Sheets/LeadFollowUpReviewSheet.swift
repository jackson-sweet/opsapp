//
//  LeadFollowUpReviewSheet.swift
//  OPS
//
//  Provider-fresh review of the exact stock follow-up the server will send.
//  Previewing is read-only; delivery remains an explicit second commit.
//

import SwiftUI

struct LeadFollowUpReviewSheet: View {
    let preview: LeadFollowUpPreview
    @Binding var skipReviewNextTime: Bool
    let onCancel: () -> Void
    let onSend: () -> Void

    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header

                ScrollView {
                    VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                        addressingCard
                        messageCard
                        templateNote
                        reviewPreference
                    }
                }
                .scrollIndicators(.hidden)

                footer
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3_5)
            .padding(.top, OPSStyle.Layout.spacing2)
            .padding(.bottom, OPSStyle.Layout.spacing4)
        }
        .preferredColorScheme(.dark)
        .opsSheet(detents: [.large])
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            HStack(spacing: OPSStyle.Layout.spacing2) {
                SheetTitleLabel(title: "FOLLOW-UP REVIEW", size: .half)
                SheetCloseButton(action: onCancel)
            }

            Text("// CONFIRM THE MESSAGE BEFORE DELIVERY")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .textCase(.uppercase)
        }
    }

    private var addressingCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2_5) {
            reviewRow(
                label: "TO",
                value: recipientDisplay,
                accessibilityValue: "Recipient \(recipientDisplay)"
            )
            Divider().overlay(OPSStyle.Colors.line)
            reviewRow(
                label: "FROM",
                value: preview.from,
                accessibilityValue: "From \(preview.from)"
            )
        }
        .padding(OPSStyle.Layout.spacing3)
        .background(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cardRadius,
                style: .continuous
            )
            .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cardRadius,
                style: .continuous
            )
            .strokeBorder(
                OPSStyle.Colors.nestedBorder,
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// SUBJECT")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(preview.subject)
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(OPSStyle.Colors.text)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(OPSStyle.Colors.line)

            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("// MESSAGE")
                    .font(OPSStyle.Typography.metadata)
                    .foregroundColor(OPSStyle.Colors.text3)
                Text(preview.body)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(OPSStyle.Colors.text2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(OPSStyle.Layout.spacing3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cardRadius,
                style: .continuous
            )
            .fill(OPSStyle.Colors.surfaceInput)
        )
        .overlay(
            RoundedRectangle(
                cornerRadius: OPSStyle.Layout.cardRadius,
                style: .continuous
            )
            .strokeBorder(
                OPSStyle.Colors.nestedBorder,
                lineWidth: OPSStyle.Layout.Border.standard
            )
        )
    }

    private var templateNote: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            Text("// COMPANY TEMPLATE")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
            Text(preview.templateSettingsPath)
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.opsAccent)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Customize the company template in \(preview.templateSettingsPath)"
        )
    }

    private var reviewPreference: some View {
        Toggle(isOn: $skipReviewNextTime) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                Text("SKIP REVIEW NEXT TIME")
                    .font(OPSStyle.Typography.buttonLabel)
                    .foregroundColor(OPSStyle.Colors.text)
                Text("A hold will send the current company template.")
                    .font(OPSStyle.Typography.smallBody)
                    .foregroundColor(OPSStyle.Colors.text3)
            }
        }
        .tint(OPSStyle.Colors.opsAccent)
        .frame(minHeight: OPSStyle.Layout.touchTargetMin)
    }

    private var footer: some View {
        SheetFooterButtonRow {
            SheetCTAButton(
                label: "CANCEL",
                variant: .secondary,
                action: onCancel
            )
        } primary: {
            SheetCTAButton(
                label: "SEND FOLLOW-UP",
                action: onSend
            )
        }
    }

    private var recipientDisplay: String {
        guard
            let name = preview.recipient.name?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !name.isEmpty
        else {
            return preview.recipient.email
        }
        return "\(name) · \(preview.recipient.email)"
    }

    private func reviewRow(
        label: String,
        value: String,
        accessibilityValue: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OPSStyle.Layout.spacing2_5) {
            Text("// \(label)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.text3)
                .frame(minWidth: OPSStyle.Layout.touchTargetMin, alignment: .leading)
            Text(value)
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(OPSStyle.Colors.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityValue)
    }
}
