//
//  LeadFollowUpServiceTests.swift
//  OPSTests
//
//  Contract coverage for the authenticated one-tap lead follow-up transport.
//  The durable request key is the client-side half of at-most-once delivery:
//  ambiguous outcomes reuse it, while definitive outcomes clear it.
//

import XCTest
@testable import OPS

@MainActor
final class LeadFollowUpServiceTests: XCTestCase {
    private let opportunityId = "6bac5d9d-44c5-4af5-b36c-48beb64cbbdc"
    private let firstKey = "11111111-2222-3333-4444-555555555555"
    private let secondKey = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    func testPreviewBuildsAuthenticatedReadOnlyRequestAndDecodesServerContent() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 200,
                body: """
                {
                  "recipient": {
                    "name": "Crystal",
                    "email": "crystal@example.com"
                  },
                  "from": "office@example.com",
                  "subject": "Re: Front deck quote",
                  "body": "Hi Crystal, checking in on the quote.",
                  "previewFingerprint": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                  "templateSettingsPath": "Settings → Comms → Lifecycle"
                }
                """
            ),
        ]
        let service = makeService(
            client: client,
            keyStore: InMemoryLeadFollowUpRequestKeyStore()
        )

        let result = await service.previewFollowUp(opportunityId: opportunityId)

        guard case .ready(let preview) = result else {
            return XCTFail("Expected ready preview, got \(result)")
        }
        XCTAssertEqual(preview.recipient.name, "Crystal")
        XCTAssertEqual(preview.recipient.email, "crystal@example.com")
        XCTAssertEqual(preview.subject, "Re: Front deck quote")
        XCTAssertEqual(
            preview.previewFingerprint,
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        XCTAssertEqual(preview.templateSettingsPath, "Settings → Comms → Lifecycle")
        XCTAssertEqual(client.requests.first?.httpMethod, "GET")
        XCTAssertNil(client.requests.first?.httpBody)
        XCTAssertEqual(
            client.requests.first?.value(forHTTPHeaderField: "Authorization"),
            "Bearer firebase-token"
        )
    }

    func testReconciledSendBuildsAuthenticatedRequestDecodesCanonicalOpportunityAndClearsKey() async throws {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 200,
                body: reconciledResponse()
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case let .reconciled(opportunity, comebackAt) = result else {
            return XCTFail("Expected reconciled success, got \(result)")
        }
        XCTAssertEqual(opportunity.id, opportunityId)
        XCTAssertEqual(opportunity.handledAt, "2026-07-23T18:00:00Z")
        XCTAssertEqual(comebackAt, SupabaseDate.parse("2026-07-26T18:00:00Z"))
        XCTAssertNil(keyStore.requestKey(for: opportunityId))

        let request = try XCTUnwrap(client.requests.first)
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://example.ops/api/leads/\(opportunityId)/follow-up"
        )
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer firebase-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json, ["idempotencyKey": firstKey])
    }

    func testReviewedSendIncludesTheExactPreviewFingerprint() async throws {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(statusCode: 200, body: reconciledResponse()),
        ]
        let service = makeService(
            client: client,
            keyStore: InMemoryLeadFollowUpRequestKeyStore()
        )
        let previewFingerprint =
            "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(previewFingerprint: previewFingerprint)
        )

        let request = try XCTUnwrap(client.requests.first)
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        XCTAssertEqual(json["idempotencyKey"], firstKey)
        XCTAssertEqual(json["previewFingerprint"], previewFingerprint)
    }

    func testNetworkFailureRetainsAndReusesRequestKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .failure(URLError(.notConnectedToInternet)),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let firstResult = await service.sendFollowUp(opportunityId: opportunityId)
        guard case .networkError = firstResult else {
            return XCTFail("Expected networkError, got \(firstResult)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)

        let secondResult = await service.sendFollowUp(opportunityId: opportunityId)
        guard case .providerAcceptedPending(intentId: "intent-pending") = secondResult else {
            return XCTFail("Expected providerAcceptedPending, got \(secondResult)")
        }
        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey])
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testDeliveryUnknownRetainsRequestKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(statusCode: 202, body: unknownResponse()),
            .response(statusCode: 202, body: unknownResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let firstResult = await service.sendFollowUp(opportunityId: opportunityId)
        guard case .deliveryUnknown(intentId: "intent-unknown") = firstResult else {
            return XCTFail("Expected deliveryUnknown, got \(firstResult)")
        }

        _ = await service.sendFollowUp(opportunityId: opportunityId)

        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey])
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testBusyRetainsRequestKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"intentId":"intent-busy","reason":"mailbox_busy"}"#
            ),
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"intentId":"intent-busy","reason":"mailbox_busy"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let firstResult = await service.sendFollowUp(opportunityId: opportunityId)
        guard case .busy(intentId: "intent-busy") = firstResult else {
            return XCTFail("Expected busy, got \(firstResult)")
        }

        _ = await service.sendFollowUp(opportunityId: opportunityId)

        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey])
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testUnavailableRetainsKeySoRetryCannotCreateASecondSend() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 422,
                body: #"{"ok":false,"delivered":false,"reason":"no_safe_thread"}"#
            ),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(
            client: client,
            keyStore: keyStore,
            generatedKeys: [firstKey, secondKey]
        )

        let firstResult = await service.sendFollowUp(opportunityId: opportunityId)
        guard case .unavailable(reason: "no_safe_thread") = firstResult else {
            return XCTFail("Expected unavailable, got \(firstResult)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)

        _ = await service.sendFollowUp(opportunityId: opportunityId)

        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey])
    }

    func testThreadRequiredConflictIsUnavailableAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"reason":"LEAD_FOLLOW_UP_THREAD_REQUIRED"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .unavailable(reason: "LEAD_FOLLOW_UP_THREAD_REQUIRED") = result else {
            return XCTFail("Expected unavailable, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testResponseRequiredConflictIsUnavailableAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"reason":"RESPONSE_REQUIRED"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .unavailable(reason: "RESPONSE_REQUIRED") = result else {
            return XCTFail("Expected unavailable, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testUnsafeDraftBindingsAreUnavailableAndRetainKey() async {
        for code in [
            "LEAD_FOLLOW_UP_DRAFT_AMBIGUOUS",
            "LEAD_FOLLOW_UP_DRAFT_CONFLICT",
        ] {
            let client = LeadFollowUpHTTPClientSpy()
            client.stubs = [
                .response(
                    statusCode: 409,
                    body: #"{"ok":false,"delivered":false,"reason":"\#(code)"}"#
                ),
            ]
            let keyStore = InMemoryLeadFollowUpRequestKeyStore()
            let service = makeService(client: client, keyStore: keyStore)

            let result = await service.sendFollowUp(opportunityId: opportunityId)

            guard case .unavailable(reason: code) = result else {
                return XCTFail("Expected unavailable for \(code), got \(result)")
            }
            XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
        }
    }

    func testProviderRejectionClearsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 400,
                body: #"{"ok":false,"delivered":false,"reason":"provider_rejected"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .rejected(reason: "provider_rejected") = result else {
            return XCTFail("Expected rejected, got \(result)")
        }
        XCTAssertNil(keyStore.requestKey(for: opportunityId))
    }

    func testProviderRejectionGatewayFailureUsesErrorCodeAndPreservesReason() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 502,
                body: #"{"ok":false,"delivered":false,"error":"LEAD_FOLLOW_UP_PROVIDER_REJECTED","reason":"Mailbox provider refused the send."}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .rejected(reason: "Mailbox provider refused the send.") = result else {
            return XCTFail("Expected rejected with provider reason, got \(result)")
        }
        XCTAssertNil(keyStore.requestKey(for: opportunityId))
    }

    func testMissingSignatureIsDistinctAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 422,
                body: #"{"ok":false,"delivered":false,"reason":"signature_required"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .signatureRequired = result else {
            return XCTFail("Expected signatureRequired, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testPermissionDenialIsDistinctAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 403,
                body: #"{"ok":false,"delivered":false,"reason":"permission_denied"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .permissionDenied = result else {
            return XCTFail("Expected permissionDenied, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testMalformedSuccessIsDeliveryUnknownAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(statusCode: 200, body: #"{"ok":true}"#),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .deliveryUnknown(intentId: nil) = result else {
            return XCTFail("Expected deliveryUnknown, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testImmutableCompletedReceiptConfirmsSendWithoutApplyingAStaleOpportunity() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 200,
                body: """
                {
                  "ok": true,
                  "delivered": true,
                  "reconciliationPending": false,
                  "opportunityId": "\(opportunityId)",
                  "comebackAt": "2026-07-26T18:00:00Z",
                  "outcomeAppliedAt": "2026-07-23T18:00:01Z",
                  "notificationId": "99999999-8888-7777-6666-555555555555",
                  "intentId": "intent-reconciled"
                }
                """
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case let .reconciledReceipt(comebackAt) = result else {
            return XCTFail("Expected immutable reconciled receipt, got \(result)")
        }
        XCTAssertEqual(comebackAt, SupabaseDate.parse("2026-07-26T18:00:00Z"))
        XCTAssertNil(keyStore.requestKey(for: opportunityId))
    }

    func testIncompleteReceiptRemainsPendingAndRetainsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 200,
                body: """
                {
                  "ok": true,
                  "delivered": true,
                  "reconciliationPending": false,
                  "opportunityId": "\(opportunityId)",
                  "comebackAt": "2026-07-26T18:00:00Z",
                  "intentId": "intent-reconciled"
                }
                """
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .providerAcceptedPending(intentId: "intent-reconciled") = result else {
            return XCTFail("Expected pending for incomplete receipt, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testCompletedReceiptWithoutComebackConfirmsSendAndClearsKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 200,
                body: """
                {
                  "ok": true,
                  "delivered": true,
                  "reconciliationPending": false,
                  "opportunityId": "\(opportunityId)",
                  "outcomeAppliedAt": "2026-07-23T18:00:01Z",
                  "notificationId": "99999999-8888-7777-6666-555555555555",
                  "intentId": "intent-reconciled"
                }
                """
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .reconciledReceipt(comebackAt: nil) = result else {
            return XCTFail("Expected a completed receipt without comeback, got \(result)")
        }
        XCTAssertNil(keyStore.requestKey(for: opportunityId))
    }

    func testLostResponseThenPermissionChangeStillReusesTheOriginalKey() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .failure(URLError(.timedOut)),
            .response(
                statusCode: 403,
                body: #"{"ok":false,"delivered":false,"reason":"permission_denied"}"#
            ),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(
            client: client,
            keyStore: keyStore,
            generatedKeys: [firstKey, secondKey]
        )

        _ = await service.sendFollowUp(opportunityId: opportunityId)
        _ = await service.sendFollowUp(opportunityId: opportunityId)
        _ = await service.sendFollowUp(opportunityId: opportunityId)

        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey, firstKey])
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testCanonicalProgressIntoANewerDueCycleRotatesTheKey() async throws {
        let firstCycle = try XCTUnwrap(SupabaseDate.parse("2026-07-23T08:00:00Z"))
        let secondCycle = try XCTUnwrap(SupabaseDate.parse("2026-07-26T08:00:00Z"))
        let acceptedAt = try XCTUnwrap(SupabaseDate.parse("2026-07-23T18:00:00Z"))
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(statusCode: 202, body: pendingResponse()),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(
            client: client,
            keyStore: keyStore,
            generatedKeys: [firstKey, secondKey]
        )

        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(nextFollowUpAt: firstCycle)
        )
        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(
                nextFollowUpAt: secondCycle,
                handledAt: acceptedAt,
                lastOutboundAt: acceptedAt
            )
        )

        XCTAssertEqual(client.idempotencyKeys, [firstKey, secondKey])
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), secondKey)
    }

    func testLaterDueDateWithoutCanonicalSendProgressKeepsTheOriginalKey() async throws {
        let firstCycle = try XCTUnwrap(SupabaseDate.parse("2026-07-23T08:00:00Z"))
        let secondCycle = try XCTUnwrap(SupabaseDate.parse("2026-07-26T08:00:00Z"))
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .failure(URLError(.timedOut)),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(
            client: client,
            keyStore: keyStore,
            generatedKeys: [firstKey, secondKey]
        )

        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(nextFollowUpAt: firstCycle)
        )
        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(nextFollowUpAt: secondCycle)
        )

        XCTAssertEqual(client.idempotencyKeys, [firstKey, firstKey])
    }

    func testRequestKeysAreIsolatedByCompanyAndActor() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(statusCode: 202, body: pendingResponse()),
            .response(statusCode: 202, body: pendingResponse()),
            .response(statusCode: 202, body: pendingResponse()),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(
            client: client,
            keyStore: keyStore,
            generatedKeys: [firstKey, secondKey, "33333333-4444-5555-6666-777777777777"]
        )

        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(companyId: "company-a", actorUserId: "user-a")
        )
        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(companyId: "company-b", actorUserId: "user-a")
        )
        _ = await service.sendFollowUp(
            opportunityId: opportunityId,
            scope: testScope(companyId: "company-a", actorUserId: "user-b")
        )

        XCTAssertEqual(
            client.idempotencyKeys,
            [firstKey, secondKey, "33333333-4444-5555-6666-777777777777"]
        )
    }

    func testServerSafetyCodesAreUnavailableAndRetainTheAttempt() async {
        for code in [
            "LEAD_FOLLOW_UP_TIMEZONE_INVALID",
            "LEAD_FOLLOW_UP_CONVERSATION_CHANGED",
        ] {
            let client = LeadFollowUpHTTPClientSpy()
            client.stubs = [
                .response(
                    statusCode: 409,
                    body: #"{"ok":false,"delivered":false,"reason":"\#(code)"}"#
                ),
            ]
            let keyStore = InMemoryLeadFollowUpRequestKeyStore()
            let service = makeService(client: client, keyStore: keyStore)

            let result = await service.sendFollowUp(opportunityId: opportunityId)

            guard case .unavailable(reason: code) = result else {
                return XCTFail("Expected unavailable for \(code), got \(result)")
            }
            XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
        }
    }

    func testAlreadyInProgressIsUnresolvedAndRetainsTheAttempt() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"intentId":"intent-other-device","reason":"LEAD_FOLLOW_UP_ALREADY_IN_PROGRESS"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .alreadyInProgress(intentId: "intent-other-device") = result else {
            return XCTFail("Expected alreadyInProgress, got \(result)")
        }
        XCTAssertEqual(keyStore.requestKey(for: opportunityId), firstKey)
    }

    func testFinalProviderFreshnessRefusalClearsTheTerminalAttempt() async {
        let client = LeadFollowUpHTTPClientSpy()
        client.stubs = [
            .response(
                statusCode: 409,
                body: #"{"ok":false,"delivered":false,"definitiveNoDelivery":true,"reason":"LEAD_FOLLOW_UP_CONVERSATION_CHANGED"}"#
            ),
        ]
        let keyStore = InMemoryLeadFollowUpRequestKeyStore()
        let service = makeService(client: client, keyStore: keyStore)

        let result = await service.sendFollowUp(opportunityId: opportunityId)

        guard case .unavailable(reason: "LEAD_FOLLOW_UP_CONVERSATION_CHANGED") = result else {
            return XCTFail("Expected definitive unavailable, got \(result)")
        }
        XCTAssertNil(keyStore.requestKey(for: opportunityId))
    }

    func testUserDefaultsStorePersistsPerActorCompanyAndOpportunity() throws {
        let suiteName = "LeadFollowUpServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let firstStore = UserDefaultsLeadFollowUpRequestKeyStore(defaults: defaults)
        let stored = StoredLeadFollowUpAttempt(
            requestKey: firstKey.uppercased(),
            cycleAt: SupabaseDate.parse("2026-07-23T18:00:00Z"),
            handledAtAtCreation: nil,
            lastOutboundAtAtCreation: nil
        )
        firstStore.saveAttempt(
            stored,
            for: opportunityId.uppercased(),
            companyId: "COMPANY-ID",
            actorUserId: "USER-ID"
        )

        let secondStore = UserDefaultsLeadFollowUpRequestKeyStore(defaults: defaults)
        XCTAssertEqual(
            secondStore.attempt(
                for: opportunityId,
                companyId: "company-id",
                actorUserId: "user-id"
            ),
            stored
        )
        XCTAssertNil(
            secondStore.attempt(
                for: opportunityId,
                companyId: "other-company",
                actorUserId: "user-id"
            )
        )

        secondStore.clearAttempt(
            for: opportunityId,
            companyId: "company-id",
            actorUserId: "user-id"
        )
        XCTAssertNil(
            firstStore.attempt(
                for: opportunityId.uppercased(),
                companyId: "COMPANY-ID",
                actorUserId: "USER-ID"
            )
        )
    }

    func testReviewPreferenceIsScopedPerActorAndCompany() throws {
        let suiteName = "LeadFollowUpReviewPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UserDefaultsLeadFollowUpReviewPreferenceStore(defaults: defaults)

        XCTAssertFalse(store.skipsReview(companyId: "company-a", actorUserId: "user-a"))
        store.setSkipsReview(
            true,
            companyId: "COMPANY-A",
            actorUserId: "USER-A"
        )
        XCTAssertTrue(store.skipsReview(companyId: "company-a", actorUserId: "user-a"))
        XCTAssertFalse(store.skipsReview(companyId: "company-b", actorUserId: "user-a"))
        XCTAssertFalse(store.skipsReview(companyId: "company-a", actorUserId: "user-b"))
    }

    // MARK: - Helpers

    private func makeService(
        client: LeadFollowUpHTTPClientSpy,
        keyStore: InMemoryLeadFollowUpRequestKeyStore,
        generatedKeys: [String]? = nil
    ) -> LeadFollowUpService {
        let keys = GeneratedKeyQueue(generatedKeys ?? [firstKey])
        return LeadFollowUpService(
            baseURL: URL(string: "https://example.ops")!,
            httpClient: client,
            tokenProvider: { "firebase-token" },
            requestKeyStore: keyStore,
            requestKeyGenerator: { keys.next() }
        )
    }

    private func testScope(
        companyId: String = "company-id",
        actorUserId: String = "user-id",
        nextFollowUpAt: Date? = SupabaseDate.parse("2026-07-23T08:00:00Z"),
        handledAt: Date? = nil,
        lastOutboundAt: Date? = nil,
        previewFingerprint: String? = nil
    ) -> LeadFollowUpAttemptScope {
        LeadFollowUpAttemptScope(
            companyId: companyId,
            actorUserId: actorUserId,
            nextFollowUpAt: nextFollowUpAt,
            handledAt: handledAt,
            lastOutboundAt: lastOutboundAt,
            previewFingerprint: previewFingerprint
        )
    }

    private func reconciledResponse() -> String {
        """
        {
          "ok": true,
          "delivered": true,
          "reconciliationPending": false,
          "opportunityId": "\(opportunityId)",
          "comebackAt": "2026-07-26T18:00:00Z",
          "outcomeAppliedAt": "2026-07-23T18:00:01Z",
          "notificationId": "99999999-8888-7777-6666-555555555555",
          "intentId": "intent-reconciled",
          "opportunity": {
            "id": "\(opportunityId)",
            "company_id": "11111111-1111-1111-1111-111111111111",
            "stage": "quoted",
            "stage_entered_at": "2026-07-20T18:00:00Z",
            "next_follow_up_at": "2026-07-26T18:00:00Z",
            "handled_at": "2026-07-23T18:00:00Z",
            "created_at": "2026-07-01T18:00:00Z",
            "updated_at": "2026-07-23T18:00:00Z"
          }
        }
        """
    }

    private func pendingResponse() -> String {
        #"{"ok":true,"delivered":true,"reconciliationPending":true,"intentId":"intent-pending"}"#
    }

    private func unknownResponse() -> String {
        #"{"ok":false,"delivered":false,"deliveryUnknown":true,"intentId":"intent-unknown"}"#
    }
}

