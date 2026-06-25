import Foundation

enum DeckJSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: DeckJSONValue])
    case array([DeckJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let value = try? single.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? single.decode(Double.self) {
            self = .number(value)
        } else if let value = try? single.decode(String.self) {
            self = .string(value)
        } else if let value = try? single.decode([DeckJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try single.decode([String: DeckJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var single = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try single.encode(value)
        case .number(let value):
            try single.encode(value)
        case .bool(let value):
            try single.encode(value)
        case .object(let value):
            try single.encode(value)
        case .array(let value):
            try single.encode(value)
        case .null:
            try single.encodeNil()
        }
    }
}

struct DeckDynamicCodingKey: CodingKey, Hashable {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
