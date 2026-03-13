/// A single review comment attached to a line in a diff.
public struct DiffReviewComment {
    public let lineNumber: Int
    public let text: String

    public init(lineNumber: Int, text: String) {
        self.lineNumber = lineNumber
        self.text = text
    }
}

/// Formats diff review comments as plain text for clipboard copy.
public enum DiffReviewFormatter {
    public static func format(filePath: String, comments: [DiffReviewComment]) -> String {
        guard !comments.isEmpty else { return "" }
        let sorted = comments.sorted { $0.lineNumber < $1.lineNumber }
        return sorted.map { comment in
            "\(filePath):L\(comment.lineNumber)\n\(comment.text)"
        }.joined(separator: "\n\n")
    }
}
