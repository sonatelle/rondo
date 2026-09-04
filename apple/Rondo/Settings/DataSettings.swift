import SwiftUI

struct DataSettings: View {
  @State private var location = (try? Database.fileURL())?.path(percentEncoded: false) ?? ""

  var body: some View {
    Form {
      LabeledContent("Database") {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
          // Selectable so the path can be copied into a terminal or a
          // backup script, which is the only reason to show it at all.
          Text(location)
            .font(.system(.caption, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(3)
            .truncationMode(.middle)
          Button("Show in Finder") {
            guard let url = try? Database.fileURL() else { return }
            NSWorkspace.shared.activateFileViewerSelecting([url])
          }
        }
      }
      Text(
        """
        Rondo keeps everything in this one file and never sends it anywhere. \
        Copy it, and its -wal and -shm companions, to keep a backup.
        """
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Section {
        Text("Export a backup or restore one from the File menu.")
          .font(.caption)
          .foregroundStyle(.secondary)
        Text("Restoring merges and never deletes, so opening the wrong file cannot cost you data.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
  }
}
