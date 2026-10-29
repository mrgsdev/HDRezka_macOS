import AVKit
import SwiftUI

/// The player window: system playback controls, subtitles drawn over the video,
/// and quality, speed, subtitle and next-episode controls in the toolbar.
struct PlayerView: View {
    @State private var controller: PlayerController
    @Environment(\.dismiss) private var dismiss

    init(request: PlaybackRequest) {
        _controller = State(initialValue: PlayerController(request: request))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Under the title bar too: the toolbar floats over the picture with no background of its own.
            PlayerSurface(player: controller.player) { controller.seek(by: $0) }
                .ignoresSafeArea()

            if let text = controller.subtitleText {
                Text(text)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .shadow(color: .black, radius: 2)
                    .shadow(color: .black, radius: 6)
                    .padding(.horizontal, 80)
                    // Above the floating playback controls.
                    .padding(.bottom, 96)
                    .allowsHitTesting(false)
            }

            if controller.isLoading {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            if let jump = controller.seekHint {
                Label(Self.jumpText(jump), systemImage: jump < 0 ? "gobackward" : "goforward")
                    .font(.title2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.55), in: Capsule())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controller.seekHint == nil)
        .background(.black)
        .frame(minWidth: 640, minHeight: 360)
        .navigationTitle(controller.request.title)
        .navigationSubtitle(controller.subtitleLine)
        .toolbar {
            ToolbarItemGroup {
                qualityMenu
                speedMenu
                subtitlesMenu
                if controller.nextEpisode != nil {
                    Button {
                        controller.playNext()
                    } label: {
                        Label("Следующая серия", systemImage: "forward.end.fill")
                    }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
                    .help("Следующая серия (⇧⌘N)")
                }
            }
        }
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        // In full screen the video takes the whole screen; the toolbar slides in with the menu bar.
        .windowToolbarFullScreenVisibility(.onHover)
        .onAppear {
            controller.onClose = { dismiss() }
            controller.start()
        }
        .onDisappear {
            controller.finish()
        }
        .alert("Не удалось воспроизвести", isPresented: Binding(
            get: { controller.errorMessage != nil },
            set: { if !$0 { controller.errorMessage = nil } }
        )) {
            Button("Закрыть", role: .cancel) { dismiss() }
        } message: {
            Text(controller.errorMessage ?? "")
        }
    }

    /// "+30 с", "−10 с", "+1:10" for a run of arrow presses.
    private static func jumpText(_ seconds: Double) -> String {
        let sign = seconds < 0 ? "−" : "+"
        let size = abs(seconds)
        return sign + (size < 60 ? "\(Int(size)) с" : size.playbackTime)
    }

    private var qualityMenu: some View {
        Menu {
            ForEach(controller.sortedQualities) { option in
                Button {
                    controller.switchQuality(option)
                } label: {
                    let title = option.isPremium ? "\(option.label) ★ Premium" : option.label
                    if option == controller.quality {
                        Label(title, systemImage: "checkmark")
                    } else {
                        Text(title)
                    }
                }
            }
        } label: {
            Label(controller.quality?.label ?? "Качество", systemImage: "slider.horizontal.3")
                .labelStyle(.titleAndIcon)
        }
        // A toolbar shows only icons by default; the current quality has to be readable.
        .fixedSize()
        .disabled(controller.stream == nil)
        .help("Качество")
        .accessibilityLabel("Качество")
    }

    private var speedMenu: some View {
        Menu {
            ForEach(PlayerController.speedOptions, id: \.self) { rate in
                Button {
                    controller.setSpeed(rate)
                } label: {
                    if rate == controller.speed {
                        Label(PlayerController.speedLabel(rate), systemImage: "checkmark")
                    } else {
                        Text(PlayerController.speedLabel(rate))
                    }
                }
            }
        } label: {
            Label(controller.speed == 1 ? "Скорость" : PlayerController.speedLabel(controller.speed), systemImage: "gauge.with.dots.needle.67percent")
                .labelStyle(.titleAndIcon)
        }
        .fixedSize()
        .help("Скорость")
        .accessibilityLabel("Скорость")
    }

