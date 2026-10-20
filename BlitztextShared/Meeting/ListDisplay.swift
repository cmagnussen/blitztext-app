import Foundation

/// Public Sans kerns a hyphen and the space after it so tightly that "- Punkt" reads as
/// "-Punkt". Summaries and notes therefore show their bullet points with "•"; copied text
/// keeps "- ", which mail and notes apps read as a list.
enum ListDisplay {
    static func bullets(_ text: String) -> String {
        text.components(separatedBy: "\n")
            .map { $0.hasPrefix("- ") ? "\u{2022} " + $0.dropFirst(2) : $0 }
            .joined(separator: "\n")
    }
}
