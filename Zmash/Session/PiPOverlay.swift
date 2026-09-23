import AVFoundation
import AVKit
import Synchronization
import SwiftUI
import ZmashKit

/// Phase 2: ride metrics in a Picture-in-Picture window while another app (e.g. YouTube) is full screen.
///
/// iOS only offers PiP for video, so a small SwiftUI card is rendered twice a second into a live
/// `AVSampleBufferDisplayLayer` stream. PiP starts automatically when leaving the app mid-ride
/// (or from the ride screen's button); its play/pause button pauses the ride.
@MainActor @Observable
final class PiPOverlay: NSObject {
    static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

    @ObservationIgnored let displayLayer = AVSampleBufferDisplayLayer()
    @ObservationIgnored private var controller: AVPictureInPictureController?
    @ObservationIgnored private var loop: Task<Void, Never>?
    @ObservationIgnored private weak var engine: SessionEngine?
    @ObservationIgnored private var units: Units = .metric
    /// Read by AVKit's (nonisolated) delegate callbacks.
    @ObservationIgnored private let paused = Mutex(false)
    #if DEBUG
    @ObservationIgnored private var possibleObservation: NSKeyValueObservation?
    #endif

    static let cardSize = CGSize(width: 480, height: 270)

    func activate(engine: SessionEngine, units: Units, autoStart: Bool) {
        guard Self.isSupported else { return }
        self.engine = engine
        self.units = units
        displayLayer.videoGravity = .resizeAspect
        // PiP needs an active playback audio session (we never play sound).
        // With ride sounds on, mix them under other audio rather than stopping it (D98).
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback,
                                                         options: Preferences.shared.rideSound ? [.mixWithOthers] : [])
        try? AVAudioSession.sharedInstance().setActive(true)

        let source = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: displayLayer, playbackDelegate: self)
        let controller = AVPictureInPictureController(contentSource: source)
        controller.canStartPictureInPictureAutomaticallyFromInline = autoStart
        controller.delegate = self
        self.controller = controller
        #if DEBUG
        possibleObservation = controller.observe(\.isPictureInPicturePossible, options: [.initial, .new]) { c, _ in
            print("[pip] possible=\(c.isPictureInPicturePossible)")
        }
        #endif

        renderFrame()
        loop = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                self?.renderFrame()
            }
        }
    }

    func deactivate() {
        loop?.cancel()
        loop = nil
        controller?.stopPictureInPicture()
        controller = nil
        displayLayer.sampleBufferRenderer.flush(removingDisplayedImage: true, completionHandler: nil)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Manual start from the ride screen (must come from a user action).
    func toggle() {
        guard let controller else { return }
        if controller.isPictureInPictureActive {
            controller.stopPictureInPicture()
            return
        }
        lastError = nil
        retried = false
        renderFrame()
        // Start on the next run loop turn, after the fresh frame is enqueued.
        DispatchQueue.main.async { controller.startPictureInPicture() }
    }

    /// Last start failure, shown briefly on the ride screen (helps diagnose on device).
    private(set) var lastError: String?
    @ObservationIgnored private var retried = false

    fileprivate func startFailed(_ error: Error) {
        let ns = error as NSError
        if !retried, let controller {
            retried = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { controller.startPictureInPicture() }
            return
        }
        lastError = "Floating window unavailable (\(ns.domain) \(ns.code))"
        Diagnostics.log("pip", lastError ?? "")
    }

    // MARK: Rendering

    private func renderFrame() {
        guard let engine else { return }
        paused.withLock { $0 = engine.isPaused }
        let card = PiPCard(engine: engine, units: units)
            .frame(width: Self.cardSize.width, height: Self.cardSize.height)
            .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 2
        guard let image = renderer.cgImage, let buffer = Self.sampleBuffer(from: image) else { return }
        if displayLayer.sampleBufferRenderer.status == .failed {
            displayLayer.sampleBufferRenderer.flush()
        }
        displayLayer.sampleBufferRenderer.enqueue(buffer)
        #if DEBUG
        frames += 1
        if frames % 60 == 1 {
            let r = displayLayer.sampleBufferRenderer
            print("[pip] frame \(frames) \(image.width)x\(image.height) status=\(r.status.rawValue) error=\(String(describing: r.error)) layer=\(displayLayer.frame.size) app=\(UIApplication.shared.applicationState.rawValue)")
        }
        #endif
    }
    #if DEBUG
    @ObservationIgnored private var frames = 0
    #endif

    static func sampleBuffer(from image: CGImage) -> CMSampleBuffer? {
        let width = image.width, height = image.height
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pixelBuffer) == kCVReturnSuccess,
              let pb = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pb, [])
        defer { CVPixelBufferUnlockBaseAddress(pb, []) }
        guard let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var format: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &format) == noErr,
              let format else { return nil }
        let now = CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 60)
        var timing = CMSampleTimingInfo(duration: CMTime(seconds: 1, preferredTimescale: 60),
                                        presentationTimeStamp: now, decodeTimeStamp: now)
        var sample: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb, formatDescription: format,
                                                       sampleTiming: &timing, sampleBufferOut: &sample) == noErr,
              let sample else { return nil }
        // No timebase on the layer: ask for each frame to be shown as soon as it arrives.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
            attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
        }
        return sample
    }
}

