import Foundation

enum GestureState: Equatable {
    case idle
    case threeFingerDown(start: ContinuousClock.Instant)
    case rejected
}

struct ThreeFingerClickDetector {
    struct Configuration {
        var maximumPressDuration: Duration = .milliseconds(180)
        var cooldown: Duration = .milliseconds(250)
    }

    private(set) var state: GestureState = .idle
    private var lastRecognition: ContinuousClock.Instant?
    let configuration: Configuration

    init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    /// Returns true exactly once when a clean three-finger click completes.
    /// `rawTouchCount` is retained separately so an over-three-finger contact
    /// is rejected even when some contacts are already ending in that frame.
    mutating func process(
        activeTouchCount: Int,
        rawTouchCount: Int,
        now: ContinuousClock.Instant
    ) -> Bool {
        switch state {
        case .idle:
            if rawTouchCount > 3 {
                state = .rejected
            } else if activeTouchCount == 3 {
                state = .threeFingerDown(start: now)
            }

        case let .threeFingerDown(start):
            if rawTouchCount > 3 || activeTouchCount != 3 {
                if activeTouchCount == 0 {
                    state = .idle
                    guard now - start <= configuration.maximumPressDuration else { return false }
                    guard lastRecognition.map({ now - $0 >= configuration.cooldown }) ?? true else { return false }
                    lastRecognition = now
                    return true
                }
                state = .rejected
            }

        case .rejected:
            if activeTouchCount == 0 {
                state = .idle
            }
        }
        return false
    }
}
