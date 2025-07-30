//
//  CategoryCard.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-05-14.
//

import SwiftUI
// Add UIKit for full compatibility
import UIKit

/// A reusable card component for displaying category items consistently throughout the app
struct CategoryCard: View {
    var title: String
    var description: String
    var iconName: String
    var isDisabled: Bool = false
    var comingSoon: Bool = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Icon in colored circle
            ZStack {
                /*
                RoundedRectangle(cornerRadius: 5)
                    .stroke(isDisabled ? OPSStyle.Colors.tertiaryText.opacity(0.3) : OPSStyle.Colors.primaryText)
                    .frame(width: 40, height: 40)
                */
                Image(systemName: iconName)
                    .font(.system(size: 24, weight: .light))
                    .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
            }.frame(width: 30)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center){
                    Text(title.uppercased())
                        .font(OPSStyle.Typography.cardTitle)
                        .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : .white)
                    
                    if comingSoon {
                        Text("COMING SOON")
                            .font(OPSStyle.Typography.smallCaption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(Color.black)
                            .foregroundColor(OPSStyle.Colors.primaryAccent)
                            .cornerRadius(OPSStyle.Layout.cornerRadius)
                    }
                }
                
                Text(description)
                    .font(OPSStyle.Typography.cardBody)
                    .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(OPSStyle.Typography.smallBody)
                .foregroundColor(isDisabled ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
        }
        .padding(24)
        .background(isDisabled ? OPSStyle.Colors.cardBackgroundDark.opacity(0.3) : OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

// SettingsSectionHeader moved to SettingsComponents.swift to avoid duplicate declaration

/// A standardized organization profile card component
struct OrganizationProfileCard: View {
    var company: Company
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 16) {
                // Logo/icon - using unified CompanyAvatar component
                CompanyAvatar(company: company, size: 60)
                
                VStack(alignment: .leading, spacing: 6) {
                    // Company name
                    Text(company.name)
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(.white)
                    
                    // Email if available
                    if let email = company.email, !email.isEmpty {
                        Text(email)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                    
                    // Business hours if available
                    if company.openHour != nil && company.closeHour != nil {
                        Text(company.hoursDisplay)
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
                
                Spacer()
            }
        }
        .padding(16)
        .background(OPSStyle.Colors.cardBackgroundDark)
        .cornerRadius(OPSStyle.Layout.cornerRadius)
    }
}

struct CategoryCardPreview: View {
    var body: some View {
        VStack(spacing: 20) {
            CategoryCard(
                title: "App Settings",
                description: "Manage app preferences",
                iconName: "gear"
            )
            
            CategoryCard(
                title: "Expenses",
                description: "Track expenses and materials costs",
                iconName: "dollarsign.circle",
                isDisabled: true,
                comingSoon: true
            )
            
            // Section header removed to avoid reference to removed component
            Text("APP SETTINGS")
                .font(OPSStyle.Typography.caption)
                .foregroundColor(OPSStyle.Colors.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .padding()
        .background(OPSStyle.Colors.backgroundGradient)
        .preferredColorScheme(.dark)
    }
}

#if swift(>=5.9)
#Preview {
    CategoryCardPreview()
}
#else
struct CategoryCardPreview_Previews: PreviewProvider {
    static var previews: some View {
        CategoryCardPreview()
    }
}
#endif
