import XCTest

private final class FakeHidutilCommand: @unchecked Sendable {
    private let lock = NSLock()
    var mappings: [[String: UInt64]] = []
    var beforeSet: (() -> Void)?
    func call(_ arguments: [String]) throws -> Data { try lock.withLock {
        if arguments.contains("--get") { return output(mappings) }
        guard let index = arguments.firstIndex(of: "--set"), arguments.indices.contains(index + 1),
              let object = try JSONSerialization.jsonObject(with: Data(arguments[index + 1].utf8)) as? [String: Any],
              let rows = object["UserKeyMapping"] as? [[String: NSNumber]] else { throw HyperBackendError.malformedOutput }
        beforeSet?(); mappings = rows.map { $0.mapValues(\.uint64Value) }; return Data()
    } }
    private func output(_ rows: [[String: UInt64]]) -> Data {
        if rows.isEmpty { return Data("RegistryID Key Value\n1 UserKeyMapping (null)\n".utf8) }
        let body = rows.map { "{ HIDKeyboardModifierMappingDst = \($0[HyperMappingFormat.destination]!); HIDKeyboardModifierMappingSrc = \($0[HyperMappingFormat.source]!); }" }.joined(separator: ",\n")
        return Data("RegistryID Key Value\n1 UserKeyMapping (\n\(body)\n)\n".utf8)
    }
}

final class HyperMappingBackendTests: XCTestCase {
    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "xmt-hyper-\(UUID().uuidString)/journal.json") }
    private func keyboard() -> HyperKeyboardSelection { .init(id: "built-in", displayName: "Built-in", matchingJSON: #"{"LocationID":1}"#) }

    func testPrepareInstallRestorePreservesConcurrentUnrelatedMapping() async throws {
        let command = FakeHidutilCommand(), url = temporaryURL()
        let backend = HidutilHyperMappingBackend(journalURL: url, command: command.call)
        let receipt = try await backend.prepare(for: keyboard()); try await backend.install(receipt)
        let unrelated = [HyperMappingFormat.source: UInt64(10), HyperMappingFormat.destination: UInt64(11)]
        command.mappings.append(unrelated)
        try await backend.restore(receipt)
        XCTAssertEqual(command.mappings, [unrelated]); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testPrepareOnlyRecoveryIsIdempotent() async throws {
        let command = FakeHidutilCommand(), url = temporaryURL()
        let backend = HidutilHyperMappingBackend(journalURL: url, command: command.call)
        _ = try await backend.prepare(for: keyboard())
        try await backend.recoverAbandonedJournal(); try await backend.recoverAbandonedJournal()
        XCTAssertEqual(command.mappings, [])
    }

    func testInstallRejectsSnapshotChangedAfterPrepare() async throws {
        let command = FakeHidutilCommand(), backend = HidutilHyperMappingBackend(journalURL: temporaryURL(), command: command.call)
        let receipt = try await backend.prepare(for: keyboard())
        command.mappings = [[HyperMappingFormat.source: 20, HyperMappingFormat.destination: 21]]
        do { try await backend.install(receipt); XCTFail("expected conflict") }
        catch HyperBackendError.mappingChangedExternally {} catch { XCTFail("unexpected \(error)") }
        XCTAssertEqual(command.mappings.count, 1)
    }

    func testExternalCapsChangeIsNeverClobberedOnRestore() async throws {
        let command = FakeHidutilCommand(), backend = HidutilHyperMappingBackend(journalURL: temporaryURL(), command: command.call)
        let receipt = try await backend.prepare(for: keyboard()); try await backend.install(receipt)
        let external = [HyperMappingFormat.source: HyperMappingFormat.caps, HyperMappingFormat.destination: UInt64(99)]
        command.mappings = [external]; try await backend.restore(receipt)
        XCTAssertEqual(command.mappings, [external])
    }

    func testOldReceiptCannotRestoreNewGeneration() async throws {
        let command = FakeHidutilCommand(), backend = HidutilHyperMappingBackend(journalURL: temporaryURL(), command: command.call)
        let old = try await backend.prepare(for: keyboard()); try await backend.install(old); try await backend.restore(old)
        let current = try await backend.prepare(for: keyboard()); try await backend.install(current)
        try await backend.restore(old)
        XCTAssertEqual(command.mappings, [HyperMappingFormat.owned])
        try await backend.restore(current)
    }
}
