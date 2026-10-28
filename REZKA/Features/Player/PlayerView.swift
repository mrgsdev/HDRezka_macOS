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
            PlayerSurface(player: controller.player)

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
        }
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
        .onAppear {
            controller.onClose = { dismiss() }
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

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = false
        view.allowsPictureInPicturePlayback = true
        // Space, arrows and J/K/L reach the player without clicking it first.
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if view.player !== player { view.player = player }
    }
}
