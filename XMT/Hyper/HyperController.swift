import AppKit
import Combine
import Foundation

struct HyperMappingReceipt: Codable, Equatable, Sendable {
    let id: UUID
    let journalURL: URL
    let keyboard: HyperKeyboardSelection
    let originalMappings: [[String: UInt64]]
    let installedMappings: [[String: UInt64]]
    var matchingJSON: String { keyboard.matchingJSON }
}

protocol HyperMappingBackend: Sendable {
    func recoverAbandonedJournal() async throws
    func prepare(for keyboard: HyperKeyboardSelection) async throws -> HyperMappingReceipt
    func install(_ receipt: HyperMappingReceipt) async throws
    func restore(_ receipt: HyperMappingReceipt) async throws
}

protocol HyperGuardian: Sendable {
    func arm(_ receipt: HyperMappingReceipt, failure: @escaping @Sendable () -> Void) async throws
    func disarm() async throws
}

protocol HyperTapBackend: Sendable {
    func start(holdMilliseconds: Int, interruption: @escaping @Sendable () -> Void) async throws
    func stop() async
}

/// One FIFO orders every operation across suspension points, including Quit.
@MainActor
final class HyperController: ObservableObject {
    static let shared = HyperController(mapping: HidutilHyperMappingBackend(), guardian: HyperProcessGuardian(), tap: HyperEventTap())
    @Published private(set) var status: HyperStatus = .disabled
    @Published private(set) var configuration: HyperConfiguration
    @Published private(set) var isBusy = false
    private let mapping: any HyperMappingBackend
    private let guardian: any HyperGuardian
    private let tap: any HyperTapBackend
    private let discover: @Sendable () async throws -> HyperKeyboardSelection
    private let competitor: @MainActor () -> Bool
    private let persist: (HyperConfiguration) throws -> Void
    private var receipt: HyperMappingReceipt?
    private var guardianArmed = false
    private var terminating = false
    private var operationTail: Task<Bool, Never>?
    private var generation: UUID?

    init(mapping: any HyperMappingBackend, guardian: any HyperGuardian, tap: any HyperTapBackend,
         configuration: HyperConfiguration = HyperSettingsStore.load(),
         discover: @escaping @Sendable () async throws -> HyperKeyboardSelection = { try await HyperBuiltInKeyboardDiscovery.discover() },
         competitor: @escaping @MainActor () -> Bool = {
             NSWorkspace.shared.runningApplications.contains {
                 $0.bundleIdentifier == "com.knollsoft.Hyperkey" || $0.localizedName?.lowercased() == "hyperkey"
             }
         }, persist: @escaping (HyperConfiguration) throws -> Void = { try HyperSettingsStore.save($0) }) {
        self.mapping = mapping; self.guardian = guardian; self.tap = tap
        self.configuration = configuration; self.discover = discover; self.competitor = competitor; self.persist = persist
    }

    func start() async { await apply(configuration) }

    func apply(_ replacement: HyperConfiguration) async {
        guard !terminating else { return }
        _ = await enqueue { await self.applyNow(replacement) }
    }

    private func enqueue(_ work: @escaping @MainActor () async -> Bool) async -> Bool {
        let previous = operationTail
        let operation = Task { @MainActor in
            _ = await previous?.value
            self.isBusy = true
            defer { self.isBusy = false }
            return await work()
        }
        operationTail = operation
        return await operation.value
    }

    private func applyNow(_ replacement: HyperConfiguration) async -> Bool {
        guard !terminating else { return false }
        guard replacement.isValid else { status = .failed("Enter a hold threshold from 1 to 60,000 milliseconds."); return false }
        guard await deactivate() else { return false }
        do {
            // Recover even if the saved preference is disabled, or preparation previously failed.
            try await mapping.recoverAbandonedJournal()
            try persist(replacement)
            configuration = replacement
            guard replacement.enabled else { status = .disabled; return true }
            guard !competitor() else {
                status = .unavailable("Quit Hyperkey before enabling XMT Hyper."); return false
            }
            status = .enabling
            // Always rediscover the built-in service. Never trust persisted matching JSON.
            let keyboard = try await discover()
            guard !terminating else { status = .disabled; return false }
            let prepared = try await mapping.prepare(for: keyboard)
            receipt = prepared
            let currentGeneration = UUID()
            generation = currentGeneration
            try await tap.start(holdMilliseconds: replacement.holdMilliseconds) { [weak self] in
                Task { @MainActor in await self?.interrupted(currentGeneration) }
            }
            try await guardian.arm(prepared) { [weak self] in
                Task { @MainActor in await self?.interrupted(currentGeneration) }
            }
            guardianArmed = true
            guard !terminating else { return await deactivate() }
            try await mapping.install(prepared)
            guard !terminating else { return await deactivate() }
            status = .active(keyboard)
            return true
        } catch {
            let restored = await deactivate()
            guard restored else { return false }
            if case HyperEventTapError.accessibilityRequired = error { status = .permissionRequired }
            else { status = .failed(error.localizedDescription) }
            return false
        }
    }

    private func interrupted(_ expectedGeneration: UUID) async {
        guard !terminating else { return }
        _ = await enqueue {
            guard self.generation == expectedGeneration else { return true }
            let restored = await self.deactivate()
            if restored { self.status = .suspended }
            return restored
        }
    }

    func applicationDidBecomeActive() async {
        guard !terminating, configuration.enabled else { return }
        switch status {
        case .permissionRequired, .suspended: await apply(configuration)
        default: break
        }
    }

    @discardableResult func stop() async -> Bool {
        terminating = true
        let result = await enqueue {
            guard await self.deactivate() else { return false }
            do { try await self.mapping.recoverAbandonedJournal(); self.status = .disabled; return true }
            catch { self.status = .recoveryRequired; return false }
        }
        if !result { terminating = false }
        return result
    }

    private func deactivate() async -> Bool {
        generation = nil
        if let receipt {
            do { try await mapping.restore(receipt); self.receipt = nil }
            catch { status = .recoveryRequired; return false }
        }
        if guardianArmed {
            do { try await guardian.disarm(); guardianArmed = false }
            catch { status = .recoveryRequired; return false }
        }
        await tap.stop()
        return true
    }
}

enum HyperSettingsStore {
    private static let key = "hyper.settings.v1"
    static func load(defaults: UserDefaults = .standard) -> HyperConfiguration {
        guard let data = defaults.data(forKey: key), let value = try? JSONDecoder().decode(HyperConfiguration.self, from: data), value.isValid else { return .init() }
        return value
    }
    static func save(_ value: HyperConfiguration, defaults: UserDefaults = .standard) throws {
        defaults.set(try JSONEncoder().encode(value), forKey: key)
    }
}
