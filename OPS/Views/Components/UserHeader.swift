//
//  UserHeader.swift
//  OPS
//
//  Created by Jackson Sweet on 2025-04-23.
//


import SwiftUI

struct UserHeader: View {
    @EnvironmentObject private var dataController: DataController
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text("Good Morning, \(dataController.currentUser?.firstName ?? "User")")
                    .font(OPSStyle.Typography.subtitle)
                    .foregroundColor(OPSStyle.Colors.primaryText)
                
                if let company = dataController.getCurrentUserCompany() {
                    Text(company.name.uppercased())
                        .font(OPSStyle.Typography.caption)
                        .foregroundColor(OPSStyle.Colors.secondaryText)
                }
            }
            
            Spacer()
            
            // User profile image
            if let imageData = dataController.currentUser?.profileImageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 50, height: 50)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 50, height: 50)
                    .overlay(
                        Text(dataController.currentUser?.firstName.prefix(1) ?? "U")
                            .foregroundColor(OPSStyle.Colors.primaryText)
                    )
            }
        }
        .padding()
        .background(OPSStyle.Colors.background.opacity(0.7))
    }
}