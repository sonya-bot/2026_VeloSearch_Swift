import Foundation

enum CSVCodec {
  enum ParseError: Error { case malformedQuotes }

  static func row(_ fields: [String]) -> String {
    fields.map { field in
      let needsQuotes = field.contains { character in
        character == "," || character == "\"" || character == "\r" || character == "\n"
          || character == "\r\n"
      }
      guard needsQuotes else { return field }
      return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }.joined(separator: ",")
  }

  static func parse(_ contents: String) throws -> [[String]] {
    var rows: [[String]] = []
    var fields: [String] = []
    var field = ""
    var isQuoted = false
    var hasClosedQuote = false
    var hasPendingRow = false
    let characters = Array(contents)
    var index = characters.first == "\u{FEFF}" ? 1 : 0
    while index < characters.count {
      let character = characters[index]
      if isQuoted {
        if character == "\"" {
          if index + 1 < characters.count, characters[index + 1] == "\"" {
            field.append("\"")
            index += 1
          } else {
            isQuoted = false
            hasClosedQuote = true
          }
        } else {
          field.append(character)
        }
      } else if character == "," {
        fields.append(field)
        field = ""
        hasClosedQuote = false
        hasPendingRow = true
      } else if character == "\n" || character == "\r" || character == "\r\n" {
        if hasPendingRow || !fields.isEmpty || !field.isEmpty || hasClosedQuote {
          fields.append(field)
          rows.append(fields)
        }
        fields = []
        field = ""
        hasClosedQuote = false
        hasPendingRow = false
      } else if character == "\"", field.isEmpty, !hasClosedQuote {
        isQuoted = true
        hasPendingRow = true
      } else {
        guard !hasClosedQuote, character != "\"" else { throw ParseError.malformedQuotes }
        field.append(character)
        hasPendingRow = true
      }
      index += 1
    }
    guard !isQuoted else { throw ParseError.malformedQuotes }
    if hasPendingRow || !fields.isEmpty || !field.isEmpty || hasClosedQuote {
      fields.append(field)
      rows.append(fields)
    }
    return rows
  }

  static func decimal(_ value: Double, precision: Int = 3) -> String {
    String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), precision, value)
  }
}
