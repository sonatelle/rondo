import Foundation

/// Where Rondo keeps its data.
enum Database {
  /// The database file, creating its directory if this is a first launch.
  ///
  /// Sandboxed, this resolves inside the app's own container. The extra
  /// `Rondo` directory is there for the unsandboxed case, so a debug build
  /// does not drop a loose file into the shared Application Support.
  static func fileURL() throws -> URL {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    )
    let directory = support.appending(path: "Rondo", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: "rondo.sqlite3", directoryHint: .notDirectory)
  }
}
