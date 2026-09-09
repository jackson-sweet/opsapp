import XCTest
@testable import OPS

final class AnalyticsContractTests: XCTestCase {

    private func event(id: String, name: String) -> QueuedAnalyticsEvent {
        QueuedAnalyticsEvent(
            expected_subject: "firebase-subject",
            id: id,
            event_type: "action",
            event_name: name,
            app_version: "2026.8.30",
            device_type: "iPhone",
            os_version: "18.0",
            session_id: "22222222-2222-4222-8222-222222222222",
            properties: [:],
            duration_ms: nil,
            created_at: "2026-08-30T18:00:00Z"
        )
    }

    func test_sanitizerKeepsOnlyBoundedAllowlistedNonPIIProperties() {
        let properties = AnalyticsEventContract.sanitizeProperties([
            "method": "apple",
            "team_size": 4,
            "has_schedule": true,
            "customer_email": "owner@example.com",
            "project_id": "11111111-1111-4111-8111-111111111111",
            "reason": "https://app.opsapp.co/private",
            "context": "6045550199",
            "path": "/projects/private-id",
            "action": ["nested": "value"],
            "unregistered_key": "value",
            "source": String(repeating: "x", count: 300)
        ])

        XCTAssertEqual(properties["method"], .string("apple"))
        XCTAssertEqual(properties["team_size"], .int(4))
        XCTAssertEqual(properties["has_schedule"], .bool(true))
        XCTAssertEqual(properties["source"], .string(String(repeating: "x", count: 256)))
        XCTAssertNil(properties["customer_email"])
        XCTAssertNil(properties["project_id"])
        XCTAssertNil(properties["reason"])
        XCTAssertNil(properties["context"])
        XCTAssertNil(properties["path"])
        XCTAssertNil(properties["action"])
        XCTAssertNil(properties["unregistered_key"])
    }

    func test_rpcPayloadCarriesStableVersionedEventsWithoutClientIdentity() throws {
        let event = QueuedAnalyticsEvent(
            id: "11111111-1111-4111-8111-111111111111",
            event_type: "action",
            event_name: "task_completed",
            app_version: "2026.8.30",
            device_type: "iPhone",
            os_version: "18.0",
            session_id: "22222222-2222-4222-8222-222222222222",
            properties: ["task_type": .string("install")],
            duration_ms: nil,
            schema_version: 1,
            environment: "production",
            created_at: "2026-08-30T18:00:00Z"
        )
        let request = AnalyticsAppendRPCParams(
            p_events: [event],
            p_expected_subject: "firebase-subject",
            p_schema_version: 1,
            p_environment: "production"
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        let events = try XCTUnwrap(object["p_events"] as? [[String: Any]])
        let encoded = try XCTUnwrap(events.first)

        XCTAssertEqual(object["p_expected_subject"] as? String, "firebase-subject")
        XCTAssertEqual(object["p_schema_version"] as? Int, 1)
        XCTAssertEqual(object["p_environment"] as? String, "production")
        XCTAssertEqual(encoded["id"] as? String, event.id)
        XCTAssertNil(encoded["schema_version"])
        XCTAssertNil(encoded["environment"])
        XCTAssertNil(encoded["user_id"])
        XCTAssertNil(encoded["company_id"])
        XCTAssertNil(encoded["role"])
        XCTAssertNil(encoded["plan"])
        XCTAssertNil(encoded["platform"])
        XCTAssertNil(encoded["expected_subject"])
        XCTAssertNil(encoded["is_preauth"])
    }

    func test_decodingLegacyQueuedEventDefaultsTheNewContractFields() throws {
        let legacy = """
        {
          "id":"11111111-1111-4111-8111-111111111111",
          "user_id":"33333333-3333-4333-8333-333333333333",
          "company_id":"44444444-4444-4444-8444-444444444444",
          "role":"Admin",
          "plan":"business",
          "event_type":"action",
          "event_name":"task_completed",
          "platform":"ios",
          "app_version":"2026.8.30",
          "device_type":"iPhone",
          "os_version":"18.0",
          "session_id":"22222222-2222-4222-8222-222222222222",
          "properties":{},
          "duration_ms":null,
          "created_at":"2026-08-30T18:00:00Z"
        }
        """

        let event = try JSONDecoder().decode(
            QueuedAnalyticsEvent.self,
            from: try XCTUnwrap(legacy.data(using: .utf8))
        )

        XCTAssertEqual(event.schema_version, 1)
        XCTAssertEqual(event.environment, "production")
        XCTAssertFalse(event.is_preauth)
    }

    func test_preauthEventCanBeClaimedOnceWithoutChangingItsStableIdentity() {
        let event = QueuedAnalyticsEvent(
            is_preauth: true,
            id: "11111111-1111-4111-8111-111111111111",
            event_type: "lifecycle",
            event_name: "onboarding_started",
            app_version: "2026.8.30",
            device_type: "iPhone",
            os_version: "18.0",
            session_id: "22222222-2222-4222-8222-222222222222",
            properties: [:],
            duration_ms: nil,
            created_at: "2026-08-30T18:00:00Z"
        )

        let claimed = event.claimed(by: "firebase-subject")

        XCTAssertEqual(claimed.id, event.id)
        XCTAssertEqual(claimed.session_id, event.session_id)
        XCTAssertEqual(claimed.expected_subject, "firebase-subject")
        XCTAssertFalse(claimed.is_preauth)
    }

    func test_durableQueuePreservesOrderAcrossRetryAndRecreation() throws {
        let suiteName = "AnalyticsContractTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "queue"
        let first = event(
            id: "11111111-1111-4111-8111-111111111111",
            name: "first_event"
        )
        let second = event(
            id: "33333333-3333-4333-8333-333333333333",
            name: "second_event"
        )
        let queue = AnalyticsEventQueue(queueKey: key, defaults: defaults)

        queue.enqueue(first)
        queue.enqueue(second)
        XCTAssertEqual(queue.dequeueBatch(size: 1), [first])
        queue.requeue([first])

        let recreated = AnalyticsEventQueue(queueKey: key, defaults: defaults)
        XCTAssertEqual(recreated.dequeueBatch(size: 2), [first, second])
        XCTAssertEqual(recreated.count, 0)
    }
}
