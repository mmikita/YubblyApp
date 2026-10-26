#if canImport(FlutterMacOS)
import FlutterMacOS
#elseif canImport(Flutter)
import Flutter
#endif
import AVFoundation
import Foundation
import os

/// Signal-routing mathematics shared by the macOS and iOS adapters.
///
/// This is a direct port of the Android `MixerMath` so both playback engines
/// produce the same envelopes for the same session settings.
enum AppleMixerMath {
    struct Gains {
        let aLeft: Double
        let aRight: Double
        let bLeft: Double
        let bRight: Double
    }

    static func clamp(_ value: Double, _ minimum: Double, _ maximum: Double) -> Double {
        guard value.isFinite else { return minimum }
        return max(minimum, min(maximum, value))
    }

    static func gains(
        mode: String,
        curve: String,
        seconds: Double,
        period: Double,
        contrast: Double,
        phase: Double,
        microHz: Double,
        depth: Double,
        swapped: Bool
    ) -> Gains {
        let period = clamp(period, 2, 300)
        let contrast = clamp(contrast, 1, 5)
        let depth = clamp(depth, 0, 0.5)
        let microHz = clamp(microHz, 0, 2)
        let u = 0.5 * (1 + sin(2 * .pi * seconds / period + phase * .pi / 180))
        let power = curve != "linear"
        var a = pow(power ? cos(.pi * u / 2) : 1 - u, contrast)
        var b = pow(power ? sin(.pi * u / 2) : u, contrast)
        let norm = power ? sqrt(a * a + b * b) : a + b
        a /= max(norm, 1e-12)
        b /= max(norm, 1e-12)
        let breath = depth * sin(2 * .pi * microHz * seconds)
        // Constant headroom bounds the sum in each ear even for correlated
        // full-scale inputs, matching the Android mixer.
        let headroom = (power ? 1 / sqrt(2) : 1) / (1 + depth)
        a *= (1 + breath) * headroom
        b *= (1 - breath) * headroom

        var result: Gains
        switch mode {
        case "split":
            result = Gains(aLeft: 1, aRight: 0, bLeft: 0, bRight: 1)
        case "mono":
            result = Gains(aLeft: a, aRight: a, bLeft: b, bRight: b)
        case "together":
            result = Gains(aLeft: 0.5, aRight: 0.5, bLeft: 0.5, bRight: 0.5)
        default:
            result = Gains(aLeft: a, aRight: b, bLeft: b, bRight: a)
        }
        if swapped {
            result = Gains(
                aLeft: result.aRight,
                aRight: result.aLeft,
                bLeft: result.bRight,
                bRight: result.bLeft
            )
        }
        return result
    }

    /// Positive offset chooses a later source fragment from B.
    static func secondaryPosition(_ primary: Int64, _ offset: Int) -> Int64 {
        max(0, primary + Int64(offset))
    }

    static func correctedSpeed(_ speed: Double, drift: Int64) -> Double {
        if abs(drift) < 25 { return speed }
        let correction = clamp(Double(drift) / 5000, -0.025, 0.025)
        return speed * (1 - correction)
    }
}

/// Small unfair lock wrapper. The receive side runs on AVFoundation's audio
/// thread, so gain targets must not be read through Foundation locks.
final class AppleUnfairLock {
    private var lock = os_unfair_lock_s()

    func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return body()
    }
}


/// One tap per language stream. It folds the decoded source to mono, routes it
/// with independent left/right gains and smooths gain changes over 10 ms.
final class AppleStereoMatrixTap {
    private let lock = AppleUnfairLock()
    private var targetLeft = 0.0
    private var targetRight = 0.0
    private var currentLeft = 0.0
    private var currentRight = 0.0
    private var sampleRate = 44_100.0
    private var channels = 2
    private var nonInterleaved = true
    private var isFloat = true
    private var bitsPerChannel = 32
    private var unsupportedFormatLogged = false

    init() {}

    func setGains(left: Double, right: Double) {
        lock.withLock {
            targetLeft = left
            targetRight = right
        }
    }

    func resetSmoothing() {
        currentLeft = 0
        currentRight = 0
    }

    func prepare(format: AudioStreamBasicDescription) {
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        channels = max(1, Int(format.mChannelsPerFrame))
        nonInterleaved = format.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        isFloat = format.mFormatFlags & kAudioFormatFlagIsFloat != 0
        bitsPerChannel = Int(format.mBitsPerChannel)
        currentLeft = 0
        currentRight = 0
        unsupportedFormatLogged = false
    }

