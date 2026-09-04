import SwiftUI

struct DataSettings: View {
  @State private var location = (try? Database.fileURL())?.path(percentEncoded: false) ?? ""

  var body: some View {
    let bundle = Localization.bundle
    let locale = Localization.locale
    return Form {
      LabeledContent(String(localized: "Database", bundle: bundle, locale: locale,
                            comment: "Settings row: where the one file lives"))
      {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
          // Selectable so the path can be copied into a terminal or a
          // backup script, which is the only reason to show it at all.
          Text(location)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
          Button(String(localized: "Show in Finder", bundle: bundle, locale: locale,
                        comment: "Reveals the database file"))
          {
            guard let url = try? Database.fileURL() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
      }
      Text(verbatim: String(
        localized: """
        Rondo keeps everything in this one file and never sends it anywhere. \
        Copy it, and its -wal and -shm companions, to keep a backup.
        """,
        bundle: bundle, locale: locale, comment: "Under the database path"
      ))
      .font(.caption)
      .foregroundStyle(.secondary)

      Section {
        Text(verbatim: String(localized: "Export a backup or restore one from the File menu.",
                              bundle: bundle, locale: locale,
                              comment: "Where the backup commands are"))
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(verbatim: String(
          localized: "Restoring merges and never deletes, so opening the wrong file cannot cost you data.",
          bundle: bundle, locale: locale, comment: "What restoring a backup does"
        ))
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
