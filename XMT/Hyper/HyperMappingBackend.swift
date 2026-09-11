import Darwin
import Foundation

enum HyperBackendError: LocalizedError {
    case processFailed(String), malformedOutput, ambiguousKeyboard, readbackMismatch, mappingChangedExternally, timedOut, busy, markerInUse
    var errorDescription: String? {
        switch self {
        case .processFailed(let detail): "Keyboard service failed: \(detail)"
        case .malformedOutput: "Could not read the keyboard's mapping safely. No new mapping was applied."
        case .ambiguousKeyboard: "A unique built-in keyboard service could not be identified."
        case .readbackMismatch: "The keyboard did not confirm the mapping."
        case .mappingChangedExternally: "Another program changed the keyboard mapping. Retry after closing it."
        case .timedOut: "The keyboard operation timed out. Retry recovery before enabling Hyper."
        case .busy: "Another XMT process is using or recovering the keyboard."
        case .markerInUse: "F18 is already used by a keyboard mapping. Hyper cannot reserve it."
        }
    }
}

/// Parses hidutil's OpenStep output, rejecting missing or multiple service results.
enum HyperMappingFormat {
    static let source = "HIDKeyboardModifierMappingSrc"
    static let destination = "HIDKeyboardModifierMappingDst"
    static let caps: UInt64 = 0x700000039
    static let marker: UInt64 = 0x70000006D
    static let owned = [source: caps, destination: marker]

    static func parse(_ data: Data) throws -> [[String: UInt64]] {
        guard let text = String(data: data, encoding: .utf8),
              text.components(separatedBy: "UserKeyMapping").count == 2,
              let label = text.range(of: "UserKeyMapping") else { throw HyperBackendError.malformedOutput }
        let payload = String(text[label.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        if payload == "(null)" { return [] }
        let value = try PropertyListSerialization.propertyList(from: Data(payload.utf8), options: [], format: nil)
        guard let rows = value as? [[String: Any]], rows.count <= 512 else { throw HyperBackendError.malformedOutput }
        let parsed = try rows.map { row -> [String: UInt64] in
            guard Set(row.keys) == Set([source, destination]) else { throw HyperBackendError.malformedOutput }
            func number(_ key: String) throws -> UInt64 {
                // OpenStep property lists normally decode integer tokens as strings.
                if let text = row[key] as? String, let value = UInt64(text) { return value }
                if let value = row[key] as? NSNumber, let parsed = UInt64(value.stringValue) { return parsed }
                throw HyperBackendError.malformedOutput
            }
            return try [source: number(source), destination: number(destination)]
        }
        guard Set(parsed.compactMap { $0[source] }).count == parsed.count else { throw HyperBackendError.malformedOutput }
        return parsed
    }

    static func installing(over original: [[String: UInt64]]) throws -> [[String: UInt64]] {
        guard !original.contains(where: { $0[source] == marker || $0[destination] == marker }) else { throw HyperBackendError.markerInUse }
        return original.filter { $0[source] != caps } + [owned]
    }

    static func restoring(current: [[String: UInt64]], original: [[String: UInt64]]) -> [[String: UInt64]] {
        // A prepare-only journal, a reboot, or another writer may have removed our entry.
        // In all those cases there is nothing we own to reverse.
        guard current.first(where: { $0[source] == caps }) == owned else { return current }
        return current.filter { $0[source] != caps } + original.filter { $0[source] == caps }
    }

    static func equivalent(_ lhs: [[String: UInt64]], _ rhs: [[String: UInt64]]) -> Bool {
        lhs.sorted { ($0[source] ?? 0) < ($1[source] ?? 0) } == rhs.sorted { ($0[source] ?? 0) < ($1[source] ?? 0) }
    }
}

/// The app and recovery child serialize journal/mapping transitions with the same file lock.
struct HidutilHyperMappingBackend: HyperMappingBackend {
    static var defaultJournalURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "XMT/hyper-mapping-journal.json")
    }
    let journalURL: URL
    let command: @Sendable ([String]) throws -> Data

    init(journalURL: URL = Self.defaultJournalURL,
         command: @escaping @Sendable ([String]) throws -> Data = { try HyperProcess.runSync("/usr/bin/hidutil", $0) }) {
        self.journalURL = journalURL; self.command = command
    }

    func recoverAbandonedJournal() async throws {
        try await Task.detached {
            try locked {
                guard let receipt = try loadJournal() else { return }
                // A live guardian owns recovery until its parent disarms or dies. Never let
                // a second app instance reset the first one's mapping.
                try restoreLocked(receipt)
            }
        }.value
    }

    func prepare(for keyboard: HyperKeyboardSelection) async throws -> HyperMappingReceipt {
        try await Task.detached {
            try locked {
                guard try loadJournal() == nil, keyboard.isValid else { throw HyperBackendError.busy }
                let original = try read(keyboard.matchingJSON)
                let installed = try HyperMappingFormat.installing(over: original)
                let receipt = HyperMappingReceipt(id: UUID(), journalURL: journalURL, keyboard: keyboard,
                    originalMappings: original, installedMappings: installed)
                try JSONEncoder().encode(receipt).write(to: journalURL, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: journalURL.path)
                return receipt
            }
        }.value
    }

    func install(_ receipt: HyperMappingReceipt) async throws {
        try await Task.detached {
            try locked {
                guard try loadJournal()?.id == receipt.id else { throw HyperBackendError.busy }
                let current = try read(receipt.matchingJSON)
                guard HyperMappingFormat.equivalent(current, receipt.originalMappings) else { throw HyperBackendError.mappingChangedExternally }
                try set(receipt.installedMappings, receipt.matchingJSON)
                guard HyperMappingFormat.equivalent(try read(receipt.matchingJSON), receipt.installedMappings) else { throw HyperBackendError.readbackMismatch }
            }
        }.value
    }

