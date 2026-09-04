import Foundation

@MainActor
protocol SupplierBillIntakeServicing {
    func list(stage: SupplierBillStage?) async throws -> [SupplierBillIntake]
    func detail(intakeId: String) async throws -> SupplierBillIntakeDetail
    func capture(
        job: QueuedSupplierBillCapture,
        documentURL: URL
    ) async throws -> SupplierBillIntakeDetail
}

enum SupplierBillIntakeServiceError: Error, Equatable, LocalizedError {
    case authentication
    case invalidResponse
    case rejected(String)
    case unavailable(String)
    case identityMismatch

    var errorDescription: String? {
        switch self {
        case .authentication: return "Supplier bills require an active OPS session."
        case .invalidResponse: return "Supplier bills returned an invalid response."
        case .rejected(let message): return message
        case .unavailable(let message): return message
        case .identityMismatch: return "The supplier bill response did not match this capture."
        }
    }
}

struct SupplierBillIntakeService {
    typealias TokenProvider = () async throws -> String
    typealias RequestSender = (URLRequest) async throws -> (Data, URLResponse)

    private let baseURL: URL
    private let tokenProvider: TokenProvider
    private let requestSender: RequestSender
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(
        baseURL: URL = AppConfiguration.apiBaseURL,
        tokenProvider: @escaping TokenProvider = {
            try await FirebaseAuthService.shared.getIDToken()
        },
        requestSender: @escaping RequestSender = { request in
            try await URLSession.shared.data(for: request)
        }
    ) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
        self.requestSender = requestSender
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        encoder = JSONEncoder()
    }

    func list(stage: SupplierBillStage? = nil) async throws -> [SupplierBillIntake] {
        var components = URLComponents(url: intakesURL, resolvingAgainstBaseURL: false)
        if let stage {
            components?.queryItems = [URLQueryItem(name: "stage", value: stage.rawValue)]
        }
        guard let url = components?.url else {
            throw SupplierBillIntakeServiceError.invalidResponse
        }
        let request = try await authorizedRequest(url: url, method: "GET")
        let data = try await send(request)
        return try decode(ListResponse.self, from: data).items
    }

    func detail(intakeId: String) async throws -> SupplierBillIntakeDetail {
        let request = try await authorizedRequest(
            url: intakesURL.appendingPathComponent(intakeId),
            method: "GET"
        )
        return try decode(SupplierBillIntakeDetail.self, from: try await send(request))
    }

    func capture(
        job: QueuedSupplierBillCapture,
        documentURL: URL
    ) async throws -> SupplierBillIntakeDetail {
        let boundary = "OPS-SUPPLIER-BILL-\(UUID().uuidString.lowercased())"
        let metadata = CaptureMetadata(
            requestId: job.id,
            idempotencyKey: "capture:\(job.id)",
            documentKind: job.documentKind
        )
        let metadataData = try encoder.encode(metadata)
        let documentData = try Data(contentsOf: documentURL)

        var prepare = try await authorizedRequest(url: intakesURL, method: "POST")
        prepare.timeoutInterval = 60
        prepare.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        prepare.httpBody = multipartBody(
            boundary: boundary,
            metadata: metadataData,
            filename: job.originalFilename,
            document: documentData
        )

        let prepared = try decode(
            PreparedWrite.self,
            from: try await send(prepare)
        )
        guard prepared.preview?.requestId.lowercased() == job.id.lowercased() else {
            throw SupplierBillIntakeServiceError.identityMismatch
        }

        var commit = try await authorizedRequest(
            url: intakesURL
                .appendingPathComponent(job.id)
                .appendingPathComponent("commit"),
            method: "POST"
        )
        commit.setValue("application/json", forHTTPHeaderField: "Content-Type")
        commit.httpBody = try encoder.encode(CommitRequest(
            intentId: prepared.intentId,
            confirmationText: prepared.confirmationText
        ))
        return try decode(
            SupplierBillIntakeDetail.self,
            from: try await send(commit)
        )
    }

    private var intakesURL: URL {
        baseURL
            .appendingPathComponent("api")
            .appendingPathComponent("internal")
            .appendingPathComponent("accounting")
            .appendingPathComponent("supplier-bills")
            .appendingPathComponent("intakes")
    }

    private func authorizedRequest(url: URL, method: String) async throws -> URLRequest {
        let token: String
        do {
            token = try await tokenProvider()
        } catch {
            throw SupplierBillIntakeServiceError.authentication
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SupplierBillIntakeServiceError.authentication
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await requestSender(request)
        guard let http = response as? HTTPURLResponse else {
            throw SupplierBillIntakeServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: data).error)
                ?? "Supplier bills unavailable."
            if http.statusCode == 401 || http.statusCode == 403 {
                throw SupplierBillIntakeServiceError.authentication
            }
            if http.statusCode == 429 || http.statusCode >= 500 {
                throw SupplierBillIntakeServiceError.unavailable(message)
            }
            throw SupplierBillIntakeServiceError.rejected(message)
        }
        return data
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SupplierBillIntakeServiceError.invalidResponse
        }
    }

    private func multipartBody(
        boundary: String,
        metadata: Data,
        filename: String,
        document: Data
    ) -> Data {
        var body = Data()
        func append(_ value: String) { body.append(Data(value.utf8)) }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"metadata\"\r\n")
        append("Content-Type: application/json\r\n\r\n")
        body.append(metadata)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"document\"; filename=\"\(escapedFilename(filename))\"\r\n")
        append("Content-Type: application/pdf\r\n\r\n")
        body.append(document)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    private func escapedFilename(_ filename: String) -> String {
        URL(fileURLWithPath: filename).lastPathComponent
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
            .replacingOccurrences(of: "\r", with: "_")
            .replacingOccurrences(of: "\n", with: "_")
    }
}

extension SupplierBillIntakeService: SupplierBillIntakeServicing {}

private extension SupplierBillIntakeService {
    struct ListResponse: Decodable { let items: [SupplierBillIntake] }
    struct ErrorResponse: Decodable { let error: String }
    struct CaptureMetadata: Encodable {
        let requestId: String
        let idempotencyKey: String
        let documentKind: SupplierDocumentKind
    }
    struct CommitRequest: Encodable {
        let intentId: String
        let confirmationText: String
    }
    struct PreparedWrite: Decodable {
        struct Preview: Decodable { let requestId: String }
        let intentId: String
        let confirmationText: String
        let preview: Preview?
    }
}
