import Testing
@testable import TripleTap

func wasAccepted(_ outcome: GestureOutcome?) -> Bool {
    outcome?.isAccepted ?? false
}

@Test func recognizesShortThreeFingerClick() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    let began = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let held = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(80)))
    let recognized = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(120)))
    let repeated = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(121)))
    #expect(began == .enteredThreeFingerDown)
    #expect(held == nil)
    #expect(wasAccepted(recognized))
    #expect(!wasAccepted(repeated))
}

@Test func rejectsLongPressAndTooManyFingers() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    _ = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let longPress = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(181)))
    let overflow = detector.process(activeTouchCount: 4, rawTouchCount: 4, now: start.advanced(by: .milliseconds(300)))
    let reduced = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(310)))
    let released = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(350)))
    #expect(longPress == .rejected(.heldTooLong, .milliseconds(181)))
    #expect(overflow == .rejected(.tooManyFingers, nil))
    #expect(reduced == nil)
    #expect(released == nil)
}

@Test func respectsCooldown() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    _ = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let firstUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(100)))
    _ = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(200)))
    let secondUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(220)))
    _ = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(400)))
    let thirdUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(450)))
    #expect(wasAccepted(firstUp))
    #expect(secondUp == .rejected(.cooldown, .milliseconds(20)))
    #expect(wasAccepted(thirdUp))
}
