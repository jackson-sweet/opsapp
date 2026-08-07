//
//  LeadAttachmentsSheet.swift
//  OPS
//
//  Compact lead-file browser. Lead Details shows one attachment count; this
//  sheet carries the filenames, provenance, and MIME-aware thumbnails.
//

import SwiftUI

struct LeadAttachmentsSheet: View {
    let attachments: [LeadAttachment]
    let onSelect: (LeadAttachment) async -> Void

    @State private var openingAttachmentID: String?

    var body: some View {
        ZStack(alignment: .top) {
            OPSStyle.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                            attachmentRow(attachment, position: index + 1)
                            if index < attachments.count - 1 {
                                Rectangle()
                                    .fill(OPSStyle.Colors.lineSoft)
                                    .frame(height: OPSStyle.Layout.Border.standard)
                                    .padding(
                                        .leading,
                                        OPSStyle.Layout.spacing3
                                            + OPSStyle.Layout.touchTargetMin
                                            + OPSStyle.Layout.spacing2_5
                                    )
                            }
                        }
                    }
                    .commandCard()
                    .padding(.horizontal, OPSStyle.Layout.spacing3_5)
                    .padding(.bottom, OPSStyle.Layout.spacing4)
                }
                .scrollIndicators(.hidden)
            }
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(openingAttachmentID != nil)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
            SheetTitleLabel(title: "ATTACHMENTS", size: .half)
            Text(LeadAttachmentPresentation.summary(count: attachments.count).uppercased())
                .font(OPSStyle.Typography.miniLabel)
                .kerning(OPSStyle.Typography.trackingStandard)
                .foregroundColor(OPSStyle.Colors.text3)
        }
        .padding(.horizontal, OPSStyle.Layout.spacing3_5)
        .padding(.vertical, OPSStyle.Layout.spacing2)
    }

    private func attachmentRow(_ attachment: LeadAttachment, position: Int) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            guard openingAttachmentID == nil else { return }
            openingAttachmentID = attachment.id
            Task {
                await onSelect(attachment)
                if openingAttachmentID == attachment.id {
                    openingAttachmentID = nil
                }
            }
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing2_5) {
                LeadAttachmentPreview(
                    attachment: attachment,
                    maxPixelSize: OPSStyle.Layout.touchTargetMin * UIScreen.main.scale
                )
                .frame(
                    width: OPSStyle.Layout.touchTargetMin,
                    height: OPSStyle.Layout.touchTargetMin
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: OPSStyle.Layout.buttonRadius,
                        style: .continuous
                    )
                    .strokeBorder(
                        OPSStyle.Colors.line,
                        lineWidth: OPSStyle.Layout.Border.standard
                    )
                }

                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(attachment.displayName)
                        .font(OPSStyle.Typography.bodyEmphasis)
                        .foregroundColor(OPSStyle.Colors.text)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(meta(for: attachment))
                        .font(OPSStyle.Typography.miniLabel)
                        .kerning(OPSStyle.Typography.trackingCompact)
                        .foregroundColor(OPSStyle.Colors.text3)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .textCase(.uppercase)
                }

                Spacer(minLength: 0)

                if openingAttachmentID == attachment.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(OPSStyle.Colors.text3)
                } else {
                    Image(systemName: OPSStyle.Icons.chevronRight)
                        .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .regular))
                        .foregroundColor(OPSStyle.Colors.textMute)
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .frame(minHeight: OPSStyle.Layout.touchTargetStandard)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(openingAttachmentID != nil)
        .accessibilityLabel(
            "\(attachment.displayName), \(meta(for: attachment)), attachment \(position) of \(attachments.count)"
        )
        .accessibilityHint("Opens attachment")
    }

    private func meta(for attachment: LeadAttachment) -> String {
        var parts: [String] = []
        if let sender = attachment.fromEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !sender.isEmpty {
            parts.append(sender)
        }
        if let date = attachment.date {
            parts.append(Self.dateFormatter.string(from: date))
        }
        return parts.isEmpty ? attachment.ingestStatus : parts.joined(separator: " · ")
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter
    }()
}