    func process(
        tap: MTAudioProcessingTap,
        requestedFrames: CMItemCount,
        bufferList: UnsafeMutablePointer<AudioBufferList>,
        framesOut: UnsafeMutablePointer<CMItemCount>,
        flagsOut: UnsafeMutablePointer<MTAudioProcessingTapFlags>
    ) {
        let status = MTAudioProcessingTapGetSourceAudio(
            tap,
            requestedFrames,
            bufferList,
            flagsOut,
            nil,
            framesOut
        )
        guard status == noErr else { return }
        let frames = Int(framesOut.pointee)
        guard frames > 0 else { return }
        let buffers = UnsafeMutableAudioBufferListPointer(bufferList)
        guard !buffers.isEmpty else { return }
        let targets = lock.withLock { (targetLeft, targetRight) }
        let alpha = 1 - exp(-1.0 / (0.010 * sampleRate))

        if isFloat && bitsPerChannel == 32 {
            renderFloat(
                frames: frames,
                buffers: buffers,
                alpha: alpha,
                leftTarget: targets.0,
                rightTarget: targets.1
            )
        } else if !isFloat && bitsPerChannel == 16 {
            renderInt16(
                frames: frames,
                buffers: buffers,
                alpha: alpha,
                leftTarget: targets.0,
                rightTarget: targets.1
            )
        } else if !unsupportedFormatLogged {
            unsupportedFormatLogged = true
            NSLog(
                "Yubbly: unsupported tap format (float=%@, bits=%d); "
                    + "audio continues without stereo routing.",
                isFloat ? "yes" : "no",
                bitsPerChannel
            )
        }
    }

    private func smooth(_ alpha: Double, _ left: Double, _ right: Double) {
        currentLeft += alpha * (left - currentLeft)
        currentRight += alpha * (right - currentRight)
    }

    private func renderFloat(
        frames: Int,
        buffers: UnsafeMutableAudioBufferListPointer,
        alpha: Double,
        leftTarget: Double,
        rightTarget: Double
    ) {
        // AVPlayer decodes AAC to planar float32 stereo on Apple platforms.
        if nonInterleaved && channels == 2 && buffers.count >= 2 {
            guard
                let left = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                let right = buffers[1].mData?.assumingMemoryBound(to: Float.self)
            else { return }
            for frame in 0..<frames {
                let mono = (Double(left[frame]) + Double(right[frame])) * 0.5
                smooth(alpha, leftTarget, rightTarget)
                left[frame] = Float(AppleMixerMath.clamp(mono * currentLeft, -1, 1))
                right[frame] = Float(AppleMixerMath.clamp(mono * currentRight, -1, 1))
            }
            return
        }

        guard let raw = buffers[0].mData else { return }
        if channels == 1 {
            let monoBuffer = raw.assumingMemoryBound(to: Float.self)
            for frame in 0..<frames {
                let mono = Double(monoBuffer[frame])
                smooth(alpha, leftTarget, rightTarget)
                let combined = (currentLeft + currentRight) * 0.5
                monoBuffer[frame] = Float(AppleMixerMath.clamp(mono * combined, -1, 1))
            }
            return
        }

        guard channels == 2 else {
            if !unsupportedFormatLogged {
                unsupportedFormatLogged = true
                NSLog(
                    "Yubbly: %d-channel audio is passed through without stereo routing.",
                    channels
                )
            }
            return
        }
        let interleaved = raw.assumingMemoryBound(to: Float.self)
        for frame in 0..<frames {
            let base = frame * 2
            let mono = (Double(interleaved[base]) + Double(interleaved[base + 1])) * 0.5
            smooth(alpha, leftTarget, rightTarget)
            interleaved[base] = Float(AppleMixerMath.clamp(mono * currentLeft, -1, 1))
            interleaved[base + 1] = Float(AppleMixerMath.clamp(mono * currentRight, -1, 1))
        }
    }

    private func renderInt16(
        frames: Int,
        buffers: UnsafeMutableAudioBufferListPointer,
        alpha: Double,
        leftTarget: Double,
        rightTarget: Double
    ) {
        if nonInterleaved && channels == 2 && buffers.count >= 2 {
            guard
                let left = buffers[0].mData?.assumingMemoryBound(to: Int16.self),
                let right = buffers[1].mData?.assumingMemoryBound(to: Int16.self)
            else { return }
            for frame in 0..<frames {
                let mono = (Double(left[frame]) + Double(right[frame])) / 65_536
                smooth(alpha, leftTarget, rightTarget)
                left[frame] = int16Sample(mono * currentLeft)
                right[frame] = int16Sample(mono * currentRight)
            }
            return
        }

        guard let raw = buffers[0].mData else { return }
        if channels == 1 {
            let monoBuffer = raw.assumingMemoryBound(to: Int16.self)
            for frame in 0..<frames {
                let mono = Double(monoBuffer[frame]) / 32_768
                smooth(alpha, leftTarget, rightTarget)
                let combined = (currentLeft + currentRight) * 0.5
                monoBuffer[frame] = int16Sample(mono * combined)
            }
            return
        }

        guard channels == 2 else {
            if !unsupportedFormatLogged {
                unsupportedFormatLogged = true
                NSLog(
                    "Yubbly: %d-channel integer audio is passed through without stereo routing.",
                    channels
                )
            }
            return
        }
        let interleaved = raw.assumingMemoryBound(to: Int16.self)
        for frame in 0..<frames {
            let base = frame * 2
            let mono = (Double(interleaved[base]) + Double(interleaved[base + 1])) / 65_536
            smooth(alpha, leftTarget, rightTarget)
            interleaved[base] = int16Sample(mono * currentLeft)
            interleaved[base + 1] = int16Sample(mono * currentRight)
        }
    }

