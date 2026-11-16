import SwiftUI

extension View {
    /// Space plays or pauses, ⌘← and ⌘→ skip by the listener's intervals: for a hardware
    /// keyboard on iPad and for the Mac. The buttons are invisible; only their shortcuts count,
    /// and holding ⌘ on iPad lists them. A text field being edited gets its keys first (UIKit
    /// gives text input priority over key commands), so Space still types a space in Search.
    func playbackShortcuts() -> some View {
        background { PlaybackShortcutButtons() }
    }
}

private struct PlaybackShortcutButtons: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let engine = model.engine
        Group {
            Button(engine.isPlaying ? LocalizedStringKey("Pause") : "Play") { engine.togglePlayPause() }
                .keyboardShortcut(.space, modifiers: [])
            Button("Skip Back") { engine.skipBackward() }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Skip Forward") { engine.skipForward() }
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .disabled(model.nowPlaying == nil)
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }
}
