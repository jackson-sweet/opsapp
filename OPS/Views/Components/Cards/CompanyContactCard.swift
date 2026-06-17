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

    private let logoSize: CGFloat = 56

    var body: some View {
        HStack(spacing: OPSStyle.Layout.spacing2_5) {
            // Logo on the left as a circle
            logoView

            // Text content
            VStack(alignment: .leading, spacing: OPSStyle.Layout.spacing1) {
                // Company name
                Text(name.isEmpty ? "COMPANY NAME" : name.uppercased())
                    .font(OPSStyle.Typography.bodyBold)
                    .foregroundColor(name.isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.primaryText)
                    .lineLimit(1)

                // Email
                if !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactRow(icon: "envelope", text: email)
                }

                // Phone
                if !phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    contactRow(icon: "phone", text: phone)
                }

                // Team member count
                if showTeamCount {
                    HStack(spacing: OPSStyle.Layout.spacing1) {
                        Image(systemName: "person.2")
                            .font(.system(size: OPSStyle.Layout.IconSize.xs))
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                        Text("\(teamMemberCount) TEAM MEMBER\(teamMemberCount == 1 ? "" : "S")")
                            .font(OPSStyle.Typography.smallCaption)
                            .foregroundColor(OPSStyle.Colors.secondaryText)
                    }
                }
            }

            Spacer()
        }
        .padding(.vertical, 14)
        .padding(.horizontal, OPSStyle.Layout.spacing3)
        .glassSurface()
    }

    // MARK: - Contact Row

    private func contactRow(icon: String, text: String, isEmpty: Bool = false) -> some View {
        HStack(spacing: OPSStyle.Layout.spacing1) {
            Image(systemName: icon)
                .font(.system(size: OPSStyle.Layout.IconSize.xs))
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
            Text(text)
                .font(OPSStyle.Typography.smallCaption)
                .foregroundColor(isEmpty ? OPSStyle.Colors.tertiaryText : OPSStyle.Colors.secondaryText)
                .lineLimit(1)
        }
    }

    // MARK: - Logo View

    @ViewBuilder
    private var logoView: some View {
        if let image = logoImage {
            // Custom image provided
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: logoSize, height: logoSize)
                .clipShape(Circle())
        } else if let data = logoData, let uiImage = UIImage(data: data) {
            // Logo from data
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: logoSize, height: logoSize)
                .clipShape(Circle())
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
                        .frame(width: logoSize, height: logoSize)
                        .clipShape(Circle())
                default:
                    logoPlaceholder
                }
            }
        } else if !name.isEmpty {
            // Show initial if name exists but no logo
            Circle()
                .fill(OPSStyle.Colors.primaryAccent)
                .frame(width: logoSize, height: logoSize)
                .overlay(
                    Text(String(name.prefix(1)).uppercased())
                        .font(.avatarInitials(size: logoSize * 0.4))
                        .foregroundColor(OPSStyle.Colors.primaryText)
                )
        } else {
            logoPlaceholder
        }
    }

    private var logoPlaceholder: some View {
        Circle()
            .fill(OPSStyle.Colors.background)
            .frame(width: logoSize, height: logoSize)
            .overlay(
                Image(systemName: "building.2")
                    .font(.system(size: logoSize * 0.4))
                    .foregroundColor(OPSStyle.Colors.tertiaryText)
            )
            .overlay(
                Circle()
                    .stroke(OPSStyle.Colors.inputFieldBorder, lineWidth: OPSStyle.Layout.Border.standard)
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
    init(company: Company, teamCount: Int? = nil, showTeamCount: Bool = true) {
        self.name = company.name
        self.logoURL = company.logoURL
        self.logoData = company.logoData
        self.logoImage = nil
        self.email = company.email ?? ""
        self.phone = company.phone ?? ""
        self.address = company.address ?? ""
        self.website = company.website ?? ""
        self.teamMemberCount = teamCount ?? 0
        self.showTeamCount = showTeamCount
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        OPSStyle.Colors.background
            .ignoresSafeArea()

        VStack(spacing: OPSStyle.Layout.spacing3_5) {
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