@MainActor
private final class LeadFollowUpHTTPClientSpy: LeadFollowUpHTTPClientProtocol {
    enum Stub {
        case response(statusCode: Int, body: String)
        case failure(Error)
    }

    var stubs: [Stub] = []
    private(set) var requests: [URLRequest] = []

    var idempotencyKeys: [String] {
        requests.compactMap { request in
            guard
                let body = request.httpBody,
                let json = try? JSONSerialization.jsonObject(with: body) as? [String: String]
            else {
                return nil
            }
            return json["idempotencyKey"]
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let stub = stubs.removeFirst()
        switch stub {
        case let .response(statusCode, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            return (Data(body.utf8), response)
        case let .failure(error):
            throw error
        }
    }
}

@MainActor
private final class InMemoryLeadFollowUpRequestKeyStore: LeadFollowUpRequestKeyStoring {
    private var values: [String: StoredLeadFollowUpAttempt] = [:]

    func requestKey(for opportunityId: String) -> String? {
        attempt(
            for: opportunityId,
            companyId: "company-id",
            actorUserId: "user-id"
        )?.requestKey
    }

    func attempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) -> StoredLeadFollowUpAttempt? {
        values[storageKey(
            opportunityId: opportunityId,
            companyId: companyId,
            actorUserId: actorUserId
        )]
    }

    func saveAttempt(
        _ attempt: StoredLeadFollowUpAttempt,
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) {
        values[storageKey(
            opportunityId: opportunityId,
            companyId: companyId,
            actorUserId: actorUserId
        )] = attempt
    }

    func clearAttempt(
        for opportunityId: String,
        companyId: String,
        actorUserId: String
    ) {
        values.removeValue(
            forKey: storageKey(
                opportunityId: opportunityId,
                companyId: companyId,
                actorUserId: actorUserId
            )
        )
    }

    private func storageKey(
        opportunityId: String,
        companyId: String,
        actorUserId: String
    ) -> String {
        [
            companyId,
            actorUserId,
            opportunityId,
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .joined(separator: "|")
    }
}

@MainActor
private extension LeadFollowUpService {
    func sendFollowUp(opportunityId: String) async -> LeadFollowUpResult {
        await sendFollowUp(
            opportunityId: opportunityId,
            scope: LeadFollowUpAttemptScope(
                companyId: "company-id",
                actorUserId: "user-id",
                nextFollowUpAt: SupabaseDate.parse("2026-07-23T08:00:00Z"),
                handledAt: nil,
                lastOutboundAt: nil
            )
        )
    }
}

private final class GeneratedKeyQueue {
    private var values: [String]

    init(_ values: [String]) {
        self.values = values
    }

    func next() -> String {
        values.removeFirst()
    }
}
