import Foundation

enum GestureState: Equatable {
    case idle
    case threeFingerDown(start: ContinuousClock.Instant)
    case rejected
}

enum GestureRejection: Equatable, CustomStringConvertible {
    case tooManyFingers
    case fingerCountChanged
    case heldTooLong
    case cooldown

    var description: String {
        switch self {
        case .tooManyFingers: "more than three fingers"
        case .fingerCountChanged: "finger count changed before release"
        case .heldTooLong: "held too long"
        case .cooldown: "cooldown active"
        }
    }
}

enum GestureOutcome: Equatable {
    case enteredThreeFingerDown
    case accepted(Duration)
    case rejected(GestureRejection, Duration?)

    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
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

    /// Returns a transition only when the recognizer enters, accepts, or rejects
    /// a gesture. This keeps normal capture quiet while enabling concise tracing.
    /// `rawTouchCount` is retained separately so an over-three-finger contact
    /// is rejected even when some contacts are already ending in that frame.
    mutating func process(
        activeTouchCount: Int,
        rawTouchCount: Int,
        now: ContinuousClock.Instant
    ) -> GestureOutcome? {
        switch state {
        case .idle:
            if rawTouchCount > 3 {
                state = .rejected
                return .rejected(.tooManyFingers, nil)
            } else if activeTouchCount == 3 {
                state = .threeFingerDown(start: now)
                return .enteredThreeFingerDown
            }

        case let .threeFingerDown(start):
            if rawTouchCount > 3 {
                state = .rejected
                return .rejected(.tooManyFingers, now - start)
            } else if activeTouchCount == 0 {
                let duration = now - start
                state = .idle
                guard duration <= configuration.maximumPressDuration else {
                    return .rejected(.heldTooLong, duration)
                }
                guard lastRecognition.map({ now - $0 >= configuration.cooldown }) ?? true else {
                    return .rejected(.cooldown, duration)
                }
                lastRecognition = now
                return .accepted(duration)
            } else if activeTouchCount != 3 {
                state = .rejected
                return .rejected(.fingerCountChanged, now - start)
            }

        case .rejected:
            if activeTouchCount == 0 {
                state = .idle
            }
        }
        return nil
    }
}
