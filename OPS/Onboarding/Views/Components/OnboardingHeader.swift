import SwiftUI

struct OnboardingHeader: View {
    let title: String
    let subtitle: String
    let showBackButton: Bool
    let showLogoutButton: Bool
    let onBack: () -> Void
    let onLogout: () -> Void
    
    init(title: String, subtitle: String, showBackButton: Bool = true, showLogoutButton: Bool = false, onBack: @escaping () -> Void = {}, onLogout: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.showBackButton = showBackButton
        self.showLogoutButton = showLogoutButton
        self.onBack = onBack
        self.onLogout = onLogout
    }
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if showBackButton {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(Color("TextPrimary"))
                    }
                } else {
                    Spacer()
                        .frame(width: 24)
                }
                
                Spacer()
                
                VStack(spacing: 4) {
                    Text(title)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(Color("TextPrimary"))
                    
                    Text(subtitle)
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(Color("TextSecondary"))
                }
                
                Spacer()
                
                if showLogoutButton {
                    Button(action: onLogout) {
                        Text("Sign Out")
                            .font(OPSStyle.Typography.bodyBold)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                    }
                } else {
                    Spacer()
                        .frame(width: 24)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            
            Divider()
                .background(Color("StatusInactive").opacity(0.3))
        }
        .background(Color("Background"))
    }
}

#Preview {
    let dataController = OnboardingPreviewHelpers.createPreviewDataController()
    
    OnboardingHeader(
        title: "Company Address",
        subtitle: "Step 2 of 6",
        showBackButton: true,
        onBack: {}
    )
    .environmentObject(dataController)
}