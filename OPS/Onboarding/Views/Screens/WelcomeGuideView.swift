import SwiftUI

struct WelcomeGuideView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @EnvironmentObject var dataController: DataController
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var currentPage = 0

    private var pages: [WelcomeGuidePage] {
        // Determine user role based on user type or actual role
        if onboardingViewModel.selectedUserType == .company {
            // Business owners/crew leads see crew lead pages
            return WelcomeGuidePage.crewLeadPages
        } else {
            // Employees see employee pages
            return WelcomeGuidePage.employeePages
        }
    }

    // Determine if we should show billing page first
    private var showBillingFirst: Bool {
        // Show billing page for all users during onboarding
        return true
    }

    // Total pages including billing
    private var totalPages: Int {
        return showBillingFirst ? pages.count + 1 : pages.count
    }
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Step indicator bars at top (no skip button)
                Spacer()
                    .frame(height: 24)
                HStack(spacing: 4) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Rectangle()
                            .fill(index <= currentPage ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 40)

                // Page Content
                TabView(selection: $currentPage) {
                    // Billing page (first page for all users)
                    if showBillingFirst {
                        BillingInfoView(onContinue: {
                            withAnimation {
                                currentPage += 1
                            }
                        })
                        .tag(0)
                    }

                    // Welcome guide pages
                    ForEach(0..<pages.count, id: \.self) { index in
                        let tagIndex = showBillingFirst ? index + 1 : index
                        WelcomePageView(page: pages[index])
                            .tag(tagIndex)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                .gesture(DragGesture().onChanged({ _ in })) // Disable swipe but allow taps

                // Navigation Button - minimal style (hide on billing page)
                VStack(spacing: 24) {
                    if currentPage == 0 {
                        // Billing page - no navigation button shown (handled in BillingInfoView)
                        EmptyView()
                    } else if currentPage < totalPages - 1 {
                        Button(action: {
                            withAnimation {
                                currentPage += 1
                            }
                        }) {
                            Text("NEXT")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(OPSStyle.Colors.primaryAccent)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .stroke(OPSStyle.Colors.primaryAccent, lineWidth: 2)
                                )
                        }
                    } else {
                        Button(action: {
                            onboardingViewModel.completeOnboarding()
                        }) {
                            Text("GET STARTED")
                                .font(OPSStyle.Typography.button)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(
                                    RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                                        .fill(Color.white)
                                )
                        }
                    }
                }
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.bottom, 40)
            }
        }
    }


}

struct WelcomePageView: View {
    let page: WelcomeGuidePage
    @State private var currentScreenshot = 0

    var body: some View {
        VStack(spacing: 20) {
            // Title with square brackets and subtitle font
            Text("[\(page.title)]")
                .font(OPSStyle.Typography.subtitle)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, OPSStyle.Layout.spacing3)
                .padding(.top, 30)

            // If page has screenshots, show swipeable carousel with prev/next preview
            if !page.screenshots.isEmpty {
                VStack(spacing: 12) {
                    // Screenshot carousel with prev/next preview
                    ZStack {
                        // Previous screenshot (grayed out, smaller, left side)
                        if currentScreenshot > 0 {
                            Image(page.screenshots[currentScreenshot - 1].imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 240)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .offset(x: -140)
                        }

                        // Current screenshot (center, full size)
                        TabView(selection: $currentScreenshot) {
                            ForEach(0..<page.screenshots.count, id: \.self) { index in
                                Image(page.screenshots[index].imageName)
                                    .resizable()
                                    .aspectRatio(contentMode: .fit)
                                    .frame(maxHeight: 380)
                                    .cornerRadius(12)
                                    .tag(index)
                            }
                        }
                        .frame(height: 400)
                        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))

                        // Next screenshot (grayed out, smaller, right side)
                        if currentScreenshot < page.screenshots.count - 1 {
                            Image(page.screenshots[currentScreenshot + 1].imageName)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 120, height: 240)
                                .cornerRadius(8)
                                .opacity(0.3)
                                .offset(x: 140)
                        }
                    }

