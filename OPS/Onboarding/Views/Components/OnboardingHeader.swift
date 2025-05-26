import SwiftUI

struct OnboardingHeader: View {
    let title: String
    let subtitle: String
    let showBackButton: Bool
    let onBack: () -> Void
    
    init(title: String, subtitle: String, showBackButton: Bool = true, onBack: @escaping () -> Void = {}) {
        self.title = title
        self.subtitle = subtitle
        self.showBackButton = showBackButton
        self.onBack = onBack
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
                
                Spacer()
                    .frame(width: 24)
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
    OnboardingHeader(
        title: "Company Address",
        subtitle: "Step 2 of 6",
        showBackButton: true,
        onBack: {}
    )
}