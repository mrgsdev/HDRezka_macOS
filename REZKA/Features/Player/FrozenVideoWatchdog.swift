import AVFoundation
import CoreImage
import QuartzCore

/// «Восстанавливать застывшее видео» in Settings, off until turned on.
enum FrozenVideoRecovery {
    static let key = "recoverFrozenVideo"

    static var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: key)
    }
}

/// Notices the picture standing still while the sound plays on. The site serves each film as one big
/// `.mp4`; when the server sits on a piece of it for 9 seconds, AVFoundation drops the video track
/// (`VideoMentor signalled err=-1001` in the system log) and goes on with the audio. The item stays
/// ready and even a jump that hit it reports success, so nothing tells the app: it watches the frames
/// itself, through a video output on the item.
@MainActor
final class FrozenVideoWatchdog {
    /// What a check found.
    enum Verdict: Equatable {
        /// A frame came since the last check, at this item time.
        case frame(at: Double)
        /// No new frame yet, but not for long.
        case waiting
        /// No new frame for `threshold` seconds of playing. `stoppedAt` is the item time of the last
        /// frame shown, where the picture stopped; nil when none has come since the last reset, e.g.
        /// right after a jump the server never answered.
        case frozen(stoppedAt: Double?)
    }

    /// Seconds of playing without a new frame before the picture counts as frozen: past any hitch of
    /// the decoder, short enough not to leave the viewer with a still for long.
    static let threshold: TimeInterval = 3

    private var output: AVPlayerItemVideoOutput?
    /// The last frame shown, kept over resets and new items: it is the picture the viewer sees standing still.
    private var lastFrame: CVPixelBuffer?
    /// When the last new frame came, or when watching began; nil until the next check starts it.
    private var lastProgress: Date?
    private var lastFrameTime: Double?

    /// Watches the frames of `item` from now on; called for each new item.
    func attach(to item: AVPlayerItem) {
        // The decoder's own format, so the output needs no conversion.
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
        ])
        item.add(output)
        self.output = output
        reset()
    }

    /// Starts the count again: after a pause, a wait for data or a jump the first frame takes a moment,
    /// and the frame before it belongs to another place in the video.
    func reset() {
        lastProgress = nil
        lastFrameTime = nil
    }

    /// Called while the video plays, every quarter of a second. A freeze is reported once, when the
    /// picture has stood still for `threshold` seconds; then the count starts over.
    func check(now: Date = Date()) -> Verdict {
        guard let output else { return .waiting }
        let itemTime = output.itemTime(forHostTime: CACurrentMediaTime())
        if output.hasNewPixelBuffer(forItemTime: itemTime) {
            // Taken, so that only a later frame counts as new.
            var shownAt = CMTime.invalid
            if let frame = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: &shownAt) {
                lastFrame = frame
            }
            let seconds = shownAt.isValid ? shownAt.seconds : itemTime.seconds
            lastProgress = now
            guard seconds.isFinite else { return .waiting }
            lastFrameTime = seconds
            return .frame(at: seconds)
        }
        guard let since = lastProgress else {
            lastProgress = now
            return .waiting
        }
        guard now.timeIntervalSince(since) >= Self.threshold else { return .waiting }
        lastProgress = now
        return .frozen(stoppedAt: lastFrameTime)
    }

    /// The picture standing still, as an image to keep in view while the video loads again.
    func stillImage() -> CGImage? {
        guard let lastFrame else { return nil }
        let image = CIImage(cvPixelBuffer: lastFrame)
        return CIContext(options: [.cacheIntermediates: false]).createCGImage(image, from: image.extent)
    }
}
