import Foundation

extension String {
    /// Returns `nil` if the string is empty after trimming whitespace; otherwise returns the trimmed value.
    var trimmedNilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Array where Element == String {
    /// Trims each element and filters out empty strings.
    /// Returns `nil` when the resulting array would be empty.
    var nonEmptyStrings: [String]? {
        let cleaned = map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned
    }
}
