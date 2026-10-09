import Foundation

/// Where Rondo lives, for the places that have to point somebody at it.
///
/// One definition each rather than a literal per use. The About tab lists
/// all three, and the screen shown when the database is from a newer build
/// needs the releases page too - the same address written twice is two
/// addresses that can come to disagree, and the one that goes stale sends
/// somebody nowhere at the moment they are already stuck.
enum Project {
  static let repository = url("https://github.com/sonatelle/rondo")
  static let releases = url("https://github.com/sonatelle/rondo/releases")
  static let issues = url("https://github.com/sonatelle/rondo/issues")

  /// These are literals in this file, so a typo is a link that lands on
  /// the project rather than a crash at the moment somebody clicks it.
  private static func url(_ address: String) -> URL {
    URL(string: address) ?? URL(string: "https://github.com/sonatelle/rondo")!
  }
}
