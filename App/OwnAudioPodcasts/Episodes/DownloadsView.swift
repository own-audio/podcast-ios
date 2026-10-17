import SwiftUI

/// What is on this iPhone, from every source, each row saying where it came from. Downloads
/// themselves arrive with the next phase; until then this says what the tab is for.
struct DownloadsView: View {
    var body: some View {
        ContentUnavailableView {
            Label("Nothing Downloaded", systemImage: "arrow.down.circle")
        } description: {
            Text("Episodes you download appear here, with the source each came from, and play with no network.")
        }
        .accessibilityIdentifier("downloads.empty")
        .navigationTitle("Downloads")
    }
}
