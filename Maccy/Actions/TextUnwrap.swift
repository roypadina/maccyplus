import Foundation

enum TextUnwrap {
  /// Minimum wrap width. Guards the weak 2-line case: a long first line + short
  /// remainder only counts as wrapped if the first line is near a real wrap width.
  static let minWrapWidth = 40

  /// True when the text shows a fixed-width char-wrap signature: every line except
  /// the last has the same length L >= minWrapWidth, and the last line is non-empty
  /// and no longer than L. This is the conservative gate for auto-firing.
  static func isSoftWrapped(_ text: String) -> Bool {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    var lines = normalized.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() } // trailing newline
    guard lines.count >= 2 else { return false }
    let widths = Set(lines.dropLast().map { $0.count })
    guard widths.count == 1, let l = widths.first, l >= minWrapWidth else { return false }
    guard let last = lines.last, !last.isEmpty, last.count <= l else { return false }
    return true
  }

  /// Join a wrapped command into one line.
  /// - Char-wrap signature → delete newlines (exact reconstruction, no spurious spaces).
  /// - Otherwise → collapse each newline run (+ surrounding whitespace) to one space.
  static func unwrap(_ text: String) -> String {
    let normalized = text
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
    let result: String
    if isSoftWrapped(normalized) {
      result = normalized.replacingOccurrences(of: "\n", with: "")
    } else {
      result = normalized
        .components(separatedBy: "\n")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .joined(separator: " ")
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
