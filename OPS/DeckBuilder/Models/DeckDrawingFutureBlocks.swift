import Foundation

enum DeckJSONValue: Equatable {
    case string(String)
    case number(String)
    case bool(Bool)
    case object([String: DeckJSONValue])
    case array([DeckJSONValue])
    case null

    static func parseObject(from json: String) throws -> [String: DeckJSONValue] {
        var parser = DeckJSONParser(json: json)
        let value = try parser.parseValue()
        try parser.finish()
        guard case .object(let object) = value else {
            throw DeckJSONValueError.expectedObject
        }
        return object
    }

    func renderedJSONString() throws -> String {
        try DeckJSONRenderer.render(self)
    }

    var isValidJSONObject: Bool {
        switch self {
        case .string, .bool, .null:
            return true
        case .number(let token):
            return Self.isValidJSONNumberToken(token)
        case .object(let object):
            return object.values.allSatisfy(\.isValidJSONObject)
        case .array(let array):
            return array.allSatisfy(\.isValidJSONObject)
        }
    }

    private static func isValidJSONNumberToken(_ token: String) -> Bool {
        token.range(
            of: #"^-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?$"#,
            options: .regularExpression
        ) != nil
    }
}

enum DeckJSONValueError: Error {
    case expectedObject
    case invalidJSONNumber(String)
    case invalidLiteral(Int)
    case invalidUnicodeEscape(Int)
    case unexpectedCharacter(Int)
    case unexpectedEndOfInput
}

private struct DeckJSONParser {
    private let scalars: [UnicodeScalar]
    private var index: Int = 0

    init(json: String) {
        scalars = Array(json.unicodeScalars)
    }

    mutating func parseValue() throws -> DeckJSONValue {
        skipWhitespace()
        guard let scalar = current else {
            throw DeckJSONValueError.unexpectedEndOfInput
        }

        switch scalar {
        case "\"":
            return .string(try parseString())
        case "{":
            return .object(try parseObject())
        case "[":
            return .array(try parseArray())
        case "t":
            try consumeLiteral("true")
            return .bool(true)
        case "f":
            try consumeLiteral("false")
            return .bool(false)
        case "n":
            try consumeLiteral("null")
            return .null
        case "-", "0"..."9":
            return .number(try parseNumberToken())
        default:
            throw DeckJSONValueError.unexpectedCharacter(index)
        }
    }

    mutating func finish() throws {
        skipWhitespace()
        guard current == nil else {
            throw DeckJSONValueError.unexpectedCharacter(index)
        }
    }

    private mutating func parseObject() throws -> [String: DeckJSONValue] {
        try consume("{")
        skipWhitespace()
        if current == "}" {
            advance()
            return [:]
        }

        var object: [String: DeckJSONValue] = [:]
        while true {
            skipWhitespace()
            guard current == "\"" else {
                throw DeckJSONValueError.unexpectedCharacter(index)
            }
            let key = try parseString()

            skipWhitespace()
            try consume(":")
            let value = try parseValue()
            object[key] = value

            skipWhitespace()
            guard let scalar = current else {
                throw DeckJSONValueError.unexpectedEndOfInput
            }
            if scalar == "}" {
                advance()
                return object
            }
            try consume(",")
        }
    }

    private mutating func parseArray() throws -> [DeckJSONValue] {
        try consume("[")
        skipWhitespace()
        if current == "]" {
            advance()
            return []
        }

        var array: [DeckJSONValue] = []
        while true {
            array.append(try parseValue())
            skipWhitespace()
            guard let scalar = current else {
                throw DeckJSONValueError.unexpectedEndOfInput
            }
            if scalar == "]" {
                advance()
                return array
            }
            try consume(",")
        }
    }

    private mutating func parseString() throws -> String {
        try consume("\"")
        var result = String()

        while let scalar = current {
            advance()
            switch scalar {
            case "\"":
                return result
            case "\\":
                guard let escaped = current else {
                    throw DeckJSONValueError.unexpectedEndOfInput
                }
                advance()
                switch escaped {
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/": result.append("/")
                case "b": result.append("\u{08}")
                case "f": result.append("\u{0C}")
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "u":
                    result.append(try parseUnicodeScalar())
                default:
                    throw DeckJSONValueError.unexpectedCharacter(index - 1)
                }
            default:
                result.unicodeScalars.append(scalar)
            }
        }

        throw DeckJSONValueError.unexpectedEndOfInput
    }

