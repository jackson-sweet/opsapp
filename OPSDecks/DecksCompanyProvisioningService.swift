import Foundation

protocol DecksCompanyProvisioningClient: AnyObject {
    func provisionCompany(
        _ request: DecksCompanyProvisioningRequest
    ) async throws -> DecksCompanyProvisioningResponse
}

struct DecksCompanyProvisioningRequest: Encodable, Equatable {
    let firebaseUID: String
    let email: String
    let displayName: String?
    let sourceApp: String = "ops_decks"

    enum CodingKeys: String, CodingKey {
        case firebaseUID = "firebase_uid"
        case email
        case displayName = "display_name"
        case sourceApp = "source_app"
    }
}

struct DecksCompanyProvisioningResponse: Decodable, Equatable {
    let companyId: String
    let userId: String
    let role: String
    let subscriptionPlan: String

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case userId = "user_id"
        case role
        case subscriptionPlan = "subscription_plan"
    }
}

protocol DecksCompanyProvisioningTransport: AnyObject {
    func provisionCompany(_ request: DecksCompanyProvisioningRequest) async throws -> Data
}

final class DecksCompanyProvisioningService: DecksCompanyProvisioningClient {
    private let transport: DecksCompanyProvisioningTransport
    private let decoder: JSONDecoder

    init(
        transport: DecksCompanyProvisioningTransport,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.transport = transport
        self.decoder = decoder
    }

    func provisionCompany(
        _ request: DecksCompanyProvisioningRequest
    ) async throws -> DecksCompanyProvisioningResponse {
        let data = try await transport.provisionCompany(request)
        return try decoder.decode(DecksCompanyProvisioningResponse.self, from: data)
    }
}

enum DecksCompanyProvisioningTransportError: Error, Equatable {
    case missingHTTPResponse
    case httpStatus(Int)
}

protocol URLSessionDataLoading: AnyObject {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionDataLoading {}

final class DecksCompanyProvisioningURLSessionTransport: DecksCompanyProvisioningTransport {
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

    func provisionCompany(_ request: DecksCompanyProvisioningRequest) async throws -> Data {
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
            throw DecksCompanyProvisioningTransportError.missingHTTPResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw DecksCompanyProvisioningTransportError.httpStatus(httpResponse.statusCode)
        }
        return data
    }
}
