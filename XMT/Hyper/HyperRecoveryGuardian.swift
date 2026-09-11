import Darwin
import Foundation

/// Prevents separate app instances from simultaneously repairing or acquiring the same map.
/// The recovery child does not inherit this close-on-exec descriptor.
enum HyperApplicationLease {
    private static var descriptor: Int32 = -1
    static func acquire() -> Bool {
        let directory = HidutilHyperMappingBackend.defaultJournalURL.deletingLastPathComponent()
        do { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
        catch { return false }
        let fd = open(directory.appending(path: "application.lock").path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return false }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { close(fd); return false }
        descriptor = fd
        return true
    }
}

/// A dedicated child waits on a pipe, with no AppKit, event tap, timer, or idle polling.
/// Deliberate disarm sends D; unexpected EOF restores the journal generation it armed for.
actor HyperProcessGuardian: HyperGuardian {
    private var process: Process?
    private var writeHandle: FileHandle?
    private let executable: URL

    init(executable: URL = Bundle.main.executableURL!) { self.executable = executable }

    func arm(_ receipt: HyperMappingReceipt, failure: @escaping @Sendable () -> Void) async throws {
        guard process == nil else { throw HyperBackendError.busy }
        let executable = self.executable
        let pair = try await Task.detached { () throws -> (Process, FileHandle) in
            let child = Process(), ownership = Pipe(), ready = Pipe()
            child.executableURL = executable
            child.arguments = ["--hyper-guardian", receipt.journalURL.path]
            // Explicitly prevent either pipe's opposite end from surviving exec in the child.
            _ = fcntl(ownership.fileHandleForWriting.fileDescriptor, F_SETFD, FD_CLOEXEC)
            _ = fcntl(ownership.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
            _ = fcntl(ready.fileHandleForReading.fileDescriptor, F_SETFD, FD_CLOEXEC)
            child.standardInput = ownership
            child.standardOutput = ready
            child.standardError = FileHandle.nullDevice
            try child.run()
            try ownership.fileHandleForReading.close()
            try ready.fileHandleForWriting.close()
            do {
                guard try HyperGuardianProtocol.readByte(from: ready.fileHandleForReading.fileDescriptor, timeoutMilliseconds: 5_000) == 1,
                      child.isRunning else { throw HyperBackendError.processFailed("Recovery process did not become ready.") }
                try ready.fileHandleForReading.close()
                return (child, ownership.fileHandleForWriting)
            } catch {
                try? ownership.fileHandleForWriting.close()
                if child.isRunning { kill(child.processIdentifier, SIGKILL) }
                try? ready.fileHandleForReading.close()
                throw error
            }
        }.value
        process = pair.0; writeHandle = pair.1
        pair.0.terminationHandler = { _ in failure() }
        guard pair.0.isRunning else {
            pair.0.terminationHandler = nil
            try? pair.1.close()
            process = nil; writeHandle = nil
            failure()
            throw HyperBackendError.processFailed("Recovery process exited.")
        }
    }

    func disarm() async throws {
        guard let process else { return }
        // The controller has already restored the mapping. Mark graceful completion before
        // allowing the child to exit, and wait before admitting another activation.
        process.terminationHandler = nil
        let handle = writeHandle
        writeHandle = nil
        try await Task.detached { try Self.finishChild(process, handle: handle) }.value
        self.process = nil
    }

    private nonisolated static func finishChild(_ process: Process, handle: FileHandle?) throws {
        if process.isRunning { try? handle?.write(contentsOf: Data([HyperGuardianProtocol.disarmByte])) }
        try? handle?.close()
        let done = DispatchSemaphore(value: 0)
        DispatchQueue.global().async { process.waitUntilExit(); done.signal() }
        if done.wait(timeout: .now() + 5) == .timedOut {
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            _ = done.wait(timeout: .now() + 1)
            throw HyperBackendError.timedOut
        }
    }
}

enum HyperGuardianProtocol {
    static let disarmByte: UInt8 = 68
    static func readByte(from fd: Int32, timeoutMilliseconds: Int32 = -1) throws -> UInt8? {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
        var result: Int32
        repeat { result = poll(&descriptor, 1, timeoutMilliseconds) } while result < 0 && errno == EINTR
        guard result > 0 else { throw HyperBackendError.timedOut }
        var byte: UInt8 = 0
        var count: Int
        repeat { count = read(fd, &byte, 1) } while count < 0 && errno == EINTR
        guard count >= 0 else { throw HyperBackendError.processFailed("Recovery pipe failed.") }
        return count == 0 ? nil : byte
    }
}

enum HyperRecoveryGuardian {
    static func runIfRequested(arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.dropFirst().first == "--hyper-guardian" else { return nil }
        guard arguments.count == 3 else { return 64 }
        let url = URL(fileURLWithPath: arguments[2]).standardizedFileURL
        // This private mode only accepts XMT's own journal, never an arbitrary mapping file.
        guard url == HidutilHyperMappingBackend.defaultJournalURL.standardizedFileURL,
              let data = try? Data(contentsOf: url), data.count <= 256_000,
              let receipt = try? JSONDecoder().decode(HyperMappingReceipt.self, from: data),
              receipt.journalURL.standardizedFileURL == url else { return 64 }
        FileHandle.standardOutput.write(Data([1]))
        do {
            if try HyperGuardianProtocol.readByte(from: STDIN_FILENO) == HyperGuardianProtocol.disarmByte { return 0 }
        } catch { /* A broken ownership channel requires recovery too. */ }
        let finished = DispatchSemaphore(value: 0)
        let result = HyperGuardianResult()
        Task.detached {
            do { try await HidutilHyperMappingBackend(journalURL: url).restore(receipt); result.succeeded = true }
            catch { result.succeeded = false }
            finished.signal()
        }
        guard finished.wait(timeout: .now() + 25) == .success else { return 1 }
        return result.succeeded ? 0 : 1
    }
}

private final class HyperGuardianResult: @unchecked Sendable {
    // Written once, read only after semaphore completion.
    var succeeded = false
}