extension PiPOverlay: AVPictureInPictureControllerDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                failedToStartPictureInPictureWithError error: Error) {
        print("[pip] failed to start: \(error)")
        Task { @MainActor in self.startFailed(error) }
    }

    nonisolated func pictureInPictureControllerDidStartPictureInPicture(_ controller: AVPictureInPictureController) {
        print("[pip] started")
    }
}

extension PiPOverlay: AVPictureInPictureSampleBufferPlaybackDelegate {
    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, setPlaying playing: Bool) {
        Task { @MainActor in
            guard let engine = self.engine, engine.isPaused == playing else { return }
            engine.handle(.pauseToggle)
            self.renderFrame()
        }
    }

    nonisolated func pictureInPictureControllerTimeRangeForPlayback(_ controller: AVPictureInPictureController) -> CMTimeRange {
        // A long finite range: infinite ranges make AVKit misbehave (see UIPiPView issue #17).
        CMTimeRange(start: .zero, duration: CMTime(value: 3600 * 24, timescale: 1))
    }

    nonisolated func pictureInPictureControllerIsPlaybackPaused(_ controller: AVPictureInPictureController) -> Bool {
        paused.withLock { $0 }
    }

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController,
                                                didTransitionToRenderSize newRenderSize: CMVideoDimensions) {}

    nonisolated func pictureInPictureController(_ controller: AVPictureInPictureController, skipByInterval skipInterval: CMTime,
                                                completion completionHandler: @escaping @Sendable () -> Void) {
        completionHandler()
    }
}

/// The PiP card: speed first, then watts, cadence, time and grade. Always dark.
private struct PiPCard: View {
    let engine: SessionEngine
    let units: Units

    var body: some View {
        let ink = Color(white: 0.95)
        let dim = Color(white: 0.95).opacity(0.5)
        let speed = units.speed(engine.speedKph)
        ZStack {
            Color(red: 0x0B / 255, green: 0x0B / 255, blue: 0x0C / 255)
            HStack(alignment: .center, spacing: 28) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(speed < 10 ? String(format: "%.1f", speed) : String(format: "%.0f", speed))
                        .font(.system(size: 110, weight: .semibold, design: .rounded))
                        .foregroundStyle(ink)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(units.speedUnit).font(.system(size: 20, weight: .medium, design: .rounded)).foregroundStyle(dim)
                }
                VStack(alignment: .leading, spacing: 10) {
                    row(engine.powerW.map(String.init) ?? "—", "w", ink, dim)
                    row(engine.cadenceRpm.map(String.init) ?? "—", "rpm", ink, dim)
                    row(TimeFormat.clock(Int(engine.elapsed)), engine.isPaused ? "paused" : "time", ink, dim)
                    row(String(format: "%+.1f", engine.terrainGrade), "% · gear \(engine.controls.gear)",
                        Design.accent(forGrade: engine.terrainGrade), dim)
                }
            }
            .padding(24)
        }
    }

    private func row(_ value: String, _ unit: String, _ ink: Color, _ dim: Color) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(value).font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit()).foregroundStyle(ink)
            Text(unit).font(.system(size: 16, weight: .medium, design: .rounded)).foregroundStyle(dim)
        }
    }
}

/// Hosts the PiP source layer in the view hierarchy (required by AVKit). It sits behind everything.
struct PiPLayerHost: UIViewRepresentable {
    let layer: AVSampleBufferDisplayLayer

    func makeUIView(context: Context) -> LayerView {
        let view = LayerView()
        view.isUserInteractionEnabled = false
        view.hosted = layer
        view.layer.addSublayer(layer)
        return view
    }

    func updateUIView(_ uiView: LayerView, context: Context) {}

    /// Keeps the layer sized to the view on every layout pass: `updateUIView` can run before layout,
    /// and a zero-sized source layer makes PiP refuse to start (PGPegasusErrorDomain −1003).
    final class LayerView: UIView {
        var hosted: CALayer?

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            hosted?.frame = bounds
            CATransaction.commit()
        }
    }
}
