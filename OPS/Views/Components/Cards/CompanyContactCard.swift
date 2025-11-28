//
//  CompanyContactCard.swift
//  OPS
//
//  Company contact preview card matching the ClientSheet pattern
//

import SwiftUI

struct CompanyContactCard: View {
    // Required fields
    let name: String
    let logoURL: String?
    let logoData: Data?
    let logoImage: UIImage?

    // Optional fields with defaults
    var email: String = ""
    var phone: String = ""
    var address: String = ""
    var website: String = ""
    var teamMemberCount: Int = 0

    // Display options
    var showTeamCount: Bool = true
    // Note: Company code moved to OrganizationDetailsView as a separate copyable field

    @State private var textHeight: CGFloat = 100

    var body: some View {
        ZStack(alignment: .trailing) {
            // Logo positioned on the right, sized to match text height
            HStack {
                Spacer()
                logoView(height: textHeight)
            }

            // Text content with gradient background for readability over logo
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    // Company name
                    Text(name.isEmpty ? "COMPANY NAME" : name.uppercased())
                        .font(OPSStyle.Typography.bodyBold)
                        .foregroundColor(name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                        .lineLimit(1)

                    // Primary contact (email or phone)
                    if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        contactRow(icon: "envelope", text: email)
                    } else {
                        contactRow(icon: "envelope", text: "NO EMAIL", isEmpty: true)
                    }

                    if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        contactRow(icon: "phone", text: phone)
                    } else {
                        contactRow(icon: "phone", text: "NO PHONE", isEmpty: true)
                    }

                    // Address
                    let formattedAddress = formatAddress(address)
                    contactRow(
                        icon: "mappin.circle",
                        text: formattedAddress.isEmpty ? "NO ADDRESS" : formattedAddress,
                        isEmpty: formattedAddress.isEmpty
                    )

                    // Website
                    if !website.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        contactRow(icon: "globe", text: website)
                    } else {
                        contactRow(icon: "globe", text: "NO WEBSITE", isEmpty: true)
                    }

                    // Team member count
                    if showTeamCount {
                        HStack(spacing: 4) {
                            Image(systemName: "person.2")
                                .font(.system(size: 11))
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                            Text("\(teamMemberCount) TEAM MEMBER\(teamMemberCount == 1 ? "" : "S")")
                                .font(OPSStyle.Typography.smallCaption)
                                .foregroundColor(OPSStyle.Colors.secondaryText)
                        }
                        .padding(.top, 2)
                    }
                }
                .padding(.trailing, 16)
                Spacer(minLength: 0)
            }
            .background(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            OPSStyle.Colors.cardBackgroundDark.opacity(1),
                            OPSStyle.Colors.cardBackgroundDark.opacity(0.7),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .onAppear { 
                        textHeight = geo.size.height
                    }
                    .onChange(of: geo.size.height) { _, newHeight in
                        textHeight = newHeight
                    }
                }
            )
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(OPSStyle.Colors.cardBackgroundDark.opacity(0.7))
        .cornerRadius(OPSStyle.Layout.cornerRadius)
        .overlay(
            RoundedRectangle(cornerRadius: OPSStyle.Layout.cornerRadius)
                .stroke(OPSStyle.Colors.cardBorder, lineWidth: 1)
        )
    }

    // MARK: - Contact Row

    private func contactRow(icon: String, text: String, isEmpty: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
            Text(text)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Logo View

    @ViewBuilder
    private func logoView(height: CGFloat) -> some View {
        if let image = logoImage {
            // Custom image provided
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: height, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let data = logoData, let uiImage = UIImage(data: data) {
            // Logo from data
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: height, height: height)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        } else if let urlString = logoURL,
                  !urlString.isEmpty,
                  let url = normalizedLogoURL(urlString) {
            // Logo from URL
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: height, height: height)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                default:
                    logoPlaceholder(height: height)
                }
            }
        } else if !name.isEmpty {
            // Show initial if name exists but no logo
            RoundedRectangle(cornerRadius: 10)
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: height, height: height)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.custom("Mohave-Bold", size: height * 0.4))
                        .foregroundColor(.white)
                )
        } else {
            logoPlaceholder(height: height)
        }
    }

    private func logoPlaceholder(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(OPSStyle.Colors.cardBackgroundDark)
            .frame(width: height, height: height)
            .overlay(
                Image(systemName: "building.2")
                    .font(.system(size: height * 0.4))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
    }

    // MARK: - Helpers

    /// Normalizes logo URL by adding https: scheme for protocol-relative URLs
    private func normalizedLogoURL(_ urlString: String) -> URL? {
        // Fix protocol-relative URLs (//domain.com -> https://domain.com)
        let fixedURLString = urlString.hasPrefix("//") ? "https:\(urlString)" : urlString
        return URL(string: fixedURLString)
    }

    private func formatAddress(_ address: String) -> String {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        // Return first line of address (street + city typically)
        let components = trimmed.components(separatedBy: ",")
        if components.count >= 2 {
            let street = components[0].trimmingCharacters(in: .whitespaces)
            let city = components[1].trimmingCharacters(in: .whitespaces)
            return "\(street), \(city)"
        }
        return components.first?.trimmingCharacters(in: .whitespaces) ?? trimmed
    }
}

// MARK: - Convenience initializer for Company model

extension CompanyContactCard {
    init(company: Company, showTeamCount: Bool = true) {
        self.name = company.name
        self.logoURL = company.logoURL
        self.logoData = company.logoData
        self.logoImage = nil
        self.email = company.email ?? ""
        self.phone = company.phone ?? ""
        self.address = company.address ?? ""
        self.website = company.website ?? ""
        self.teamMemberCount = company.teamMembers.count
        self.showTeamCount = showTeamCount
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack(spacing: 20) {
            // With data
            CompanyContactCard(
                name: "ABC Construction",
                logoURL: nil,
                logoData: nil,
                logoImage: nil,
                email: "info@abcconstruction.com",
                phone: "(555) 123-4567",
                address: "123 Main Street, Denver, CO 80202",
                website: "www.abcconstruction.com",
                teamMemberCount: 12
            )

            // Without data
            CompanyContactCard(
                name: "",
                logoURL: nil,
                logoData: nil,
                logoImage: nil,
                email: "",
                phone: "",
                address: "",
                website: "",
                teamMemberCount: 0
            )
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}
