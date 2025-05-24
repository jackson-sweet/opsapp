import SwiftUI

struct WelcomeGuideView: View {
    @EnvironmentObject var onboardingViewModel: OnboardingViewModel
    @State private var currentPage = 0
    @State private var dragOffset: CGFloat = 0
    
    private let pages = WelcomeGuidePage.allPages
    
    var body: some View {
        VStack(spacing: 0) {
            OnboardingHeader(
                title: "Welcome to OPS",
                subtitle: "Step 6 of 6",
                showBackButton: true,
                onBack: {
                    onboardingViewModel.previousStep()
                }
            )
            
            VStack(spacing: 32) {
                // Page Indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? Color("AccentPrimary") : Color("StatusInactive"))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut(duration: 0.3), value: currentPage)
                    }
                }
                .padding(.top, 24)
                
                // Page Content
                TabView(selection: $currentPage) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        WelcomePageView(page: pages[index])
                            .tag(index)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentPage)
                
                Spacer()
                
                // Navigation Buttons
                VStack(spacing: 16) {
                    if currentPage < pages.count - 1 {
                        Button(action: {
                            withAnimation {
                                currentPage += 1
                            }
                        }) {
                            HStack {
                                Text("Next")
                                    .font(OPSStyle.Typography.bodyBold)
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color("AccentPrimary"))
                            )
                        }
                    } else {
                        Button(action: {
                            onboardingViewModel.completeOnboarding()
                        }) {
                            HStack {
                                Text("Get Started")
                                    .font(OPSStyle.Typography.bodyBold)
                                Spacer()
                                Image(systemName: "checkmark")
                                    .font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color("AccentPrimary"))
                            )
                        }
                    }
                    
                    if currentPage > 0 {
                        Button(action: {
                            withAnimation {
                                currentPage -= 1
                            }
                        }) {
                            Text("Previous")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(Color("TextSecondary"))
                        }
                    } else {
                        Button(action: {
                            onboardingViewModel.completeOnboarding()
                        }) {
                            Text("Skip guide")
                                .font(OPSStyle.Typography.body)
                                .foregroundColor(Color("TextSecondary"))
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 34)
            }
        }
        .background(Color("Background"))
    }
}

struct WelcomePageView: View {
    let page: WelcomeGuidePage
    
    var body: some View {
        VStack(spacing: 32) {
            // Icon/Image Area
            ZStack {
                Circle()
                    .fill(Color("AccentPrimary").opacity(0.1))
                    .frame(width: 120, height: 120)
                
                Image(systemName: page.iconName)
                    .font(.system(size: 48, weight: .light))
                    .foregroundColor(Color("AccentPrimary"))
            }
            
            VStack(spacing: 16) {
                Text(page.title)
                    .font(OPSStyle.Typography.title)
                    .foregroundColor(Color("TextPrimary"))
                    .multilineTextAlignment(.center)
                
                Text(page.description)
                    .font(OPSStyle.Typography.body)
                    .foregroundColor(Color("TextSecondary"))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            
            if !page.features.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(page.features, id: \.self) { feature in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Color("AccentPrimary"))
                                .font(.system(size: 16))
                                .offset(y: 2)
                            
                            Text(feature)
                                .font(OPSStyle.Typography.caption)
                                .foregroundColor(Color("TextPrimary"))
                                .multilineTextAlignment(.leading)
                            
                            Spacer()
                        }
                    }
                }
                .padding(20)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color("CardBackground"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color("StatusInactive").opacity(0.3), lineWidth: 1)
                        )
                )
            }
            
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

struct WelcomeGuidePage {
    let title: String
    let description: String
    let iconName: String
    let features: [String]
    
    static let allPages: [WelcomeGuidePage] = [
        WelcomeGuidePage(
            title: "Welcome to Your Company Dashboard",
            description: "You're all set up! Your company profile is ready and your team can start joining.",
            iconName: "building.2",
            features: [
                "Manage projects and track progress",
                "Coordinate with your team members",
                "View real-time project updates",
                "Access financial summaries"
            ]
        ),
        WelcomeGuidePage(
            title: "Project Management Made Simple",
            description: "Track all your projects in one place with real-time updates and seamless team coordination.",
            iconName: "list.clipboard",
            features: [
                "Create and assign projects",
                "Track project status and progress",
                "Share updates with clients",
                "Manage project timelines"
            ]
        ),
        WelcomeGuidePage(
            title: "Team Collaboration",
            description: "Your team members will receive their invitations soon. Once they join, you'll see them here.",
            iconName: "person.3",
            features: [
                "Invite unlimited team members",
                "Real-time location tracking",
                "Instant messaging and updates",
                "Role-based permissions"
            ]
        ),
        WelcomeGuidePage(
            title: "Stay Connected on the Go",
            description: "Access everything you need from anywhere. Your team stays connected whether they're in the office or in the field.",
            iconName: "location",
            features: [
                "GPS tracking for field teams",
                "Offline capability",
                "Push notifications",
                "Mobile-first design"
            ]
        )
    ]
}

#Preview {
    WelcomeGuideView()
        .environmentObject(OnboardingViewModel())
}