    private func int16Sample(_ value: Double) -> Int16 {
        let clamped = AppleMixerMath.clamp(value, -1, 1)
        return Int16((clamped * 32_767).rounded())
    }
}

/// Creates and attaches the processing tap to a loaded audio track.
func makeAppleAudioTap(processor: AppleStereoMatrixTap) -> MTAudioProcessingTap? {
    var callbacks = MTAudioProcessingTapCallbacks(
        version: kMTAudioProcessingTapCallbacksVersion_0,
        clientInfo: Unmanaged.passUnretained(processor).toOpaque(),
        init: { _, clientInfo, storage in
            storage.pointee = clientInfo
        },
        finalize: { _ in },
        prepare: { tap, _, format in
            let processor = Unmanaged<AppleStereoMatrixTap>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            processor.prepare(format: format.pointee)
        },
        unprepare: { _ in },
        process: { tap, numberFrames, _, bufferList, numberFramesOut, flagsOut in
            let processor = Unmanaged<AppleStereoMatrixTap>
                .fromOpaque(MTAudioProcessingTapGetStorage(tap))
                .takeUnretainedValue()
            processor.process(
                tap: tap,
                requestedFrames: numberFrames,
                bufferList: bufferList,
                framesOut: numberFramesOut,
                flagsOut: flagsOut
            )
        }
    )
    var tap: MTAudioProcessingTap?
    let status = MTAudioProcessingTapCreate(
        kCFAllocatorDefault,
        &callbacks,
        kMTAudioProcessingTapCreationFlag_PostEffects,
        &tap
    )
    if status != noErr {
        NSLog("Yubbly: MTAudioProcessingTapCreate failed with status %d", status)
        return nil
    }
    return tap
}



/// Two AVPlayers, one per language. Each item gets an audio mix with a
/// MTAudioProcessingTap; AVFoundation sums the two player outputs.
final class ApplePlaybackEngine {
    private static let sessionKey = "yubbly.playback.session"
    private static let positionKey = "yubbly.playback.position"
    private static let historyKey = "yubbly.playback.history"
    private static let legacyHistoryKey = "yubbly.history"
    private static let userAgent = "com.google.android.youtube/20.10.38 (Linux; U; Android 11) gzip"

    private let defaults = UserDefaults.standard
    private let primaryPlayer = AVPlayer()
    private let secondaryPlayer = AVPlayer()
    private let matrixA = AppleStereoMatrixTap()
    private let matrixB = AppleStereoMatrixTap()

    private var itemA: AVPlayerItem?
    private var itemB: AVPlayerItem?
    private var tapA: MTAudioProcessingTap?
    private var tapB: MTAudioProcessingTap?
    private var itemObservers: [NSObjectProtocol] = []
    private var sessionObservers: [NSObjectProtocol] = []
    private var ticker: Timer?

    private var session: [String: Any] = [:]
    private var mix: [String: Any] = [:]
    private var journal: [String: [String: Any]] = [:]
    private var wanted = false
    private var loaded = false
    private var hasPlayed = false
    private var ended = false
    private var tapsAttemptedA = false
    private var tapsAttemptedB = false
    private var prerollReady = false
    private var prerollInFlight = false
    private var prerollGeneration = 0
    private var secondaryLeadInPrerolled = false
    private var secondaryLeadInPrerollInFlight = false
    private var seekGeneration = 0
    private var seeksPending = 0
    private var savedPosition: Int64 = 0
    private var drift: Int64 = 0
    private var error = ""
    private var lastTick: TimeInterval = 0
    private var lastSave: TimeInterval = 0
    private var lastCorrection: TimeInterval = 0

    init() {
        restore()
        for player in [primaryPlayer, secondaryPlayer] {
            player.actionAtItemEnd = .pause
            player.automaticallyWaitsToMinimizeStalling = true
        }
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
        installAudioSessionObservers()
    }

    deinit {
        ticker?.invalidate()
        removeItemObservers()
        for observer in sessionObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        persist()
    }

    // MARK: - Channel commands

