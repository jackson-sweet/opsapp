//
//  InviteModels.swift
//  OPS
//
//  DTOs for team invitation flows during onboarding.
//  Used by check_pending_invites and get_company_join_details RPCs.
//

import Foundation

// MARK: - Pending Invite DTO (from check_pending_invites RPC)

struct PendingInviteDTO: Codable, Identifiable {
    let invitationId: String
    let companyId: String
    let companyName: String
    let companyCode: String?
    let companyLogoUrl: String?
    let industries: [String]?
    let roleName: String?
    let invitedByName: String?
    let teamMembers: [TeamMemberDTO]
    let teamSize: Int
    let expiresAt: String

    var id: String { invitationId }

    enum CodingKeys: String, CodingKey {
        case invitationId = "invitation_id"
        case companyId = "company_id"
        case companyName = "company_name"
        case companyCode = "company_code"
        case companyLogoUrl = "company_logo_url"
        case industries
        case roleName = "role_name"
        case invitedByName = "invited_by_name"
        case teamMembers = "team_members"
        case teamSize = "team_size"
        case expiresAt = "expires_at"
    }
}

// MARK: - Company Join Details DTO (from get_company_join_details RPC)

struct CompanyJoinDetailsDTO: Codable {
    let companyId: String
    let companyName: String
    let companyCode: String?
    let companyLogoUrl: String?
    let industries: [String]?
    let teamMembers: [TeamMemberDTO]
    let teamSize: Int

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case companyName = "company_name"
        case companyCode = "company_code"
        case companyLogoUrl = "company_logo_url"
        case industries
        case teamMembers = "team_members"
        case teamSize = "team_size"
    }
}

// MARK: - Team Member DTO (shared by both RPCs)

struct TeamMemberDTO: Codable, Equatable {
    let firstName: String
    let lastName: String
    let profileImageUrl: String?

    var initials: String {
        let first = firstName.first.map(String.init) ?? ""
        let last = lastName.first.map(String.init) ?? ""
        return (first + last).uppercased()
    }

    enum CodingKeys: String, CodingKey {
        case firstName = "first_name"
        case lastName = "last_name"
        case profileImageUrl = "profile_image_url"
    }
}

// MARK: - Company Confirmation Source

/// Tracks how the user arrived at CompanyConfirmationScreen
/// so the back button navigates to the correct screen.
enum CompanyConfirmationSource {
    case singleInvite       // Auto-navigated (1 invite found), back → CodeEntryScreen
    case pickerSelection    // Selected from InvitePickerScreen, back → InvitePickerScreen
    case manualCodeEntry    // Entered code on CodeEntryScreen, back → CodeEntryScreen
}
