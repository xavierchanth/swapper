import Foundation

struct HyperConfiguration: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var holdMilliseconds: Int = 200
    var keyboard: HyperKeyboardSelection?

    var isValid: Bool { (1...60_000).contains(holdMilliseconds) && (keyboard?.isValid ?? true) }
}

struct HyperKeyboardSelection: Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    /// A complete hidutil `--matching` JSON object chosen by the device-selection UI.
    let matchingJSON: String

    var isValid: Bool {
        guard !id.isEmpty, id == id.trimmingCharacters(in: .whitespacesAndNewlines),
              !displayName.isEmpty, let data = matchingJSON.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data),
              value is [String: Any] else { return false }
        return true
    }
}

enum HyperStatus: Equatable, Sendable {
    case disabled
    case enabling
    case active(HyperKeyboardSelection)
    case permissionRequired
    case recoveryRequired
    case suspended
    case unavailable(String)
    case failed(String)
}

enum HyperResolverInput: Equatable, Sendable {
    case mappedKeyDown(isRepeat: Bool)
    case mappedKeyUp
    case otherKeyDown(isRepeat: Bool)
    case deadline
    case interrupted
}

struct HyperResolverResult: Equatable, Sendable {
    var consumeMappedEvent = false
    var addHyperFlags = false
    var emitEscapeTap = false
    var deadlineMilliseconds: Int?
}

/// Pure tap/hold state for the ordinary spare key produced by hidutil.
struct HyperResolver: Sendable {
    private enum State: Sendable { case idle, pending(downAt: Int), held, interruptedUntilUp }
    private var state: State = .idle
    var isHoldingHyper: Bool { if case .held = state { true } else { false } }
    var isGestureActive: Bool {
        switch state { case .pending, .held, .interruptedUntilUp: true; case .idle: false }
    }
    let holdMilliseconds: Int

    init?(holdMilliseconds: Int) {
        guard (1...60_000).contains(holdMilliseconds) else { return nil }
        self.holdMilliseconds = holdMilliseconds
    }

    mutating func receive(_ input: HyperResolverInput, at milliseconds: Int) -> HyperResolverResult {
        var result = HyperResolverResult()
        switch (state, input) {
        case (.idle, .mappedKeyDown(let repeatValue)):
            result.consumeMappedEvent = true
            guard !repeatValue else { break }
            state = .pending(downAt: milliseconds)
            result.deadlineMilliseconds = saturatingAdd(milliseconds, holdMilliseconds)
        case (.idle, .mappedKeyUp):
            result.consumeMappedEvent = true
        case (.pending(let downAt), .mappedKeyUp):
            result.consumeMappedEvent = true
            if saturatingElapsed(milliseconds, since: downAt) >= holdMilliseconds { state = .idle }
            else { state = .idle; result.emitEscapeTap = true }
        case (.pending(let downAt), .mappedKeyDown):
            result.consumeMappedEvent = true
            result.deadlineMilliseconds = saturatingAdd(downAt, holdMilliseconds)
        case (.pending, .otherKeyDown(let repeatValue)) where !repeatValue:
            state = .held
            result.addHyperFlags = true
        case (.pending, .deadline):
            state = .held
        case (.pending, .interrupted), (.held, .interrupted):
            state = .interruptedUntilUp
        case (.held, .mappedKeyUp), (.interruptedUntilUp, .mappedKeyUp):
            result.consumeMappedEvent = true
            state = .idle
        case (.held, _):
            result.addHyperFlags = true
            if case .mappedKeyDown = input { result.consumeMappedEvent = true }
        case (.pending(let downAt), _):
            result.deadlineMilliseconds = saturatingAdd(downAt, holdMilliseconds)
        case (.interruptedUntilUp, .mappedKeyDown):
            result.consumeMappedEvent = true
        default:
            break
        }
        return result
    }

    private func saturatingAdd(_ value: Int, _ delta: Int) -> Int {
        let (sum, overflow) = value.addingReportingOverflow(delta)
        return overflow ? Int.max : sum
    }

    private func saturatingElapsed(_ value: Int, since earlier: Int) -> Int {
        let (elapsed, overflow) = value.subtractingReportingOverflow(earlier)
        return overflow ? (value >= earlier ? Int.max : Int.min) : elapsed
    }
}