    func load(_ args: [String: Any]) throws {
        persist()
        stopPair()
        error = ""
        hasPlayed = false
        ended = false
        session = args["session"] as? [String: Any] ?? [:]
        mix = session["mix"] as? [String: Any] ?? [:]

        let urlA = try streamURL(args["urlA"])
        let urlB = try streamURL(args["urlB"])
        activateAudioSession()

        removeItemObservers()
        tapA = nil
        tapB = nil
        tapsAttemptedA = false
        tapsAttemptedB = false
        matrixA.resetSmoothing()
        matrixB.resetSmoothing()

        let first = makeItem(url: urlA)
        let second = makeItem(url: urlB)
        itemA = first
        itemB = second
        primaryPlayer.replaceCurrentItem(with: first)
        secondaryPlayer.replaceCurrentItem(with: second)
        observe(first)
        observe(second)
        attachTap(to: first, matrix: matrixA, isPrimary: true)
        attachTap(to: second, matrix: matrixB, isPrimary: false)

        loaded = true
        configure(mix)
        let requested = number(args["positionMs"], fallback: 0, minimum: 0, maximum: 604_800_000)
        seekBoth(to: Int64(requested.rounded()))
        prerollReady = false
        prerollGeneration += 1
        wanted = true
        saveState(recordCurrent: false)
        reconcile()
    }

    func play() {
        guard loaded else { return }
        error = ""
        wanted = true
        if ended { seekPair(0) }
        reconcile()
    }

    func pause() {
        wanted = false
        pausePair()
        prerollReady = false
        prerollInFlight = false
        prerollGeneration += 1
        secondaryLeadInPrerolled = false
        secondaryLeadInPrerollInFlight = false
        persist()
    }

    func stop() {
        wanted = false
        persist()
        pausePair()
        primaryPlayer.replaceCurrentItem(with: nil)
        secondaryPlayer.replaceCurrentItem(with: nil)
        removeItemObservers()
        itemA = nil
        itemB = nil
        tapA = nil
        tapB = nil
        loaded = false
        prerollReady = false
        prerollInFlight = false
        prerollGeneration += 1
        secondaryLeadInPrerolled = false
        secondaryLeadInPrerollInFlight = false
        seekGeneration += 1
        seeksPending = 0
        deactivateAudioSession()
    }

    func seek(_ positionMs: Int64) {
        guard loaded else { return }
        seekPair(positionMs)
    }

    func configure(_ config: [String: Any]) {
        let previousOffset = offset()
        mix = config
        session["mix"] = mix
        let volume = floatValue("volume", fallback: 0.7, minimum: 0, maximum: 1)
        primaryPlayer.volume = Float(volume)
        secondaryPlayer.volume = Float(volume)

        if loaded && wanted {
            if primaryPlayer.rate > 0 {
                primaryPlayer.rate = Float(speed())
            }
            if secondaryPlayer.rate > 0 && !inLeadIn() {
                secondaryPlayer.rate = Float(
                    AppleMixerMath.correctedSpeed(speed(), drift: drift)
                )
            }
        }
        if loaded && previousOffset != offset() {
            seekPair(currentPositionMs())
        }
        updateGains()
    }

    func snapshot() -> [String: Any] {
        var result: [String: Any] = [:]
        result["session"] = session
        result["loaded"] = loaded
        result["positionMs"] = Int(loaded ? currentPositionMs() : savedPosition)
        result["durationMs"] = Int(loaded ? durationMs() : 0)
        let pairPlaying = isPairPlaying()
        result["playing"] = pairPlaying
        result["buffering"] = wanted && loaded && !pairPlaying
        result["driftMs"] = Int(drift)
        result["error"] = error
        return result
    }

    func history() -> [[String: Any]] {
        Array(journal.values)
    }

    func clearHistory() {
        journal.removeAll()
        hasPlayed = false
        saveState(recordCurrent: false)
    }

    // MARK: - Playback

    private func reconcile() {
        guard loaded, wanted else {
            pausePair()
            return
        }
        guard tapsAttemptedA, tapsAttemptedB,
              let first = itemA, let second = itemB,
              first.status == .readyToPlay, second.status == .readyToPlay,
              seeksPending == 0
        else {
            pausePair()
            return
        }
        if !prerollReady {
            if !prerollInFlight {
                requestPreroll()
            }
            return
        }
        if primaryPlayer.timeControlStatus == .paused {
            primaryPlayer.playImmediately(atRate: Float(speed()))
        }
        if inLeadIn() {
            startSecondaryInLeadIn()
        } else if secondaryPlayer.timeControlStatus == .paused {
            secondaryPlayer.playImmediately(
                atRate: Float(AppleMixerMath.correctedSpeed(speed(), drift: drift))
            )
        }
    }

