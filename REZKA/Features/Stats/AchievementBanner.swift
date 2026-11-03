import AppKit
import SwiftUI

/// The banner for a new achievement: a small panel at the top of the screen with the medal turning in,
/// over every window and over the player in full screen, gone in a few seconds or on a click.
/// Several come one after another.
@MainActor
enum AchievementBanner {
    private static var queue: [Achievement] = []
    private static var panel: NSPanel?
    private static var hideTask: Task<Void, Never>?

    static func show(_ achievement: Achievement) {
        queue.append(achievement)
        if panel == nil { showNext() }
    }

    private static func showNext() {
        guard !queue.isEmpty, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let achievement = queue.removeFirst()
        let host = NSHostingView(rootView: AchievementBannerView(achievement: achievement) { hide() })
        let size = host.fittingSize
        let frame = screen.visibleFrame
        let panel = NSPanel(
            contentRect: NSRect(x: frame.midX - size.width / 2, y: frame.maxY - size.height - 16, width: size.width, height: size.height),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.contentView = host
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
        self.panel = panel
        hideTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private static func hide() {
        hideTask?.cancel()
        guard let panel else { return }
        self.panel = nil
        NSAnimationContext.runAnimationGroup { $0.duration = 0.3; panel.animator().alphaValue = 0 } completionHandler: {
            MainActor.assumeIsolated {
                panel.orderOut(nil)
                showNext()
            }
        }
    }
}

private struct AchievementBannerView: View {
    let achievement: Achievement
    let dismiss: () -> Void

    @State private var spin = -200.0

    var body: some View {
        HStack(spacing: 14) {
            MedalView(medal: achievement.medal, size: 64)
                .rotation3DEffect(.degrees(spin), axis: (x: 0, y: 1, z: 0), perspective: 0.45)
                .onAppear {
                    withAnimation(.spring(response: 1.1, dampingFraction: 0.55)) { spin = 0 }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text("Новое достижение")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Text(achievement.title)
                    .font(.headline)
                Text(achievement.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 280, alignment: .leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.3), radius: 16, y: 6)
        .padding(20)
        .contentShape(Rectangle())
        .onTapGesture(perform: dismiss)
    }
}
