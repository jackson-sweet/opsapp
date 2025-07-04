import SwiftUI

struct WelcomeGuideView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @EnvironmentObject var dataController: DataController
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
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Minimal header with skip
                HStack {
                    Spacer()
                    Button(action: {
                        onboardingViewModel.completeOnboarding()
                    }) {
                        Text("Skip")
                            .font(OPSStyle.Typography.body)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 8)
                
                // Step indicator bars at top
                HStack(spacing: 4) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Rectangle()
                            .fill(index <= currentPage ? OPSStyle.Colors.primaryAccent : Color.gray.opacity(0.3))
                            .frame(height: 2)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
                
                // Page Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        WelcomePageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                
                // Navigation Button - minimal style
                VStack(spacing: 24) {
                    if currentPage < pages.count - 1 {
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
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }


}

struct WelcomePageView: View {
    let page: WelcomeGuidePage
    
    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            
            // Larger title text
            Text(page.title)
                .font(OPSStyle.Typography.largeTitle)
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            
            // Larger description text
            Text(page.description)
                .font(OPSStyle.Typography.cardTitle)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(6)
                .padding(.horizontal, 24)
            
            Spacer()
            Spacer()
        }
    }
}

struct WelcomeGuidePage {
    let title: String
    let description: String
    let iconName: String
    let features: [String]
    
    // Pages for employees
    static let employeePages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: "YOUR PROJECTS.",
            description: "See assigned jobs.\nMark projects complete.\nAdd photos and notes from the field.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "WORKS OFFLINE.",
            description: "No signal required.\nUpdates your progress when you're back online.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "NOTHING FANCY.",
            description: "Designed for simplicity.\nTested for reliability.",
            iconName: "",
            features: []
        )
    ]
    
    // Pages for crew leads / business owners
    static let crewLeadPages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: "TRACK PROJECTS",
            description: "Monitor job progress.\nView team assignments.\nUpdate from field.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "TAKE CONTROL.",
            description: "Use the OPS website to create, assign and schedule.\nUse the mobile app to add photos, notes and track progress.\nEverything you need.\nNothing you don't.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "VERSION 2 IS COMING.",
            description: "V2 update brings in-app project creation, crew management, advanced scheduling and more.",
            iconName: "",
            features: []
        )
    ]
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    WelcomeGuideView()
        .environmentObject(OnboardingViewModel())
        .environmentObject(dataController)
}
