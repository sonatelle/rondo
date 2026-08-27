import Foundation
import Testing
import UniformTypeIdentifiers

@testable import Rondo

/// Tests for the app's half of a backup: carrying the core's JSON to a file
/// and back without altering it.
///
/// What the JSON means is the core's business and is tested there. What is
/// worth pinning down here is that the text survives the trip - a backup
/// that comes back changed is one that cannot be restored.
struct BackupTests {
  @Test("JSON survives being written and read back unchanged")
  func documentRoundTrips() {
    // Non-ASCII on purpose: written as anything but UTF-8 the name would
    // come back mangled, and the core would reject the file.
    let json = #"{"version":1,"subscriptions":[{"name":"Café 訂閱"}]}"#

    let written = BackupFile(json: json).data

    #expect(String(data: written, encoding: .utf8) == json)
  }

  @Test("A saved backup is named for the day it was taken")
  func filenameCarriesTheDate() throws {
    var components = DateComponents()
    components.year = 2026
    components.month = 2
    components.day = 5
    components.hour = 23
    components.minute = 45
    let evening = try #require(Calendar.current.date(from: components))

    // Padded and dot-free, so a folder of these sorts into the order they
    // were taken, and taken from the calendar so a late-evening export is
    // not named for tomorrow.
    #expect(BackupFile.defaultFilename(on: evening) == "Rondo Backup 2026-02-05")
  }
}
