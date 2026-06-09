//
//  GuidedSetupSurveyView.swift
//  OPS
//
//  The plain-language diagnostic survey. One question per screen, tap to answer
//  and advance, back to revise. On completion it hands the finished
//  BusinessProfile to the model, which moves the flow to the plan phase.
//  Self-contained flow styling (steel-blue primaryAccent) — not the overlay
//  Wizard System.
//

import SwiftUI

struct GuidedSetupSurveyView: View {
    @ObservedObject var model: GuidedCatalogSetupModel
    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    @State private var answers = SurveyAnswers()
    @State private var current: SurveyQuestionID = SurveyFlow.firstQuestion
    @State private var history: [SurveyQuestionID] = []

    var body: some View {
        let q = SurveyFlow.content(current)
        ScrollView {
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                header(eyebrow: q.eyebrow, prompt: q.prompt)

                VStack(spacing: OPSStyle.Layout.spacing2) {
                    ForEach(q.options) { option in
                        optionCard(option)
                    }
                }

                if !history.isEmpty {
                    backButton
                }
            }
            .padding(.horizontal, OPSStyle.Layout.spacing3)
            .padding(.top, OPSStyle.Layout.spacing3)
            .padding(.bottom, OPSStyle.Layout.spacing4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(transition)
            .animation(flowAnimation, value: current)
        }
    }

    private func header(eyebrow: String, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
            Text("// \(eyebrow)")
                .font(OPSStyle.Typography.metadata)
                .foregroundColor(OPSStyle.Colors.tertiaryText)
            Text(prompt)
                .font(OPSStyle.Typography.pageTitle)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func optionCard(_ option: SurveyOption) -> some View {
        Button {
            select(option)
        } label: {
            HStack(alignment: .top, spacing: OPSStyle.Layout.spacing3) {
                VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                    Text(option.label)
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(OPSStyle.Colors.primaryText)
                        .multilineTextAlignment(.leading)
                    Text(option.sublabel)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: OPSStyle.Layout.spacing2)
                Image(systemName: OPSStyle.Icons.chevronRight)
                    .font(.system(size: OPSStyle.Layout.IconSize.sm, weight: .semibold))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            }
            .padding(OPSStyle.Layout.spacing3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .nestedCard()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.label)
        .accessibilityHint(option.sublabel)
    }

    private var backButton: some View {
        Button {
            goBack()
        } label: {
            HStack(spacing: OPSStyle.Layout.spacing1) {
                Image(systemName: "chevron.left")
                    .font(.system(size: OPSStyle.Layout.IconSize.xs, weight: .semibold))
                Text("BACK")
                    .font(OPSStyle.Typography.metadata)
            }
            .foregroundColor(OPSStyle.Colors.secondaryText)
            .frame(minHeight: OPSStyle.Layout.touchTargetMin)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Go back to the previous question")
    }

    private func select(_ option: SurveyOption) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        var updated = answers
        SurveyFlow.apply(option.value, to: &updated)
        answers = updated

        if let next = SurveyFlow.next(after: current, answers: updated) {
            history.append(current)
            withAnimation(flowAnimation) { current = next }
        } else if let profile = SurveyFlow.finalize(updated) {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            model.completeSurvey(with: profile)
        }
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(flowAnimation) { current = previous }
    }

    private var flowAnimation: SwiftUI.Animation {
        reducedMotion ? .linear(duration: 0.15) : OPSStyle.Animation.page
    }

    private var transition: AnyTransition {
        reducedMotion
            ? .opacity
            : .asymmetric(insertion: .opacity.combined(with: .move(edge: .trailing)),
                          removal: .opacity.combined(with: .move(edge: .leading)))
    }
}

#Preview {
    ZStack {
        OPSStyle.Colors.backgroundGradient.ignoresSafeArea()
        GuidedSetupSurveyView(model: GuidedCatalogSetupModel(companyId: "preview", userId: "preview"))
    }
}
