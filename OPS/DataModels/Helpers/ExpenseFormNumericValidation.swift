import Foundation

enum ExpenseFormNumericValidation {
    /// Validate text before building JSON or calculating allocation totals.
    /// A malformed tax is never silently turned into a deliberate null.
    static func errors(amount: String, tax: String, percentages: [String]) -> [String] {
        var errors: [String] = []
        if decimal(amount) == nil { errors.append("Enter a valid amount.") }
        if !tax.isEmpty, decimal(tax) == nil { errors.append("Enter a valid tax amount or leave it blank.") }
        if percentages.contains(where: {
            guard let value = decimal($0) else { return true }
            return value <= 0 || value > 100
        }) { errors.append("Enter a project percentage greater than 0 and no more than 100.") }
        return errors
    }

    private static func decimal(_ text: String) -> Double? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)$"#, options: .regularExpression) != nil,
              let number = Double(value), number.isFinite else { return nil }
        return number
    }
}
