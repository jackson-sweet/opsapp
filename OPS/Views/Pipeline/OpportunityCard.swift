//
//  OpportunityCard.swift
//  OPS
//
//  Deal card for the Pipeline — left color stripe, swipe-to-advance and swipe-to-lost.
//

import SwiftUI

struct OpportunityCard: View {
    let opportunity: Opportunity
    let onTap: () -> Void
    let onAdvance: () -> Void
    let onLost: () -> Void

    @State private var dragOffset: CGFloat = 0

    private var swipeThreshold: CGFloat { 80 }

    var body: some View {
        ZStack {
            // Swipe-right reveal (advance)
            HStack {
                Label("ADVANCE", systemImage: OPSStyle.Icons.stageAdvance)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.invertedText)
                    .padding(.leading, OPSStyle.Layout.spacing3)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.successStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset > 0 ? Double(min(dragOffset / swipeThreshold, 1)) : 0)

            // Swipe-left reveal (lost)
            HStack {
                Spacer()
                Label("LOST", systemImage: OPSStyle.Icons.dealLost)
                    .font(OPSStyle.Typography.captionBold)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                    .padding(.trailing, OPSStyle.Layout.spacing3)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(OPSStyle.Colors.errorStatus)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .opacity(dragOffset < 0 ? Double(min(-dragOffset / swipeThreshold, 1)) : 0)

            // Card content
            cardContent
                .offset(x: dragOffset)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            dragOffset = value.translation.width
                        }
                        .onEnded { value in
                            if value.translation.width > swipeThreshold && !opportunity.stage.isTerminal {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                                onAdvance()
                            } else if value.translation.width < -swipeThreshold && !opportunity.stage.isTerminal {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                                onLost()
                            } else {
                                withAnimation(OPSStyle.Animation.faster) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    // MARK: - Card Content

    private var cardContent: some View {
        Button(action: onTap) {
            HStack(spacing: 0) {
                // Left color stripe
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(OPSStyle.Colors.pipelineStageColor(for: opportunity.stage))
                    .frame(width: 3)

                // Content
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    // Row 1: Contact name + value
                    HStack {
                        if opportunity.isStale {
                            Image(systemName: OPSStyle.Icons.stale)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(OPSStyle.Colors.warningStatus)
                        }
                        Text(opportunity.contactName.uppercased())
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.primaryText)
                            .lineLimit(1)
                        Spacer()
                        if let value = opportunity.estimatedValue {
                            Text(value, format: .currency(code: "USD").precision(.fractionLength(0)))
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                        }
                    }

                    // Row 2: Job description
                    if let desc = opportunity.jobDescription {
                        Text(desc)
                            .font(OPSStyle.Typography.smallBody)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                            .lineLimit(1)
                    }

                    // Row 3: Stage dot + name, days counter
                    HStack {
                        HStack(spacing: OPSStyle.Layout.spacing1) {
                            Circle()
                                .fill(OPSStyle.Colors.pipelineStageColor(for: opportunity.stage))
                                .frame(width: 6, height: 6)
                            Text(opportunity.stage.displayName)
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        Spacer()
                        Text("day \(opportunity.daysInStage)")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.tertiaryText)
                    }
                }
                .padding(.vertical, OPSStyle.Layout.spacing3)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
            }
            .background(OPSStyle.Colors.cardBackgroundDark)
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(OPSStyle.Colors.cardBorder, lineWidth: OPSStyle.Layout.Border.standard)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}
