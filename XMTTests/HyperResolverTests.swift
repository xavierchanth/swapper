import XCTest

final class HyperResolverTests: XCTestCase {
    func testTapEmitsEscapeOnlyOnReleaseBeforeThreshold() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        XCTAssertEqual(resolver.receive(.mappedKeyDown(isRepeat: false), at: 10).deadlineMilliseconds, 210)
        let result = resolver.receive(.mappedKeyUp, at: 209)
        XCTAssertTrue(result.consumeMappedEvent); XCTAssertTrue(result.emitEscapeTap)
    }

    func testOtherKeyFormsHyperOnThatEvent() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 0)
        XCTAssertTrue(resolver.receive(.otherKeyDown(isRepeat: false), at: 5).addHyperFlags)
        XCTAssertTrue(resolver.receive(.otherKeyDown(isRepeat: false), at: 6).addHyperFlags)
        XCTAssertTrue(resolver.receive(.mappedKeyUp, at: 7).consumeMappedEvent)
        XCTAssertFalse(resolver.receive(.otherKeyDown(isRepeat: false), at: 8).addHyperFlags)
    }

    func testDeadlineFormsHoldAndInterruptionNeverTaps() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 0)
        _ = resolver.receive(.deadline, at: 200)
        XCTAssertTrue(resolver.receive(.otherKeyDown(isRepeat: false), at: 201).addHyperFlags)
        _ = resolver.receive(.interrupted, at: 202)
        let release = resolver.receive(.mappedKeyUp, at: 203)
        XCTAssertTrue(release.consumeMappedEvent); XCTAssertFalse(release.emitEscapeTap)
    }

    func testInterruptedPendingConsumesLateReleaseWithoutTap() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 0)
        _ = resolver.receive(.interrupted, at: 50)
        let release = resolver.receive(.mappedKeyUp, at: 60)
        XCTAssertTrue(release.consumeMappedEvent); XCTAssertFalse(release.emitEscapeTap)
    }

    func testDuplicateAndRepeatMarkerDownsAreAlwaysConsumed() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 10)
        let duplicate = resolver.receive(.mappedKeyDown(isRepeat: false), at: 11)
        let repeated = resolver.receive(.mappedKeyDown(isRepeat: true), at: 12)
        XCTAssertTrue(duplicate.consumeMappedEvent); XCTAssertTrue(repeated.consumeMappedEvent)
        XCTAssertEqual(duplicate.deadlineMilliseconds, 210); XCTAssertEqual(repeated.deadlineMilliseconds, 210)
    }

    func testStrayMarkerReleaseIsConsumedWithoutEscape() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        let result = resolver.receive(.mappedKeyUp, at: 1)
        XCTAssertTrue(result.consumeMappedEvent); XCTAssertFalse(result.emitEscapeTap)
    }

    func testRepeatOfOtherKeyDoesNotResolvePendingGesture() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 0)
        let repeatValue = resolver.receive(.otherKeyDown(isRepeat: true), at: 10)
        XCTAssertFalse(repeatValue.addHyperFlags); XCTAssertEqual(repeatValue.deadlineMilliseconds, 200)
        XCTAssertTrue(resolver.receive(.mappedKeyUp, at: 20).emitEscapeTap)
    }

    func testDeadlineSaturatesAtIntegerMaximum() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        XCTAssertEqual(resolver.receive(.mappedKeyDown(isRepeat: false), at: Int.max - 10).deadlineMilliseconds, Int.max)
    }

    func testInterruptedMarkerDownsRemainConsumedUntilRelease() {
        var resolver = HyperResolver(holdMilliseconds: 200)!
        _ = resolver.receive(.mappedKeyDown(isRepeat: false), at: 0)
        _ = resolver.receive(.interrupted, at: 1)
        XCTAssertTrue(resolver.receive(.mappedKeyDown(isRepeat: false), at: 2).consumeMappedEvent)
        XCTAssertTrue(resolver.receive(.mappedKeyDown(isRepeat: true), at: 3).consumeMappedEvent)
        let release = resolver.receive(.mappedKeyUp, at: 4)
        XCTAssertTrue(release.consumeMappedEvent); XCTAssertFalse(release.emitEscapeTap)
    }
}
