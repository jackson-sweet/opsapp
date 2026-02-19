//
//  OpportunityCard.swift
//  OPS
//
//  Deal card for the Pipeline Kanban — supports swipe-to-advance and swipe-to-lost.
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
                    .foregroundColor(.black)
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
                    .foregroundColor(.white)
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
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onAdvance()
                            } else if value.translation.width < -swipeThreshold && !opportunity.stage.isTerminal {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                                onLost()
                            } else {
                                withAnimation(.easeOut(duration: 0.15)) { dragOffset = 0 }
                            }
                        }
                )
        }
    }

    private var cardContent: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                HStack {
                    if opportunity.isStale {
                        Image(systemName: OPSStyle.Icons.stale)
                            .font(.system(size: 14))
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

                if let desc = opportunity.jobDescription {
                    Text(desc)
                        .font(OPSStyle.Typography.smallBody)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .lineLimit(1)
                }

                HStack {
                    stageBadge
                    Spacer()
                    Text("[\(opportunity.daysInStage == 1 ? "day 1" : "day \(opportunity.daysInStage)")]")
                        .font(OPSStyle.Typography.smallCaption)
                        .foregroundColor(OPSStyle.Colors.tertiaryText)
                }
            }
            .padding(OPSStyle.Layout.spacing3)
            .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.6))
            .cornerRadius(OPSStyle.Layout.cardCornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: OPSStyle.Layout.cardCornerRadius)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }

    private var stageBadge: some View {
        let color = OPSStyle.Colors.pipelineStageColor(for: opportunity.stage)
        return Text(opportunity.stage.displayName)
            .font(OPSStyle.Typography.smallCaption)
            .fontWeight(.medium)
            .foregroundColor(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.15))
            .overlay(
                Capsule().stroke(color, lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