    func restore(_ receipt: HyperMappingReceipt) async throws {
        try await Task.detached { try locked { try restoreLocked(receipt) } }.value
    }

    private func restoreLocked(_ receipt: HyperMappingReceipt) throws {
        guard let saved = try loadJournal(), saved.id == receipt.id else { return }
        let current = try read(saved.matchingJSON)
        let restored = HyperMappingFormat.restoring(current: current, original: saved.originalMappings)
        if !HyperMappingFormat.equivalent(current, restored) {
            // Detect edits since the first read. hidutil has no cross-application CAS;
            // competing remappers must be stopped during activation and recovery.
            guard HyperMappingFormat.equivalent(try read(saved.matchingJSON), current) else { throw HyperBackendError.mappingChangedExternally }
            try set(restored, saved.matchingJSON)
            guard HyperMappingFormat.equivalent(try read(saved.matchingJSON), restored) else { throw HyperBackendError.readbackMismatch }
        }
        try FileManager.default.removeItem(at: journalURL)
    }

    private func loadJournal() throws -> HyperMappingReceipt? {
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return nil }
        let data = try Data(contentsOf: journalURL)
        guard data.count <= 256_000 else { throw HyperBackendError.malformedOutput }
        let value = try JSONDecoder().decode(HyperMappingReceipt.self, from: data)
        guard value.journalURL.standardizedFileURL == journalURL.standardizedFileURL,
              value.keyboard.isValid,
              value.installedMappings == (try HyperMappingFormat.installing(over: value.originalMappings)) else { throw HyperBackendError.malformedOutput }
        return value
    }

    private func read(_ matching: String) throws -> [[String: UInt64]] {
        try HyperMappingFormat.parse(command(["property", "--matching", matching, "--get", "UserKeyMapping"]))
    }
    private func set(_ value: [[String: UInt64]], _ matching: String) throws {
        let json = try JSONSerialization.data(withJSONObject: ["UserKeyMapping": value], options: .sortedKeys)
        _ = try command(["property", "--matching", matching, "--set", String(decoding: json, as: UTF8.self)])
    }

    private func locked<T>(_ work: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: journalURL.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let descriptor = open(journalURL.appendingPathExtension("lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { throw HyperBackendError.busy }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw HyperBackendError.busy }
        defer { flock(descriptor, LOCK_UN) }
        return try work()
    }
}

enum HyperBuiltInKeyboardDiscovery {
    static func discover() async throws -> HyperKeyboardSelection {
        try parse(await HyperProcess.run("/usr/bin/hidutil", ["list", "--ndjson", "--matching", "keyboard"]))
    }
    static func parse(_ data: Data) throws -> HyperKeyboardSelection {
        let services = try data.split(separator: 10).compactMap { line -> [String: Any]? in
            guard let item = try JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  item["type"] as? String == "service", (item["Built-In"] as? Bool) == true,
                  item["PrimaryUsagePage"] as? Int == 1, item["PrimaryUsage"] as? Int == 6 else { return nil }
            return item
        }
        guard services.count == 1, let item = services.first,
              let product = item["Product"] as? String, let location = item["LocationID"] as? NSNumber,
              let registry = item["IORegistryEntryID"] as? NSNumber else { throw HyperBackendError.ambiguousKeyboard }
        let match: [String: Any] = ["Product": product, "LocationID": location, "PrimaryUsagePage": 1, "PrimaryUsage": 6]
        let json = try JSONSerialization.data(withJSONObject: match, options: .sortedKeys)
        return .init(id: "builtin-\(registry)", displayName: product, matchingJSON: String(decoding: json, as: UTF8.self))
    }
}

enum HyperProcess {
    static func run(_ executable: String, _ arguments: [String]) async throws -> Data {
        try await Task.detached { try runSync(executable, arguments) }.value
    }

    static func runSync(_ executable: String, _ arguments: [String], timeout: TimeInterval = 5) throws -> Data {
        let process = Process(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
        process.standardOutput = output; process.standardError = errors
        try process.run()
        let readers = DispatchGroup(), stdout = HyperCapturedOutput(), stderr = HyperCapturedOutput()
        for (handle, result) in [(output.fileHandleForReading, stdout), (errors.fileHandleForReading, stderr)] {
            readers.enter()
            DispatchQueue.global().async { result.read(handle); readers.leave() }
        }
        let ended = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { process.waitUntilExit(); ended.signal() }
        if ended.wait(timeout: .now() + timeout) == .timedOut {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = ended.wait(timeout: .now() + 1)
            throw HyperBackendError.timedOut
        }
        guard readers.wait(timeout: .now() + 1) == .success else { throw HyperBackendError.timedOut }
        guard process.terminationStatus == 0 else { throw HyperBackendError.processFailed(String(decoding: stderr.data, as: UTF8.self)) }
        guard !stdout.overflow else { throw HyperBackendError.malformedOutput }
        return stdout.data
    }
}

private final class HyperCapturedOutput: @unchecked Sendable {
    private(set) var data = Data()
    private(set) var overflow = false
    // Exactly one writer; read only after its DispatchGroup completion.
    func read(_ handle: FileHandle) {
        while let part = try? handle.read(upToCount: 8192), !part.isEmpty {
            if data.count + part.count <= 1_048_576 { data.append(part) } else { overflow = true }
        }
        try? handle.close()
    }
}