    @ViewBuilder
    private var subtitlesMenu: some View {
        if let subtitles = controller.stream?.subtitles, !subtitles.isEmpty {
            Menu {
                Button {
                    controller.selectSubtitle(nil)
                } label: {
                    if controller.subtitle == nil {
                        Label("Выключены", systemImage: "checkmark")
                    } else {
                        Text("Выключены")
                    }
                }
                ForEach(subtitles) { track in
                    Button {
                        controller.selectSubtitle(track)
                    } label: {
                        if track == controller.subtitle {
                            Label(track.label, systemImage: "checkmark")
                        } else {
                            Text(track.label)
                        }
                    }
                }
            } label: {
                Label(controller.subtitle?.label ?? "Субтитры", systemImage: "captions.bubble")
                    .labelStyle(.titleAndIcon)
            }
            .fixedSize()
            .help("Субтитры")
            .accessibilityLabel("Субтитры")
        }
    }
}

/// The system player view. Its own full-screen button is hidden: the window goes full screen instead,
/// so the subtitles drawn over it stay visible.
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    let onSeek: (Double) -> Void

    func makeNSView(context: Context) -> TitleBarHidingPlayerView {
        let view = TitleBarHidingPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        view.onSeek = onSeek
        // Space, arrows and J/K/L reach the player without clicking it first.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: TitleBarHidingPlayerView, context: Context) {
        if view.player !== player { view.player = player }
        view.onSeek = onSeek
    }
}

/// Hides the window's title bar along with the floating controls, as QuickTime does: a few seconds
/// after the mouse stops while the video plays. It stays while paused, under the pointer or with a
/// menu open; in full screen the system hides it.
/// ← and → jump 10 seconds, as in web players, instead of AVPlayerView's step of a frame.
private final class TitleBarHidingPlayerView: AVPlayerView {
    /// Called with ±10 for the arrow keys.
    var onSeek: ((Double) -> Void)?

    /// The jump for ← or →. Taken in the window's event monitor: the keys go to the player's inner
    /// controls, not to this view. With a modifier, or for any other key, the system player keeps them.
    private func jump(for event: NSEvent) -> Double? {
        guard event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return nil }
        switch event.keyCode {
        case 123: return -10
        case 124: return 10
        default: return nil
        }
    }

    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []
    private var hideTimer: Timer?
    private var openMenus = 0
    private var isTitleBarHidden = false

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopWatching()
        guard let window else { return }
        window.acceptsMouseMovedEvents = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .keyDown]) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, event.window === self.window else { return false }
                self.userDidSomething()
                guard let jump = self.jump(for: event), let onSeek = self.onSeek else { return false }
                onSeek(jump)
                return true
            }
            return handled ? nil : event
        }
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.openMenus += 1
                    self?.userDidSomething()
                }
            },
            center.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.openMenus = max(self.openMenus - 1, 0)
                    self.userDidSomething()
                }
            },
            center.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.setTitleBarHidden(false) }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stopWatching() }
            },
        ]
        userDidSomething()
    }

    private func stopWatching() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        hideTimer?.invalidate()
        hideTimer = nil
    }

    private func userDidSomething() {
        setTitleBarHidden(false)
        scheduleHide()
    }

    private func scheduleHide() {
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.hideIfIdle() }
        }
    }

    /// Paused or otherwise busy, it looks again later rather than waiting for the mouse.
    private func hideIfIdle() {
        guard let window else { return }
        guard player?.timeControlStatus != .paused, openMenus == 0,
              !window.styleMask.contains(.fullScreen), !isPointerOverTitleBar(window)
        else { return scheduleHide() }
        setTitleBarHidden(true)
    }

    private func isPointerOverTitleBar(_ window: NSWindow) -> Bool {
        let point = window.mouseLocationOutsideOfEventStream
        return point.y > window.contentLayoutRect.maxY && NSRect(origin: .zero, size: window.frame.size).contains(point)
    }

    /// Fades the title, toolbar and window buttons together through the view that holds them,
    /// so the video does not move as hiding the toolbar itself would make it.
    private func setTitleBarHidden(_ hidden: Bool) {
        guard hidden != isTitleBarHidden, let window else { return }
        let themeFrame = window.contentView?.superview
        var titleBar: NSView? = window.standardWindowButton(.closeButton)
        while let parent = titleBar?.superview, parent !== themeFrame { titleBar = parent }
        guard let titleBar else { return }
        isTitleBarHidden = hidden
        NSAnimationContext.runAnimationGroup { context in
            context.duration = hidden ? 0.4 : 0.15
            titleBar.animator().alphaValue = hidden ? 0 : 1
        }
    }
}
