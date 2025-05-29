import SwiftUI

struct WelcomeGuideView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var currentPage = 0
    
    private let pages = WelcomeGuidePage.allPages
    
    var body: some View {
        ZStack {
            OPSStyle.Colors.background.edgesIgnoringSafeArea(.all)
            
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
    
    static let allPages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: "Welcome to Ops.",
            description: "Time to streamline your operations.\n\nMaximize your efficiency.\n\nBurn the scattered notes on your Silverado's dashboard.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "Built by trades, for trades.",
            description: "It's not just another tool.\nIt's THE tool.\n\nBuilt to solve real problems for real tradesmen, so you can focus on building, leading, and succeeding.",
            iconName: "",
            features: []
        ),
        WelcomeGuidePage(
            title: "You're all set up!",
            description: "Your company profile is ready and your team can start joining.\n\nLet's get to work.",
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
