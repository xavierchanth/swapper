import XCTest

private actor HyperControllerFixture: HyperMappingBackend, HyperGuardian, HyperTapBackend {
    enum Failure: Error { case requested }
    var log: [String] = []
    var failInstall = false
    var failRestore = false
    var stallPrepare = false
    var prepareWaiter: CheckedContinuation<Void, Never>?
    let receipt: HyperMappingReceipt

    init(url: URL) {
        let keyboard = HyperKeyboardSelection(id: "built-in", displayName: "Built-in", matchingJSON: #"{"LocationID":1}"#)
        receipt = .init(id: UUID(), journalURL: url, keyboard: keyboard, originalMappings: [], installedMappings: [HyperMappingFormat.owned])
    }
    func recoverAbandonedJournal() { log.append("recover") }
    func prepare(for keyboard: HyperKeyboardSelection) async -> HyperMappingReceipt {
        log.append("prepare")
        if stallPrepare { await withCheckedContinuation { prepareWaiter = $0 } }
        return receipt
    }
    func install(_ receipt: HyperMappingReceipt) throws { log.append("install"); if failInstall { throw Failure.requested } }
    func restore(_ receipt: HyperMappingReceipt) throws { log.append("restore"); if failRestore { throw Failure.requested } }
    func arm(_ receipt: HyperMappingReceipt, failure: @escaping @Sendable () -> Void) { log.append("arm") }
    func disarm() { log.append("disarm") }
    func start(holdMilliseconds: Int, interruption: @escaping @Sendable () -> Void) { log.append("tap-start") }
    func stop() { log.append("tap-stop") }
    func setFailInstall() { failInstall = true }
    func setFailRestore() { failRestore = true }
    func setStallPrepare() { stallPrepare = true }
    func releasePrepare() { stallPrepare = false; prepareWaiter?.resume(); prepareWaiter = nil }
    func snapshot() -> [String] { log }
}

@MainActor
final class HyperControllerTests: XCTestCase {
    private func keyboard() -> HyperKeyboardSelection { .init(id: "built-in", displayName: "Built-in", matchingJSON: #"{"LocationID":1}"#) }

    func testEnableOrdersRecoveryPrepareTapGuardianInstall() async {
        let fixture = HyperControllerFixture(url: URL(fileURLWithPath: "/tmp/controller-journal"))
        let selected = keyboard()
        let controller = HyperController(mapping: fixture, guardian: fixture, tap: fixture,
            configuration: .init(enabled: true, holdMilliseconds: 200), discover: { selected },
            competitor: { false }, persist: { _ in })
        await controller.start()
        let log = await fixture.snapshot()
        XCTAssertEqual(log, ["tap-stop", "recover", "prepare", "tap-start", "arm", "install"])
        XCTAssertEqual(controller.status, .active(keyboard()))
    }

    func testDisabledStartStillRecovers() async {
        let fixture = HyperControllerFixture(url: URL(fileURLWithPath: "/tmp/controller-disabled"))
        let selected = keyboard()
        let controller = HyperController(mapping: fixture, guardian: fixture, tap: fixture,
            configuration: .init(), discover: { selected }, competitor: { false }, persist: { _ in })
        await controller.start()
        let log = await fixture.snapshot()
        XCTAssertEqual(log, ["tap-stop", "recover"])
        XCTAssertEqual(controller.status, .disabled)
    }

    func testPartialInstallFailureRestoresBeforeDisarming() async {
        let fixture = HyperControllerFixture(url: URL(fileURLWithPath: "/tmp/controller-install-fail")); await fixture.setFailInstall()
        let selected = keyboard()
        let controller = HyperController(mapping: fixture, guardian: fixture, tap: fixture,
            configuration: .init(enabled: true, holdMilliseconds: 200), discover: { selected },
            competitor: { false }, persist: { _ in })
        await controller.start()
        let log = await fixture.snapshot()
        XCTAssertEqual(Array(log.suffix(3)), ["restore", "disarm", "tap-stop"])
        if case .failed = controller.status {} else { XCTFail("expected failure") }
    }

    func testFailedRestoreBlocksStopAndLeavesRecoveryStatus() async {
        let fixture = HyperControllerFixture(url: URL(fileURLWithPath: "/tmp/controller-restore-fail"))
        let selected = keyboard()
        let controller = HyperController(mapping: fixture, guardian: fixture, tap: fixture,
            configuration: .init(enabled: true, holdMilliseconds: 200), discover: { selected },
            competitor: { false }, persist: { _ in })
        await controller.start(); await fixture.setFailRestore()
        let stopped = await controller.stop(); let log = await fixture.snapshot()
        XCTAssertFalse(stopped); XCTAssertEqual(controller.status, .recoveryRequired)
        XCTAssertFalse(log.contains("disarm"))
    }

    func testStopDuringStalledPrepareWaitsThenRestoresWithoutInstalling() async {
        let fixture = HyperControllerFixture(url: URL(fileURLWithPath: "/tmp/controller-stop-race")); await fixture.setStallPrepare()
        let selected = keyboard()
        let controller = HyperController(mapping: fixture, guardian: fixture, tap: fixture,
            configuration: .init(enabled: true, holdMilliseconds: 200), discover: { selected },
            competitor: { false }, persist: { _ in })
        let starting = Task { await controller.start() }
        while !(await fixture.snapshot()).contains("prepare") { await Task.yield() }
        let stopping = Task { await controller.stop() }
        await fixture.releasePrepare(); await starting.value
        let stopped = await stopping.value
        XCTAssertTrue(stopped)
        let log = await fixture.snapshot()
        XCTAssertTrue(log.contains("restore")); XCTAssertFalse(log.contains("install"))
        XCTAssertEqual(controller.status, .disabled)
    }
}
