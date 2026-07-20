import Testing
@testable import TripleTap

@Test func recognizesShortThreeFingerClick() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    let began = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let held = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(80)))
    let recognized = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(120)))
    let repeated = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(121)))
    #expect(!began)
    #expect(!held)
    #expect(recognized)
    #expect(!repeated)
}

@Test func rejectsLongPressAndTooManyFingers() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    let began = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let longPress = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(181)))
    let overflow = detector.process(activeTouchCount: 4, rawTouchCount: 4, now: start.advanced(by: .milliseconds(300)))
    let reduced = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(310)))
    let released = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(350)))
    #expect(!began)
    #expect(!longPress)
    #expect(!overflow)
    #expect(!reduced)
    #expect(!released)
}

@Test func respectsCooldown() {
    let clock = ContinuousClock()
    let start = clock.now
    var detector = ThreeFingerClickDetector()

    let firstDown = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start)
    let firstUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(100)))
    let secondDown = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(200)))
    let secondUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(220)))
    let thirdDown = detector.process(activeTouchCount: 3, rawTouchCount: 3, now: start.advanced(by: .milliseconds(400)))
    let thirdUp = detector.process(activeTouchCount: 0, rawTouchCount: 0, now: start.advanced(by: .milliseconds(450)))
    #expect(!firstDown)
    #expect(firstUp)
    #expect(!secondDown)
    #expect(!secondUp)
    #expect(!thirdDown)
    #expect(thirdUp)
}