    /// B is muted by the tap and paused until its timeline starts. Preroll it
    /// while A plays so the first B syllable is not delayed by ~0.5 s.
    private func startSecondaryInLeadIn() {
        if secondaryPlayer.timeControlStatus != .paused {
            secondaryPlayer.pause()
        }
        guard !secondaryLeadInPrerolled, !secondaryLeadInPrerollInFlight else {
            return
        }
        let generation = prerollGeneration
        secondaryLeadInPrerollInFlight = true
        secondaryPlayer.preroll(atRate: Float(speed())) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.prerollGeneration == generation else { return }
                self.secondaryLeadInPrerollInFlight = false
                self.secondaryLeadInPrerolled = true
                self.reconcile()
            }
        }
    }

    /// Pausing and resuming an AVPlayer costs roughly half a second of audio
    /// startup on macOS/iOS. Prerolling both players hides that latency so the
    /// two media clocks resume together.
    private func requestPreroll() {
        guard loaded, let first = itemA, let second = itemB,
              first.status == .readyToPlay, second.status == .readyToPlay
        else { return }
        prerollGeneration += 1
        let generation = prerollGeneration
        prerollInFlight = true
        prerollReady = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.prerollGeneration == generation else { return }
            self.performPreroll(generation: generation)
        }
    }

    private func performPreroll(generation: Int) {
        guard loaded, let first = itemA, let second = itemB,
              first.status == .readyToPlay, second.status == .readyToPlay
        else {
            prerollInFlight = false
            return
        }
        var remaining = 2
        let rate = Float(speed())
        let completion: (Bool) -> Void = { _ in
            DispatchQueue.main.async { [weak self] in
                guard let self, self.prerollGeneration == generation else { return }
                remaining -= 1
                if remaining <= 0 {
                    self.prerollInFlight = false
                    self.prerollReady = true
                    self.secondaryLeadInPrerolled = true
                    self.reconcile()
                }
            }
        }
        primaryPlayer.preroll(atRate: rate, completionHandler: completion)
        secondaryPlayer.preroll(atRate: rate, completionHandler: completion)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.prerollGeneration == generation,
                  self.prerollInFlight
            else { return }
            self.prerollInFlight = false
            self.prerollReady = true
            self.reconcile()
        }
    }

    private func pausePair() {
        primaryPlayer.pause()
        secondaryPlayer.pause()
    }

    private func stopPair() {
        wanted = false
        pausePair()
        primaryPlayer.replaceCurrentItem(with: nil)
        secondaryPlayer.replaceCurrentItem(with: nil)
        removeItemObservers()
        itemA = nil
        itemB = nil
        tapA = nil
        tapB = nil
        loaded = false
        prerollReady = false
        prerollInFlight = false
        prerollGeneration += 1
        secondaryLeadInPrerolled = false
        secondaryLeadInPrerollInFlight = false
        seekGeneration += 1
        seeksPending = 0
    }

    private func seekPair(_ positionMs: Int64) {
        guard loaded else { return }
        pausePair()
        seekBoth(to: positionMs)
        prerollReady = false
        prerollGeneration += 1
        saveState(recordCurrent: false)
        reconcile()
    }

    private func seekBoth(to positionMs: Int64) {
        let duration = durationMs()
        let maximum = duration > 0 ? duration : 604_800_000
        let target = max(0, min(positionMs, maximum))
        savedPosition = target
        ended = false
        seekGeneration += 1
        let generation = seekGeneration
        seeksPending = 2
        prerollReady = false
        prerollGeneration += 1
        secondaryLeadInPrerolled = false
        secondaryLeadInPrerollInFlight = false
        let secondaryTarget = AppleMixerMath.secondaryPosition(target, offset())
        primaryPlayer.seek(
            to: time(target),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.seekCompleted(generation)
        }
        secondaryPlayer.seek(
            to: time(secondaryTarget),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        ) { [weak self] _ in
            self?.seekCompleted(generation)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.seekGeneration == generation,
                  self.seeksPending > 0
            else { return }
            self.seeksPending = 0
            self.reconcile()
        }
        lastCorrection = Date().timeIntervalSince1970
        updateGains()
    }

    private func seekCompleted(_ generation: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.seekGeneration == generation else { return }
            self.seeksPending = max(0, self.seeksPending - 1)
            if self.seeksPending == 0 {
                self.reconcile()
            }
        }
    }

    private func tick() {
        let now = Date().timeIntervalSince1970
        guard loaded else {
            lastTick = now
            return
        }
        if checkItemErrors() {
            lastTick = now
            return
        }
        if wanted { reconcile() }

        // Some YouTube MP4 audio streams carry a doubled container duration
        // and then 19 additional seconds of silence. The video metadata from
        // YouTube is authoritative for the session's visible end.
        if !ended, metadataDurationMs() > 0,
           currentPositionMs() >= metadataDurationMs() - 80 {
            handleEnd()
            lastTick = now
            return
        }

        let position = currentPositionMs()
        let target = AppleMixerMath.secondaryPosition(position, offset())
        let leadIn = inLeadIn()
        drift = leadIn ? 0 : secondaryPositionMs() - target
        let primaryPlaying = primaryPlayer.timeControlStatus == .playing
        let secondaryPlaying = secondaryPlayer.timeControlStatus == .playing

        if primaryPlaying && (secondaryPlaying || leadIn) {
            hasPlayed = true
            let elapsed = lastTick == 0 ? 0 : min(250, (now - lastTick) * 1000)
            record(completed: false, listenedMs: Int64(elapsed.rounded()))

            if !leadIn, abs(drift) > 150, now - lastCorrection > 1.5 {
                let target = currentPositionMs()
                pausePair()
                seekBoth(to: target)
                lastCorrection = now
            } else if !leadIn, secondaryPlayer.rate > 0 {
                let corrected = AppleMixerMath.correctedSpeed(speed(), drift: drift)
                if abs(Double(secondaryPlayer.rate) - corrected) > 0.001 {
                    secondaryPlayer.rate = Float(corrected)
                }
            }
        }
        updateGains()
        if now - lastSave > 5 {
            persist()
            lastSave = now
        }
        lastTick = now
    }

    private func updateGains() {
        let gains = AppleMixerMath.gains(
            mode: string("mode", fallback: "orbit"),
            curve: string("curve", fallback: "equal-power"),
            seconds: Double(currentPositionMs()) / 1000,
            period: floatValue("period", fallback: 60, minimum: 2, maximum: 300),
            contrast: floatValue("contrast", fallback: 1, minimum: 1, maximum: 5),
            phase: floatValue("phase", fallback: 0, minimum: 0, maximum: 360),
            microHz: floatValue("microHz", fallback: 0.3, minimum: 0, maximum: 2),
            depth: floatValue("depth", fallback: 0.04, minimum: 0, maximum: 0.5),
            swapped: boolValue("swapped")
        )
        matrixA.setGains(left: gains.aLeft, right: gains.aRight)
        let leadIn = inLeadIn()
        matrixB.setGains(
            left: leadIn ? 0 : gains.bLeft,
            right: leadIn ? 0 : gains.bRight
        )
    }

    private func inLeadIn() -> Bool {
        currentPositionMs() + Int64(offset()) < 0
    }

    private func isPairPlaying() -> Bool {
        guard loaded else { return false }
        let primaryPlaying = primaryPlayer.timeControlStatus == .playing
        let secondaryPlaying = secondaryPlayer.timeControlStatus == .playing
        return primaryPlaying && (secondaryPlaying || inLeadIn())
    }



    // MARK: - AVFoundation wiring

    private func makeItem(url: URL) -> AVPlayerItem {
        let asset = AVURLAsset(
            url: url,
            options: [
                "AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": Self.userAgent],
            ]
        )
        let item = AVPlayerItem(asset: asset)
        item.audioTimePitchAlgorithm = .spectral
        return item
    }

    private func attachTap(
        to item: AVPlayerItem,
        matrix: AppleStereoMatrixTap,
        isPrimary: Bool
    ) {
        guard let asset = item.asset as? AVURLAsset else {
            markTapAttempted(isPrimary)
            return
        }
        asset.loadTracks(withMediaType: .audio) { [weak self, weak item] tracks, failure in
            DispatchQueue.main.async {
                guard let self, let item else { return }
                let isCurrent = isPrimary ? self.itemA === item : self.itemB === item
                guard isCurrent else { return }
                if let track = tracks?.first, let tap = makeAppleAudioTap(processor: matrix) {
                    let parameters = AVMutableAudioMixInputParameters(track: track)
                    parameters.audioTapProcessor = tap
                    let audioMix = AVMutableAudioMix()
                    audioMix.inputParameters = [parameters]
                    item.audioMix = audioMix
                    if isPrimary {
                        self.tapA = tap
                    } else {
                        self.tapB = tap
                    }
                } else if let failure {
                    NSLog(
                        "Yubbly: could not load audio track: %@",
                        failure.localizedDescription
                    )
                }
                self.markTapAttempted(isPrimary)
                self.reconcile()
            }
        }
    }

    private func markTapAttempted(_ isPrimary: Bool) {
        if isPrimary {
            tapsAttemptedA = true
        } else {
            tapsAttemptedB = true
        }
    }

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        itemObservers.append(
            center.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] _ in
                self?.handleEnd()
            }
        )
        itemObservers.append(
            center.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime,
                object: item,
                queue: .main
            ) { [weak self] notification in
                self?.handleFailure(
                    notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
                )
            }
        )
    }

    private func removeItemObservers() {
        for observer in itemObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        itemObservers.removeAll()
    }

    private func handleEnd() {
        guard loaded, !ended else { return }
        ended = true
        wanted = false
        pausePair()
        record(completed: true, listenedMs: 0)
        persist()
    }

    private func handleFailure(_ failure: Error?) {
        guard error.isEmpty else { return }
        let detail = Self.failureDescription(failure)
        error = "Nie udało się odtworzyć strumienia (\(detail)). "
            + "Wciśnij Odśwież, aby pobrać nowe adresy YouTube. "
            + "Jeśli błąd się powtarza, wybierz inny film lub spróbuj później."
        wanted = false
        pausePair()
        persist()
    }

    /// AVFoundation often hides the useful error behind `unknown error` and a
    /// chain of underlying `NSError`s. Pick the first concrete cause so the UI
    /// can explain an expired/blocked stream instead of showing a dead end.
    private static func failureDescription(_ failure: Error?) -> String {
        guard let failure else { return "brak szczegółów" }
        let root = failure as NSError
        var chain: [NSError] = []
        var current: NSError? = root
        while let node = current, chain.count < 6 {
            chain.append(node)
            current = node.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let descriptions = chain.compactMap { node -> String? in
            guard let text = node.userInfo[NSLocalizedDescriptionKey] as? String,
                  !text.isEmpty else { return nil }
            return text
        }
        if descriptions.contains(where: {
            $0.localizedCaseInsensitiveContains("HTTP 403")
        }) || chain.contains(where: {
            $0.domain == "CoreMediaErrorDomain" && $0.code == -12660
        }) {
            return "HTTP 403 – YouTube odrzucił lub ograniczył strumień"
        }
        if chain.contains(where: {
            $0.domain == NSURLErrorDomain
                && $0.code == NSURLErrorNotConnectedToInternet
        }) {
            return "brak połączenia z internetem"
        }
        if chain.contains(where: {
            $0.domain == NSURLErrorDomain && $0.code == NSURLErrorTimedOut
        }) {
            return "przekroczono czas oczekiwania na YouTube"
        }
        if let meaningful = descriptions.first(where: {
            $0.lowercased() != "unknown error"
        }) {
            return meaningful
        }
        return "nieznany błąd AVFoundation (kod \(root.code))"
    }

    private func checkItemErrors() -> Bool {
        if itemA?.status == .failed || itemB?.status == .failed {
            handleFailure(itemA?.error ?? itemB?.error)
            return true
        }
        return false
    }

    private func activateAudioSession() {
        #if os(iOS)
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .default)
            try audioSession.setActive(true)
        } catch {
            NSLog("Yubbly: AVAudioSession setup failed: %@", error.localizedDescription)
        }
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS)
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        #endif
    }

    private func installAudioSessionObservers() {
        #if os(iOS)
        let center = NotificationCenter.default
        let audioSession = AVAudioSession.sharedInstance()
        sessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard
                    let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                    let type = AVAudioSession.InterruptionType(rawValue: raw),
                    type == .began
                else { return }
                self?.wanted = false
                self?.pausePair()
                self?.persist()
            }
        )
        sessionObservers.append(
            center.addObserver(
                forName: AVAudioSession.routeChangeNotification,
                object: audioSession,
                queue: .main
            ) { [weak self] notification in
                guard
                    let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                    let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
                    reason == .oldDeviceUnavailable
                else { return }
                self?.wanted = false
                self?.pausePair()
                self?.persist()
            }
        )
        #endif
    }

    // MARK: - Persistence

    private func restore() {
        if let raw = defaults.string(forKey: Self.sessionKey),
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let restored = object as? [String: Any] {
            session = restored
            mix = restored["mix"] as? [String: Any] ?? [:]
        }
        savedPosition = Int64(defaults.integer(forKey: Self.positionKey))
        if let raw = defaults.string(forKey: Self.historyKey),
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let restored = object as? [String: Any] {
            for (key, value) in restored {
                if let entry = value as? [String: Any] {
                    journal[key] = entry
                }
            }
        }
        if journal.isEmpty,
           let legacy = defaults.array(forKey: Self.legacyHistoryKey) as? [[String: Any]] {
            for entry in legacy {
                if let id = entry["id"] as? String {
                    journal[id] = entry
                }
            }
        }
    }

    private func persist() {
        saveState(recordCurrent: true)
    }

    private func saveState(recordCurrent: Bool) {
        if loaded && recordCurrent {
            savedPosition = currentPositionMs()
            if hasPlayed {
                record(completed: false, listenedMs: 0)
            }
        }
        defaults.set(jsonString(session) ?? "{}", forKey: Self.sessionKey)
        defaults.set(Int(savedPosition), forKey: Self.positionKey)
        defaults.set(jsonString(journal) ?? "{}", forKey: Self.historyKey)
    }

    @discardableResult
    private func record(completed: Bool, listenedMs: Int64) -> String? {
        guard
            let video = session["video"] as? [String: Any],
            let id = video["id"] as? String,
            !id.isEmpty
        else { return nil }

        var entry = journal[id] ?? video
        let actualDuration = durationMs()
        let fallbackDuration = int64Value(video["durationMs"])
        entry["positionMs"] = Int(currentPositionMs())
        entry["durationMs"] = Int(
            max(0, actualDuration > 0 ? actualDuration : fallbackDuration)
        )
        entry["lastPlayedMs"] = Int(Date().timeIntervalSince1970 * 1000)
        entry["complete"] = completed || boolValue(entry["complete"])
        if listenedMs > 0 {
            entry["listenedMs"] = int64Value(entry["listenedMs"]) + listenedMs
        }
        journal[id] = entry
        if journal.count > 500 {
            let oldest = journal.min {
                int64Value($0.value["lastPlayedMs"]) < int64Value($1.value["lastPlayedMs"])
            }?.key
            if let oldest {
                journal.removeValue(forKey: oldest)
            }
        }
        return id
    }


    // MARK: - Value helpers

    private func time(_ milliseconds: Int64) -> CMTime {
        CMTime(value: milliseconds, timescale: 1000)
    }

    private func currentPositionMs() -> Int64 {
        positionMs(primaryPlayer)
    }

    private func secondaryPositionMs() -> Int64 {
        positionMs(secondaryPlayer)
    }

    private func positionMs(_ player: AVPlayer) -> Int64 {
        let seconds = player.currentTime().seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    private func durationMs() -> Int64 {
        let metadata = metadataDurationMs()
        if metadata > 0 { return metadata }
        guard let duration = itemA?.duration else { return 0 }
        let seconds = duration.seconds
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int64((seconds * 1000).rounded())
    }

    private func metadataDurationMs() -> Int64 {
        guard let video = session["video"] as? [String: Any] else { return 0 }
        return max(0, int64Value(video["durationMs"]))
    }

    private func streamURL(_ value: Any?) throws -> URL {
        guard let raw = value as? String else {
            throw ApplePlaybackFailure(message: "Nieprawidłowy adres strumienia YouTube.")
        }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: text),
            url.scheme?.lowercased() == "https",
            let host = url.host?.lowercased(),
            host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
        else {
            throw ApplePlaybackFailure(message: "Nieprawidłowy adres strumienia YouTube.")
        }
        return url
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        return nil
    }

    private func int64Value(_ value: Any?) -> Int64 {
        if let number = value as? NSNumber { return number.int64Value }
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? Double { return Int64(value) }
        return 0
    }

    private func number(
        _ value: Any?,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        guard let number = doubleValue(value), number.isFinite else { return fallback }
        return AppleMixerMath.clamp(number, minimum, maximum)
    }

    private func floatValue(
        _ key: String,
        fallback: Double,
        minimum: Double,
        maximum: Double
    ) -> Double {
        number(mix[key], fallback: fallback, minimum: minimum, maximum: maximum)
    }

    private func string(_ key: String, fallback: String) -> String {
        mix[key] as? String ?? fallback
    }

    private func boolValue(_ value: Any?) -> Bool {
        if let number = value as? NSNumber { return number.boolValue }
        if let value = value as? Bool { return value }
        return false
    }

    private func boolValue(_ key: String) -> Bool {
        boolValue(mix[key])
    }

    private func offset() -> Int {
        Int(number(mix["offsetMs"], fallback: 0, minimum: -3000, maximum: 3000).rounded())
    }

    private func speed() -> Double {
        number(mix["speed"], fallback: 1, minimum: 1, maximum: 5)
    }

    private func jsonString(_ object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object) else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

