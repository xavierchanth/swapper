import ApplicationServices
import AppKit
import Carbon
import Foundation

enum HyperEventTapError: Error { case accessibilityRequired, secureInputActive, creationFailed }

@MainActor
final class HyperEventTap: HyperTapBackend {
    static let mappedVirtualKey: Int64 = 79 // F18, the hidutil destination usage 0x6d.
    private let marker = Int64.random(in: 1...Int64.max)
    private var resolver: HyperResolver?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var deadlineTimer: Timer?
    private var secureTimer: Timer?
    private var interruption: (@Sendable () -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start(holdMilliseconds: Int, interruption: @escaping @Sendable () -> Void) async throws {
        await stop()
        guard AXIsProcessTrusted() else { throw HyperEventTapError.accessibilityRequired }
        guard !IsSecureEventInputEnabled() else { throw HyperEventTapError.secureInputActive }
        guard let resolver = HyperResolver(holdMilliseconds: holdMilliseconds) else { throw HyperBackendError.malformedOutput }
        self.resolver = resolver
        self.interruption = interruption
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, pointer in
            guard let pointer else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let owner = Unmanaged<HyperEventTap>.fromOpaque(pointer).takeUnretainedValue()
                return owner.handle(type, event) ? nil : Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()) else { self.resolver = nil; throw HyperEventTapError.creationFailed }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.tap = tap; self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes); CGEvent.tapEnable(tap: tap, enable: true)
        let center = NSWorkspace.shared.notificationCenter
        observers = [center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.interrupt(notify: true) }
        }]
    }

    func stop() async {
        interrupt()
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        source = nil; tap = nil; resolver = nil
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers.removeAll(); interruption = nil
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            interrupt(notify: true); if let tap { CGEvent.tapEnable(tap: tap, enable: true) }; return false
        }
        guard event.getIntegerValueField(.eventSourceUserData) != marker else { return false }
        guard !IsSecureEventInputEnabled() else { interrupt(notify: true); return false }
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        let repeatValue = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        let input: HyperResolverInput?
        if key == Self.mappedVirtualKey { input = type == .keyDown ? .mappedKeyDown(isRepeat: repeatValue) : .mappedKeyUp }
        else { input = type == .keyDown ? .otherKeyDown(isRepeat: repeatValue) : nil }
        guard var resolver else { return false }
        if input == nil {
            if resolver.isHoldingHyper { event.flags.formUnion([.maskControl, .maskShift, .maskAlternate, .maskCommand]) }
            return false
        }
        let result = resolver.receive(input!, at: Self.now); self.resolver = resolver
        schedule(result.deadlineMilliseconds)
        if result.addHyperFlags { event.flags.formUnion([.maskControl, .maskShift, .maskAlternate, .maskCommand]) }
        if result.emitEscapeTap { postEscape() }
        updateSecureTimer()
        return result.consumeMappedEvent
    }

    private func schedule(_ deadline: Int?) {
        deadlineTimer?.invalidate(); deadlineTimer = nil
        guard let deadline else { return }
        let value = Timer(timeInterval: max(0, Double(deadline - Self.now) / 1000), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, var resolver = self.resolver else { return }
                let result = resolver.receive(.deadline, at: Self.now); self.resolver = resolver
                self.schedule(result.deadlineMilliseconds); self.updateSecureTimer()
            }
        }
        deadlineTimer = value; RunLoop.main.add(value, forMode: .common)
    }

    private func postEscape() {
        guard let eventSource = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: eventSource, virtualKey: 53, keyDown: true),
              let up = CGEvent(keyboardEventSource: eventSource, virtualKey: 53, keyDown: false) else { return }
        for event in [down, up] { event.setIntegerValueField(.eventSourceUserData, value: marker); event.post(tap: .cgSessionEventTap) }
    }

    private func updateSecureTimer() {
        guard resolver?.isGestureActive == true else { secureTimer?.invalidate(); secureTimer = nil; return }
        guard secureTimer == nil else { return }
        let value = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in MainActor.assumeIsolated { if IsSecureEventInputEnabled() { self?.interrupt(notify: true) } } }
        secureTimer = value; RunLoop.main.add(value, forMode: .common)
    }
    private func interrupt(notify: Bool = false) {
        if var resolver { _ = resolver.receive(.interrupted, at: Self.now); self.resolver = resolver }
        deadlineTimer?.invalidate(); deadlineTimer = nil; secureTimer?.invalidate(); secureTimer = nil
        if notify { interruption?() }
    }
    private static var now: Int { Int(ProcessInfo.processInfo.systemUptime * 1000) }
}
