import Foundation

/// Additive metadata; the persisted field kind remains short_text so older
/// clients can still read whole pages containing this field.
struct SiteVisitSingleChoice: Codable, Equatable, Sendable {
    struct Option: Codable, Equatable, Identifiable, Sendable {
        var id: String = UUID().uuidString.lowercased()
        var label: String
    }

    static let minimumOptions = 2
    static let maximumOptions = 20
    static let maximumLabelLength = 120

    var version: Int = 1
    var options: [Option]

    var isValid: Bool { (try? normalized()) == self }

    func normalized() throws -> Self {
        guard version == 1 else { throw ValidationError.invalidDefinition }
        guard (Self.minimumOptions...Self.maximumOptions).contains(options.count) else {
            throw ValidationError.optionCount
        }
        var ids = Set<String>()
        var labels = Set<String>()
        var result = self
        for index in result.options.indices {
            let option = result.options[index]
            guard UUID(uuidString: option.id)?.uuidString.lowercased() == option.id,
                  ids.insert(option.id).inserted else { throw ValidationError.invalidDefinition }
            let label = option.label.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !label.isEmpty else { throw ValidationError.emptyLabel }
            guard label.unicodeScalars.count <= Self.maximumLabelLength else { throw ValidationError.labelTooLong }
            guard labels.insert(label.lowercased(with: Locale(identifier: "und"))).inserted else { throw ValidationError.duplicateLabel }
            result.options[index].label = label
        }
        return result
    }

    func option(matching text: String?) -> Option? {
        guard isValid, let text else { return nil }
        return options.first { $0.label.utf8.elementsEqual(text.utf8) }
    }

    enum ValidationError: LocalizedError {
        case invalidDefinition, optionCount, emptyLabel, labelTooLong, duplicateLabel
        var errorDescription: String? {
            switch self {
            case .invalidDefinition: return "This choice field is invalid. Add it again."
            case .optionCount: return "Use 2 to 20 answer options."
            case .emptyLabel: return "Every answer option needs a label."
            case .labelTooLong: return "Use 120 characters or fewer for each answer option."
            case .duplicateLabel: return "Give each answer option a different label."
            }
        }
    }
}
