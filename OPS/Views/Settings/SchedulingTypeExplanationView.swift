//
//  SchedulingTypeExplanationView.swift
//  OPS
//
//  Explains the differences between Project-Based and Task-Based scheduling
//

import SwiftUI

struct SchedulingTypeExplanationView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            OPSStyle.Colors.backgroundGradient
                .edgesIgnoringSafeArea(.all)

            VStack(spacing: 0) {
                SettingsHeader(
                    title: "Scheduling Types",
                    onBackTapped: { dismiss() }
                )
                .padding(.bottom, 8)

                ScrollView {
                    VStack(spacing: OPSStyle.Layout.spacing4) {
                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            Text("SCHEDULING TYPES")
                                .font(OPSStyle.Typography.captionBold)
                                .foregroundColor(OPSStyle.Colors.secondaryText)

                            Text("OPS supports two different ways to schedule and manage projects. Choose the approach that best fits how you work.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineSpacing(4)
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: OPSStyle.Icons.calendar)
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                                Text("PROJECT-BASED SCHEDULING")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("BEST FOR:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                BulletPoint(text: "Projects with a single continuous timeline")
                                BulletPoint(text: "Jobs that happen all at once or over consecutive days")
                                BulletPoint(text: "Simple scheduling without breaking work into specific tasks")
                                BulletPoint(text: "Field crews who work on one project at a time")
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("HOW IT WORKS:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text("The entire project appears as a single block on the calendar. You set start and end dates for the whole project, and the team works on it during that timeframe.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineSpacing(4)
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("EXAMPLE:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text("A kitchen remodel scheduled for March 15-22. The whole project shows on the calendar for that week, and the crew knows they're working on that kitchen all week.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineSpacing(4)
                                    .italic()
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: OPSStyle.Icons.checklist)
                                    .font(.system(size: 24))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                                Text("TASK-BASED SCHEDULING")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("BEST FOR:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                BulletPoint(text: "Complex projects broken into distinct phases")
                                BulletPoint(text: "Jobs with specific tasks on different dates")
                                BulletPoint(text: "Projects where different crews handle different tasks")
                                BulletPoint(text: "Detailed scheduling and progress tracking")
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("HOW IT WORKS:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text("Each task within the project appears separately on the calendar. You schedule specific tasks for specific dates, giving you granular control over the project timeline.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                                    .lineSpacing(4)
                            }

                            Divider()
                                .background(OPSStyle.Colors.secondaryText.opacity(0.2))

                            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing2) {
                                Text("EXAMPLE:")
                                    .font(OPSStyle.Typography.captionBold)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)

                                Text("A kitchen remodel with separate tasks: Demo on March 15, Plumbing on March 16-17, Electrical on March 18, Drywall on March 19-20, and Paint on March 21-22. Each task shows individually on the calendar.")
                                    .font(OPSStyle.Typography.body)
                                    .foregroundColor(OPSStyle.Colors.secondaryText)
                                    .lineSpacing(4)
                                    .italic()
                            }
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.cardBackgroundDark)
                        .cornerRadius(OPSStyle.Layout.cornerRadius)

                        VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing3) {
                            HStack(spacing: OPSStyle.Layout.spacing2) {
                                Image(systemName: "lightbulb.fill")
                                    .font(.system(size: 20))
                                    .foregroundColor(OPSStyle.Colors.primaryAccent)

                                Text("CHOOSING YOUR APPROACH")
                                    .font(OPSStyle.Typography.bodyBold)
                                    .foregroundColor(OPSStyle.Colors.primaryText)
                            }

                            Text("You can set the scheduling type for each individual project when creating or editing it. There's no right or wrong choice—use what makes sense for how you work and the complexity of each job.")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(OPSStyle.Colors.primaryText)
                                .lineSpacing(4)
                        }
                        .padding(OPSStyle.Layout.spacing3)
                        .background(OPSStyle.Colors.primaryAccent.opacity(0.1))
                        .cornerRadius(OPSStyle.Layout.cornerRadius)
                        .overlay(
                            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                .stroke(OPSStyle.Colors.primaryAccent.opacity(0.3), lineWidth: 1)
                        )
                    }
                    .padding(OPSStyle.Layout.spacing3)
                }
            }
        }
        .navigationBarHidden(true)
    }
}

struct BulletPoint: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryAccent)

            Text(text)
                .font(OPSStyle.Typography.body)
                .foregroundColor(OPSStyle.Colors.primaryText)
                .lineSpacing(4)
        }
    }
}
