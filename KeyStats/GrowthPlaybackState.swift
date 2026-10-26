import Foundation

struct GrowthPlaybackState {
    let lastOffset: Int
    private(set) var offset: Int
    private(set) var isPlaying = false

    init(dayCount: Int, selectedOffset: Int? = nil) {
        precondition(dayCount > 0)
        lastOffset = dayCount - 1
        offset = min(lastOffset, max(0, selectedOffset ?? lastOffset))
    }
    mutating func select(_ offset: Int) {
        self.offset = min(lastOffset, max(0, offset))
        isPlaying = false
    }
    mutating func start() { offset = 0; isPlaying = lastOffset > 0 }
    mutating func pause() { isPlaying = false }
    mutating func advance() {
        guard isPlaying else { return }
        offset = min(lastOffset, offset + 1)
        if offset == lastOffset { isPlaying = false }
    }
}

/// Bounded, cancellable one-shot playback. Scheduling is injectable for tests;
/// the same driver is used by the production page. No repeating timer.
final class GrowthPlaybackDriver {
    typealias Schedule = (TimeInterval, @escaping () -> Void) -> (() -> Void)
    private let schedule: Schedule
    private var cancelPending: (() -> Void)?
    private var generation = 0
    private var awaitingPresentation = false
    var waitsForPresentation = false
    var stepInterval: TimeInterval = 0.15
    var presentationGeneration: Int { generation }
    var isPresentingPlaybackFrame: Bool { waitsForPresentation && (state.isPlaying || awaitingPresentation) }
    private(set) var state = GrowthPlaybackState(dayCount: 1)
    private(set) var isActive = false
    var onChange: ((Int) -> Void)?
    var hasScheduledStep: Bool { cancelPending != nil }

    init(schedule: @escaping Schedule = GrowthPlaybackDriver.scheduleOnMain) {
        self.schedule = schedule
    }
    deinit { cancelPending?() }

    func reset(dayCount: Int, selectedOffset: Int? = nil) {
        pause()
        state = GrowthPlaybackState(dayCount: dayCount, selectedOffset: selectedOffset)
        onChange?(state.offset)
    }

    func setActive(_ active: Bool) {
        isActive = active
        if !active { pause() }
    }

    func select(_ offset: Int) {
        pause()
        state.select(offset)
        onChange?(state.offset)
    }

    func start() {
        guard isActive else { return }
        pause()
        state.start()
        awaitingPresentation = waitsForPresentation && state.isPlaying
        onChange?(state.offset)
        enqueue()
    }

    func pause() {
        generation &+= 1
        cancelPending?()
        cancelPending = nil
        state.pause()
        awaitingPresentation = false
    }

    /// 3D advances only after the requested image is ready. Cold shaders and slower
    /// machines cannot make the calendar outrun the displayed keyboard.
    func framePresented(at offset: Int, generation token: Int) {
        guard generation == token, state.offset == offset, isActive, awaitingPresentation else { return }
        awaitingPresentation = false
        enqueue()
    }

    private func enqueue() {
        guard isActive && state.isPlaying && !awaitingPresentation && cancelPending == nil else { return }
        let token = generation
        cancelPending = schedule(stepInterval) { [weak self] in
            guard let self, self.generation == token, self.isActive, self.state.isPlaying else { return }
            self.cancelPending = nil
            self.state.advance()
            self.awaitingPresentation = self.waitsForPresentation
            self.onChange?(self.state.offset)
            self.enqueue()
        }
    }

    private static func scheduleOnMain(after delay: TimeInterval, action: @escaping () -> Void) -> (() -> Void) {
        let work = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        return { work.cancel() }
    }
}
