//
//  AnyJSONBridge.swift
//  OPS
//
//  One boolean-safe [String: Any] → [String: AnyJSON] conversion shared by every
//  outbound push path (DataActor and the legacy OutboundProcessor).
//
//  Push payloads are round-tripped through JSONSerialization, which represents
//  JSON true/false as CFBoolean — and CFBoolean satisfies `as? Int` with 1/0.
//  A converter that tests `Int` before CFBoolean therefore flattens every
//  boolean to a number. Native `boolean` columns coerce that back server-side,
//  so it stayed invisible; inside a `jsonb` blob it sticks and breaks strict
//  `Bool` decodes on every reader (iOS, DeckKit, web).
//
//  CFBoolean is matched first, and only first: the remaining cases keep their
//  original order (Int before Double before Bool) so an honest NSNumber integer
//  — which also satisfies `as? Bool` — still lands on `.integer`.
//

import Foundation
import Supabase

enum AnyJSONBridge {
    /// Converts a push payload dictionary to Supabase's JSON representation.
    static func payload(_ payload: [String: Any]) -> [String: AnyJSON] {
        var result: [String: AnyJSON] = [:]
        for (key, value) in payload {
            result[key] = json(value)
        }
        return result
    }

    /// Recursively converts one Swift/Foundation value to `AnyJSON`.
    static func json(_ value: Any) -> AnyJSON {
        // MUST precede the `Int` case: `NSNumber(value: true) as? Int` succeeds
        // with 1, which is exactly how every pushed boolean became a number.
        if let number = value as? NSNumber,
           CFGetTypeID(number) == CFBooleanGetTypeID() {
            return .bool(number.boolValue)
        }

        switch value {
        case let string as String:
            return .string(string)
        case let int as Int:
            return .integer(int)
        case let double as Double:
            return .double(double)
        case let bool as Bool:
            return .bool(bool)
        case let array as [Any]:
            return .array(array.map { json($0) })
        case let dict as [String: Any]:
            return .object(dict.mapValues { json($0) })
        case is NSNull:
            return .null
        default:
            // Fallback: convert to string representation
            return .string("\(value)")
        }
    }
}
