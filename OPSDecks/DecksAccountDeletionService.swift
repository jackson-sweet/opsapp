import Foundation

protocol DecksAccountDeletionClient: AnyObject {
    func deleteAccount(
        _ request: DecksAccountDeletionRequest
    ) async throws -> DecksAccountDeletionReceipt
}

struct DecksAccountDeletionRequest: Encodable, Equatable {
    let firebaseUID: String
    let companyId: String

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case companyId = "company_id"
    }
}

struct DecksAccountDeletionReceipt: Decodable, Equatable {
    let receiptId: String
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case receiptId = "receipt_id"
        case deletedAt = "deleted_at"
    }
}

protocol DecksAccountDeletionTransport: AnyObject {
    func deleteAccount(_ request: DecksAccountDeletionRequest) async throws -> Data
}

final class DecksAccountDeletionService: DecksAccountDeletionClient {
    private let transport: DecksAccountDeletionTransport
    private let decoder: JSONDecoder

    init(
        transport: DecksAccountDeletionTransport,
        decoder: JSONDecoder = DecksAccountDeletionService.makeDefaultDecoder()
    ) {
        self.transport = transport
        self.decoder = decoder
    }

    func deleteAccount(
        _ request: DecksAccountDeletionRequest
    ) async throws -> DecksAccountDeletionReceipt {
        let data = try await transport.deleteAccount(request)
        return try decoder.decode(DecksAccountDeletionReceipt.self, from: data)
    }

    private static func makeDefaultDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum DecksAccountDeletionTransportError: Error, Equatable {
    case missingHTTPResponse
    case httpStatus(Int)
}

final class DecksAccountDeletionURLSessionTransport: DecksAccountDeletionTransport {
    private let endpointURL: URL
    private let accessTokenProvider: () async throws -> String
    private let dataLoader: URLSessionDataLoading
    private let encoder: JSONEncoder

    init(
        endpointURL: URL,
        accessTokenProvider: @escaping () async throws -> String,
        dataLoader: URLSessionDataLoading = URLSession.shared,
        encoder: JSONEncoder = JSONEncoder()
    ) {
        self.endpointURL = endpointURL
        self.accessTokenProvider = accessTokenProvider
        self.dataLoader = dataLoader
        self.encoder = encoder
    }

    func deleteAccount(_ request: DecksAccountDeletionRequest) async throws -> Data {
        var urlRequest = URLRequest(url: endpointURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(
            "Bearer \(try await accessTokenProvider())",
            forHTTPHeaderField: "Authorization"
        )
        urlRequest.httpBody = try encoder.encode(request)

        let (data, response) = try await dataLoader.data(for: urlRequest)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DecksAccountDeletionTransportError.missingHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DecksAccountDeletionTransportError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}

struct AccountDeletionCompanyRow: Equatable {
    let id: String
    let adminIds: [String]
    let subscriptionPlan: String
    let memberCount: Int
}

enum AccountDeletionBlockReason: Equatable {
    case upgradedOPSCompany
    case otherMembersPresent
    case userIsNotSoleAdmin
}

struct AccountDeletionPlan: Equatable {
    let softDeleteDeckIds: [String]
    let deleteCompany: Bool
    let deleteUser: Bool
    let blockedReason: AccountDeletionBlockReason?
}

struct AccountDeletionPlanner {
    func plan(
        company: AccountDeletionCompanyRow,
        userId: String,
        deckIds: [String]
    ) -> AccountDeletionPlan {
        guard company.subscriptionPlan == "decks" else {
            return blocked(.upgradedOPSCompany)
        }

        guard company.memberCount == 1 else {
            return blocked(.otherMembersPresent)
        }

        guard company.adminIds.count == 1, company.adminIds.first == userId else {
            return blocked(.userIsNotSoleAdmin)
        }

        return AccountDeletionPlan(
            softDeleteDeckIds: deckIds,
            deleteCompany: true,
            deleteUser: true,
            blockedReason: nil
        )
    }

    private func blocked(_ reason: AccountDeletionBlockReason) -> AccountDeletionPlan {
        AccountDeletionPlan(
            softDeleteDeckIds: [],
            deleteCompany: false,
            deleteUser: false,
            blockedReason: reason
        )
    }
}
