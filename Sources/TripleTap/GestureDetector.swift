import Foundation

enum GestureState: Equatable {
    case idle
    case threeFingerDown(start: ContinuousClock.Instant, origins: [Int32: TouchPoint])
    case releasing(start: ContinuousClock.Instant, origins: [Int32: TouchPoint])
    case rejected
}

enum GestureRejection: Equatable, CustomStringConvertible {
    case tooManyFingers
    case fingerCountChanged
    case heldTooLong
    case cooldown
    case movedTooFar

    var description: String {
        switch self {
        case .tooManyFingers: "more than three fingers"
        case .fingerCountChanged: "finger count changed before release"
        case .heldTooLong: "held too long"
        case .cooldown: "cooldown active"
        case .movedTooFar: "fingers moved too far"
        }
    }
}

struct TouchPoint: Equatable {
    let x: Float
    let y: Float
}

struct TouchSample: Equatable {
    let identifier: Int32
    let position: TouchPoint
}

enum GestureOutcome: Equatable {
    case enteredThreeFingerDown
    case enteredRelease
    case accepted(Duration)
    case rejected(GestureRejection, Duration?)

    var isAccepted: Bool {
        if case .accepted = self { return true }
        return false
    }
}

struct ThreeFingerClickDetector {
    struct Configuration {
        var maximumPressDuration: Duration = .milliseconds(260)
        var cooldown: Duration = .milliseconds(250)
        /// Coordinates are normalized to the trackpad dimensions. A 2.5% move
        /// is generous for a press but small enough to reject swipes.
        var maximumMovement: Float = 0.025
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
        touches: [TouchSample] = [],
        now: ContinuousClock.Instant
    ) -> GestureOutcome? {
        switch state {
        case .idle:
            if rawTouchCount > 3 {
                state = .rejected
                return .rejected(.tooManyFingers, nil)
            } else if activeTouchCount == 3 {
                state = .threeFingerDown(start: now, origins: Dictionary(uniqueKeysWithValues: touches.map { ($0.identifier, $0.position) }))
                return .enteredThreeFingerDown
            }

        case let .threeFingerDown(start, origins):
            if rawTouchCount > 3 {
                state = .rejected
                return .rejected(.tooManyFingers, now - start)
            } else if hasExceededMovement(touches, from: origins) {
                state = .rejected
                return .rejected(.movedTooFar, now - start)
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
            } else if activeTouchCount < 3 {
                // Hardware reports individual fingers lifting on successive
                // frames, so a valid click commonly transitions 3 → 2 → 1 → 0.
                state = .releasing(start: start, origins: origins)
                return .enteredRelease
            }

        case let .releasing(start, origins):
            if rawTouchCount > 3 {
                state = .rejected
                return .rejected(.tooManyFingers, now - start)
            } else if hasExceededMovement(touches, from: origins) {
                state = .rejected
                return .rejected(.movedTooFar, now - start)
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
            } else if activeTouchCount == 3 {
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

    private func hasExceededMovement(_ touches: [TouchSample], from origins: [Int32: TouchPoint]) -> Bool {
        let maximumDistanceSquared = configuration.maximumMovement * configuration.maximumMovement
        return touches.contains { touch in
            guard let origin = origins[touch.identifier] else { return false }
            let deltaX = touch.position.x - origin.x
            let deltaY = touch.position.y - origin.y
            return deltaX * deltaX + deltaY * deltaY > maximumDistanceSquared
        }
    }
}