    private mutating func parseUnicodeScalar() throws -> String {
        let first = try parseHexQuad()
        if (0xD800...0xDBFF).contains(first) {
            let checkpoint = index
            guard current == "\\" else {
                throw DeckJSONValueError.invalidUnicodeEscape(checkpoint)
            }
            advance()
            guard current == "u" else {
                throw DeckJSONValueError.invalidUnicodeEscape(index)
            }
            advance()
            let second = try parseHexQuad()
            guard (0xDC00...0xDFFF).contains(second) else {
                throw DeckJSONValueError.invalidUnicodeEscape(index)
            }

            let high = UInt32(first - 0xD800)
            let low = UInt32(second - 0xDC00)
            let codePoint = 0x10000 + ((high << 10) | low)
            guard let scalar = UnicodeScalar(codePoint) else {
                throw DeckJSONValueError.invalidUnicodeEscape(index)
            }
            return String(scalar)
        }

        guard let scalar = UnicodeScalar(first) else {
            throw DeckJSONValueError.invalidUnicodeEscape(index)
        }
        return String(scalar)
    }

    private mutating func parseHexQuad() throws -> UInt32 {
        let start = index
        var value: UInt32 = 0
        for _ in 0..<4 {
            guard let scalar = current, let digit = scalar.jsonHexDigitValue else {
                throw DeckJSONValueError.invalidUnicodeEscape(start)
            }
            value = (value << 4) | UInt32(digit)
            advance()
        }
        return value
    }

    private mutating func parseNumberToken() throws -> String {
        let start = index

        if current == "-" {
            advance()
        }

        guard let scalar = current else {
            throw DeckJSONValueError.unexpectedEndOfInput
        }

        if scalar == "0" {
            advance()
        } else if scalar.isASCIIDigit, scalar != "0" {
            advance()
            while current?.isASCIIDigit == true {
                advance()
            }
        } else {
            throw DeckJSONValueError.invalidJSONNumber(currentToken(from: start))
        }

        if current == "." {
            advance()
            guard current?.isASCIIDigit == true else {
                throw DeckJSONValueError.invalidJSONNumber(currentToken(from: start))
            }
            while current?.isASCIIDigit == true {
                advance()
            }
        }

        if current == "e" || current == "E" {
            advance()
            if current == "+" || current == "-" {
                advance()
            }
            guard current?.isASCIIDigit == true else {
                throw DeckJSONValueError.invalidJSONNumber(currentToken(from: start))
            }
            while current?.isASCIIDigit == true {
                advance()
            }
        }

        let token = currentToken(from: start)
        guard DeckJSONValue.number(token).isValidJSONObject else {
            throw DeckJSONValueError.invalidJSONNumber(token)
        }
        return token
    }

    private mutating func consume(_ expected: UnicodeScalar) throws {
        guard current == expected else {
            throw DeckJSONValueError.unexpectedCharacter(index)
        }
        advance()
    }

    private mutating func consumeLiteral(_ literal: String) throws {
        for scalar in literal.unicodeScalars {
            guard current == scalar else {
                throw DeckJSONValueError.invalidLiteral(index)
            }
            advance()
        }
    }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar.isJSONWhitespace {
            advance()
        }
    }

    private mutating func advance() {
        index += 1
    }

    private var current: UnicodeScalar? {
        guard index < scalars.count else { return nil }
        return scalars[index]
    }

    private func currentToken(from start: Int) -> String {
        String(String.UnicodeScalarView(scalars[start..<min(index, scalars.count)]))
    }
}

private enum DeckJSONRenderer {
    static func render(_ value: DeckJSONValue) throws -> String {
        switch value {
        case .string(let string):
            return "\"\(escape(string))\""
        case .number(let token):
            guard value.isValidJSONObject else {
                throw DeckJSONValueError.invalidJSONNumber(token)
            }
            return token
        case .bool(let bool):
            return bool ? "true" : "false"
        case .null:
            return "null"
        case .array(let array):
            return "[\(try array.map(render).joined(separator: ","))]"
        case .object(let object):
            let pairs = try object.keys.sorted().map { key in
                let escapedKey = "\"\(escape(key))\""
                let renderedValue = try render(object[key] ?? .null)
                return "\(escapedKey):\(renderedValue)"
            }
            return "{\(pairs.joined(separator: ","))}"
        }
    }

    private static func escape(_ string: String) -> String {
        var escaped = String()
        escaped.reserveCapacity(string.count)

        for scalar in string.unicodeScalars {
            switch scalar {
            case "\"": escaped.append("\\\"")
            case "\\": escaped.append("\\\\")
            case "\u{08}": escaped.append("\\b")
            case "\u{0C}": escaped.append("\\f")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            case "/" : escaped.append("/")
            default:
                if scalar.value < 0x20 {
                    escaped.append(String(format: "\\u%04X", scalar.value))
                } else {
                    escaped.unicodeScalars.append(scalar)
                }
            }
        }

        return escaped
    }
}

private extension UnicodeScalar {
    var isASCIIDigit: Bool {
        value >= 48 && value <= 57
    }

    var jsonHexDigitValue: Int? {
        switch value {
        case 48...57:
            return Int(value - 48)
        case 65...70:
            return Int(value - 55)
        case 97...102:
            return Int(value - 87)
        default:
            return nil
        }
    }

    var isJSONWhitespace: Bool {
        self == " " || self == "\n" || self == "\r" || self == "\t"
    }
}