struct ApplePlaybackFailure: LocalizedError {
    let message: String

    var errorDescription: String? { message }
}

#if canImport(FlutterMacOS) || canImport(Flutter)
/// Registers the shared `app.yubbly/player` channel on macOS and iOS.
final class ApplePlaybackChannel {
    static let channelName = "app.yubbly/player"

    private let engine: ApplePlaybackEngine
    private let channel: FlutterMethodChannel

    init(messenger: FlutterBinaryMessenger) {
        engine = ApplePlaybackEngine()
        channel = FlutterMethodChannel(
            name: Self.channelName,
            binaryMessenger: messenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result: result)
        }
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "state":
            result(engine.snapshot())
        case "history":
            result(engine.history())
        case "clearHistory":
            engine.clearHistory()
            result(nil)
        case "initialLink":
            result(nil)
        case "load":
            guard let args = call.arguments as? [String: Any] else {
                result(invalidArguments())
                return
            }
            do {
                try engine.load(args)
                result(nil)
            } catch {
                result(
                    FlutterError(
                        code: "PLAYER",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
        case "play":
            engine.play()
            result(nil)
        case "pause":
            engine.pause()
            result(nil)
        case "stop":
            engine.stop()
            result(nil)
        case "seek":
            guard
                let args = call.arguments as? [String: Any],
                let value = args["positionMs"] as? NSNumber
            else {
                result(invalidArguments())
                return
            }
            engine.seek(value.int64Value)
            result(nil)
        case "configure":
            guard let args = call.arguments as? [String: Any] else {
                result(invalidArguments())
                return
            }
            engine.configure(args)
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func invalidArguments() -> FlutterError {
        FlutterError(
            code: "PLAYER",
            message: "Nieprawidłowe dane sterowania odtwarzaczem.",
            details: nil
        )
    }
}
#endif