                    // Page dots
                    HStack(spacing: 6) {
                        ForEach(0..<page.screenshots.count, id: \.self) { index in
                            Circle()
                                .fill(index == currentScreenshot ? OPSStyle.Colors.primaryAccent : OPSStyle.Colors.secondaryText.opacity(0.3))
                                .frame(width: 6, height: 6)
                                .animation(.easeInOut, value: currentScreenshot)
                        }
                    }
                    .padding(.bottom, 4)

                    // Description for current screenshot - smaller font
                    Text(page.screenshots[currentScreenshot].description)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)
                        .frame(minHeight: 60)
                        .animation(.easeInOut, value: currentScreenshot)
                }
            } else {
                // Original layout for pages without screenshots
                VStack(spacing: 30) {
                    Spacer()

                    Text(page.description)
                        .font(OPSStyle.Typography.body)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(5)
                        .padding(.horizontal, OPSStyle.Layout.spacing3)

                    Spacer()
                    Spacer()
                }
            }

            Spacer()
        }
    }
}

struct WelcomeGuidePage {
    let title: String
    let description: String
    let iconName: String
    let features: [String]
    let screenshots: [ScreenshotInfo]

    init(title: String, description: String, iconName: String = "", features: [String] = [], screenshots: [ScreenshotInfo] = []) {
        self.title = title
        self.description = description
        self.iconName = iconName
        self.features = features
        self.screenshots = screenshots
    }

    // Pages for employees
    static let employeePages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: " YOUR PROJECTS ",
            description: "See assigned jobs.\nMark projects complete.\nAdd photos and notes from the field.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: " WORKS OFFLINE ",
            description: "No signal required.\nUpdates your progress when you're back online.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: " KEEP IT SIMPLE ",
            description: "Designed for simplicity.\nTested for reliability.",
            iconName: "",
            features: []
        )
    ]
    
    // Pages for crew leads / business owners
    static let crewLeadPages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: " TRACK PROJECTS ",
            description: "Monitor job progress.\nView team assignments.\nUpdate from field."
        ),
        WelcomeGuidePage(
            title: " TAKE CONTROL ",
            description: "All the functionality you need, anywhere you need it. Offline, in the mud, OPS is your wingman. Create jobs, clients, tasks, update assignments. All in your pocket."
        ),
        WelcomeGuidePage(
            title: " TASK-BASED WORKFLOWS ",
            description: "",
            screenshots: [
                ScreenshotInfo(imageName: "Group 12", description: "Create tasks or projects directly from the job board. Organize work by trade or phase."),
                ScreenshotInfo(imageName: "Group 10", description: "Detailed task view showing location, client, dates, team members, and notes. Update status from the field."),
                ScreenshotInfo(imageName: "Group 11", description: "Calendar auto-populated with tasks and projects. Color coded by type. Pinch to expand/minimize rows."),
                ScreenshotInfo(imageName: "Group 13", description: "Month view for high-level overview. Pinch to expand days or minimize for compact view.")
            ]
        ),
        WelcomeGuidePage(
            title: "JOB BOARD",
            description: "",
            screenshots: [
                ScreenshotInfo(imageName: "Group 15", description: "Drag projects left or right to move between workflow stages. Simple gestures for fast management."),
                ScreenshotInfo(imageName: "Group 14", description: "All clients in one list with active project counts, color coded by status. Long-press for quick actions."),
                ScreenshotInfo(imageName: "Group 3", description: "Swipe project or task cards to advance status. From In Progress to Complete in one gesture.")
            ]
        )
    ]
}

struct ScreenshotInfo {
    let imageName: String
    let description: String
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()

    WelcomeGuideView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
        .environmentObject(SubscriptionManager.shared)
}
