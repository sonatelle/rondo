import SwiftUI
import UniformTypeIdentifiers

/// A backup on its way to or from a file the person picked.
///
/// The core produces and consumes the JSON; this only carries that text
/// across a file panel. It is SwiftUI's document type rather than
/// `NSSavePanel` so the same code still works when iOS arrives, and so the
/// sandbox grants access to whichever location was chosen.
struct BackupFile: FileDocument {
  /// JSON, because that is what the core writes and because a person can
  /// open one and read what it holds without this app.
  static let readableContentTypes = [UTType.json]

  let json: String

  init(json: String) {
    self.json = json
  }

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents,
          let text = String(data: data, encoding: .utf8)
    else {
      throw CocoaError(.fileReadCorruptFile)
    }
    json = text
  }

  /// The bytes written to disk.
  ///
  /// Separate from `fileWrapper(configuration:)` only because SwiftUI's
  /// write configuration cannot be constructed outside SwiftUI, so this is
  /// the last point a test can reach.
  var data: Data {
    Data(json.utf8)
  }

  func fileWrapper(configuration _: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: data)
  }

  /// Reads a file chosen in an open panel.
  ///
  /// The panel hands back a location rather than a right to it, so the
  /// scope is claimed for the read and given back straight afterwards.
  static func read(contentsOf url: URL) throws -> String {
    let scoped = url.startAccessingSecurityScopedResource()
    defer {
      if scoped {
        url.stopAccessingSecurityScopedResource()
      }
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  /// The name a saved backup is offered under.
  ///
  /// Dated, since the reason to keep backups is telling one copy from
  /// another, and dated as `YYYY-MM-DD` so a folder of them sorts by name
  /// into the order they were taken.
  static func defaultFilename(on date: Date = Date()) -> String {
    "Rondo Backup \(Formatting.civilDate(from: date))"
  }
}
