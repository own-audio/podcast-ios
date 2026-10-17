import FeedKit
import PlayerCore
import SwiftUI

/// The full player: the picture, the episode and show, the current chapter as a button, the
/// scrubber, the transport with skip intervals, and the speed, sleep timer and chapter tools.
struct PlayerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var sheet: Sheet?
    @State private var scrubbing: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum Sheet: Identifiable {
        case speed, sleep, chapters
        var id: Self { self }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let item = model.nowPlaying {
                    content(item)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "mic")
                }
            }
            .background(Theme.Colors.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "chevron.down") }
                        .accessibilityLabel("Close")
                        .accessibilityIdentifier("player.close")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        model.stopPlayback()
                        dismiss()
                    } label: { Image(systemName: "xmark.circle") }
                        .accessibilityLabel("Stop")
                        .accessibilityIdentifier("player.stop")
                }
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .speed: SpeedSheet()
                case .sleep: SleepTimerSheet()
                case .chapters: ChaptersSheet()
                }
            }
        }
    }

    private func content(_ item: SourcedEpisode) -> some View {
        let engine = model.engine
        return ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                ArtworkView(url: item.episode.imageURL ?? model.nowPlayingShow?.imageURL, size: dynamicTypeSize.isAccessibilitySize ? 140 : 280, radius: Theme.Radius.cover)
                    .overlay(alignment: .topTrailing) {
                        if let remaining = engine.sleepTimer.remainingSecs {
                            Label(formatDuration(remaining), systemImage: "moon.zzz.fill")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .padding(.horizontal, Theme.Spacing.sm)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(.regularMaterial, in: Capsule())
                                .padding(Theme.Spacing.sm)
                                .accessibilityIdentifier("player.sleepBadge")
                        }
                    }
                    .padding(.top, Theme.Spacing.lg)
                VStack(spacing: Theme.Spacing.xs) {
                    Text(Mojibake.repair(item.episode.title))
                        .font(.title3.bold())
                        .foregroundStyle(Theme.Colors.foreground)
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .accessibilityIdentifier("player.title")
                    if let show = model.nowPlayingShow {
                        Text(Mojibake.repair(show.title)).font(.subheadline).foregroundStyle(Theme.Colors.muted).lineLimit(1)
                    }
                    if engine.hasChapters {
                        Button { sheet = .chapters } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Text(engine.currentChapter?.title ?? String(localized: "Chapters")).font(.subheadline.weight(.medium)).lineLimit(1)
                                Image(systemName: "chevron.down").font(.caption2)
                            }
                            .foregroundStyle(Theme.Colors.accent)
                        }
                        .accessibilityIdentifier("player.chapter")
                    }
                }
                .padding(.horizontal, Theme.Spacing.xl)
                scrubber
                controls
                tools
                if let message = engine.errorMessage {
                    Text(message).font(.footnote).foregroundStyle(Theme.Colors.error).padding(.horizontal, Theme.Spacing.xl)
                }
            }
            .padding(.bottom, Theme.Spacing.xl)
        }
    }

    private var scrubber: some View {
        let engine = model.engine
        let duration = max(engine.durationMs, 1)
        let shown = scrubbing ?? Double(engine.positionMs)
        return VStack(spacing: Theme.Spacing.xs) {
            Slider(value: Binding(get: { shown }, set: { scrubbing = $0 }), in: 0...Double(duration)) { editing in
                if !editing, let scrubbing {
                    engine.seek(to: Int64(scrubbing))
                    self.scrubbing = nil
                }
            }
            .tint(Theme.Colors.accent)
            .disabled(engine.durationMs == 0)
            .accessibilityIdentifier("player.scrubber")
            .accessibilityValue("\(ProgressText.clock(Int64(shown))) of \(ProgressText.clock(engine.durationMs))")
            HStack {
                Text(ProgressText.clock(Int64(shown))).accessibilityIdentifier("player.elapsed")
                Spacer()
                Text(engine.durationMs > 0 ? ProgressText.leftAtSpeed(engine.durationMs - Int64(shown), rate: engine.rate) : "")
                    .accessibilityIdentifier("player.remaining")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(Theme.Colors.muted)
        }
        .padding(.horizontal, Theme.Spacing.xl)
    }

    private var controls: some View {
        let engine = model.engine
        return HStack(spacing: Theme.Spacing.xxl) {
            control("gobackward.\(Int(engine.skipBackwardSecs))", String(localized: "Back \(Int(engine.skipBackwardSecs)) seconds"), id: "player.skipBackward") { engine.skipBackward() }
            Button {
                Haptics.impact(.medium)
                engine.togglePlayPause()
            } label: {
                Group {
                    if engine.isLoading || engine.isBuffering {
                        ProgressView().controlSize(.large)
                    } else {
                        Image(systemName: engine.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.system(size: 64))
                    }
                }
                .foregroundStyle(Theme.Colors.foreground)
                .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("player.playPause")
            .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
            control("goforward.\(Int(engine.skipForwardSecs))", String(localized: "Forward \(Int(engine.skipForwardSecs)) seconds"), id: "player.skipForward") { engine.skipForward() }
        }
    }

    private func control(_ symbol: String, _ label: String, id: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.impact(.light)
            action()
        } label: {
            Image(systemName: symbol)
                .font(.title)
                .foregroundStyle(Theme.Colors.foreground)
                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }

    private var tools: some View {
        let engine = model.engine
        let sleeping = engine.sleepTimer.isActive || engine.stopsAtEndOfChapter
        return HStack(spacing: Theme.Spacing.xxl) {
            tool(id: "player.speed", label: String(localized: "Speed \(String(format: "%.2g", engine.rate))"), caption: "Speed", tinted: engine.rate != 1) {
                Text(String(format: "%.2g×", engine.rate)).font(.subheadline.weight(.semibold).monospacedDigit())
            } action: { sheet = .speed }
            tool(id: "player.sleep", label: String(localized: "Sleep Timer"), caption: "Sleep", tinted: sleeping) {
                Image(systemName: sleeping ? "moon.zzz.fill" : "moon.zzz").font(.title3)
            } action: { sheet = .sleep }
            if engine.hasChapters {
                tool(id: "player.chapters", label: String(localized: "Chapters"), caption: "Chapters", tinted: false) {
                    Image(systemName: "list.bullet").font(.title3)
                } action: { sheet = .chapters }
            }
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private func tool<Icon: View>(id: String, label: String, caption: LocalizedStringKey, tinted: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                icon().frame(height: 24)
                Text(caption).font(.caption2)
            }
            .foregroundStyle(tinted ? Theme.Colors.accent : Theme.Colors.foreground)
            .frame(minWidth: 56, minHeight: Theme.minTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
    }
}

/// Speed: a stepper in 0.05 steps, with the common speeds one tap away.
struct SpeedSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private let presets: [Float] = [0.8, 1.0, 1.2, 1.5, 1.75, 2.0, 2.5, 3.0]

    var body: some View {
        NavigationStack {
            VStack(spacing: Theme.Spacing.xl) {
                Text(String(format: "%.2f×", model.engine.rate))
                    .font(.system(size: 48, weight: .semibold, design: .rounded).monospacedDigit())
                    .accessibilityIdentifier("speed.value")
                HStack(spacing: Theme.Spacing.xl) {
                    Button { model.setRate(model.engine.rate - 0.05) } label: { Image(systemName: "minus.circle.fill").font(.system(size: 44)) }
                        .accessibilityLabel("Slower")
                        .accessibilityIdentifier("speed.slower")
                    Button { model.setRate(model.engine.rate + 0.05) } label: { Image(systemName: "plus.circle.fill").font(.system(size: 44)) }
                        .accessibilityLabel("Faster")
                        .accessibilityIdentifier("speed.faster")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: Theme.Spacing.sm) {
                    ForEach(presets, id: \.self) { preset in
                        Button {
                            model.setRate(preset)
                        } label: {
                            Text(String(format: "%.2g×", preset))
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: Theme.minTarget)
                        }
                        .buttonStyle(.bordered)
                        .tint(abs(model.engine.rate - preset) < 0.01 ? .accentColor : .secondary)
                        .accessibilityIdentifier("speed.preset.\(preset)")
                    }
                }
                Text("Pitch stays the same at any speed. A show can keep its own speed in its settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .padding(Theme.Spacing.xl)
            .navigationTitle("Speed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}

/// The sleep timer: a countdown, the end of the chapter, or the end of the episode.
struct SleepTimerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let engine = model.engine
        let timer = engine.sleepTimer
        NavigationStack {
            List {
                if timer.isActive || engine.stopsAtEndOfChapter {
                    Section {
                        if let remaining = timer.remainingSecs {
                            LabeledContent("Stops in", value: formatDuration(remaining))
                            Button("Add 10 Minutes") { timer.extend(bySecs: 600) }
                        } else if engine.stopsAtEndOfChapter {
                            Text("Stops at the end of this chapter")
                        } else {
                            Text("Stops at the end of the episode")
                        }
                        Button("Turn Off", role: .destructive) {
                            timer.cancel()
                            engine.stopAtEndOfChapter(false)
                            dismiss()
                        }
                        .accessibilityIdentifier("sleep.off")
                    }
                }
                Section {
                    ForEach(SleepTimer.Preset.allCases) { preset in
                        Button(preset.label) {
                            engine.stopAtEndOfChapter(false)
                            timer.start(preset: preset)
                            dismiss()
                        }
                        .accessibilityIdentifier("sleep.\(Int(preset.secs / 60))")
                    }
                    if engine.hasChapters {
                        Button("End of Chapter") {
                            timer.cancel()
                            engine.stopAtEndOfChapter(true)
                            dismiss()
                        }
                        .accessibilityIdentifier("sleep.endOfChapter")
                    }
                    Button("End of Episode") {
                        engine.stopAtEndOfChapter(false)
                        timer.startUntilEndOfItem()
                        dismiss()
                    }
                    .accessibilityIdentifier("sleep.endOfEpisode")
                }
            }
            .navigationTitle("Sleep Timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

/// The episode's chapters, the current one marked; a tap plays from there.
struct ChaptersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let engine = model.engine
        let chapters = engine.book?.timeline.chapters ?? []
        let current = engine.currentChapter
        NavigationStack {
            ScrollViewReader { proxy in
                List(chapters) { chapter in
                    Button {
                        engine.seek(to: chapter.startMs)
                        if !engine.isPlaying { engine.play() }
                        dismiss()
                    } label: {
                        HStack {
                            if chapter == current {
                                Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint).accessibilityLabel("Playing")
                            }
                            Text(chapter.title).foregroundStyle(.primary).lineLimit(2)
                            Spacer()
                            Text(ProgressText.clock(chapter.startMs)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                    .id(chapter.id)
                    .accessibilityIdentifier("chapters.\(chapter.startMs)")
                }
                .listStyle(.plain)
                .onAppear { if let current { proxy.scrollTo(current.id, anchor: .center) } }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

/// Above the tab bar while an episode is loaded: picture, title, time left, play/pause, skip.
struct MiniPlayerBar: View {
    @Environment(AppModel.self) private var model
    let onTap: () -> Void

    var body: some View {
        if let item = model.nowPlaying {
            let engine = model.engine
            Button {
                Haptics.impact(.medium)
                onTap()
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    ArtworkView(url: item.episode.imageURL ?? model.nowPlayingShow?.imageURL, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Mojibake.repair(item.episode.title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.Colors.foreground).lineLimit(1)
                        Text(engine.durationMs > 0 ? ProgressText.leftAtSpeed(engine.durationMs - engine.positionMs, rate: engine.rate) : (model.nowPlayingShow?.title ?? ""))
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.muted)
                            .lineLimit(1)
                    }
                    Spacer()
                    if engine.isLoading || engine.isBuffering {
                        ProgressView().frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                    } else {
                        Button {
                            Haptics.impact(.medium)
                            engine.togglePlayPause()
                        } label: {
                            Image(systemName: engine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.Colors.foreground)
                                .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("miniPlayer.playPause")
                        .accessibilityLabel(engine.isPlaying ? "Pause" : "Play")
                    }
                    Button {
                        Haptics.impact(.light)
                        engine.skipForward()
                    } label: {
                        Image(systemName: "goforward.\(Int(engine.skipForwardSecs))")
                            .font(.title3)
                            .foregroundStyle(Theme.Colors.foreground)
                            .frame(minWidth: Theme.minTarget, minHeight: Theme.minTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("miniPlayer.skipForward")
                    .accessibilityLabel("Skip forward \(Int(engine.skipForwardSecs)) seconds")
                }
                .padding(Theme.Spacing.sm)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("miniPlayer")
            .accessibilityHint("Opens the player")
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Theme.Radius.miniPlayer, style: .continuous))
            .overlay(alignment: .bottom) {
                GeometryReader { geometry in
                    let fraction = engine.durationMs > 0 ? CGFloat(engine.positionMs) / CGFloat(engine.durationMs) : 0
                    Theme.Colors.accent.frame(width: geometry.size.width * min(max(fraction, 0), 1), height: 2)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.miniPlayer, style: .continuous))
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            .padding(.horizontal, Theme.Spacing.screenEdge)
            .padding(.bottom, Theme.Spacing.xs)
        }
    }
}
