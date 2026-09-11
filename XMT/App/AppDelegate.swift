import AppKit
import Carbon
import OSLog

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "com.xavierchanth.xmt", category: "AppShell")
    // The delegate is retained by NSApplication; this is the sole strong process-lifetime owner.
    private var menuBarController: MenuBarController?
    private var isTerminating = false
    private var isDuplicateInstance = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            isDuplicateInstance = true
            if let url = existing.bundleURL {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.createsNewApplicationInstance = false
                NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            }
            NSApp.terminate(nil)
            return
        }
        logger.notice("XMT finished launching")
        precondition(menuBarController == nil, "A second XMT status item was requested")
        menuBarController = MenuBarController()
        logger.notice("AppKit status item installed")
        // Install callbacks and apply persisted state without prompting for permission.
        ModuleRegistry.shared.register()
        ConfigurationCoordinator.shared.register()
        // A crowded macOS 26 menu bar can clip status items. Always provide a visible
        // recovery surface when the user explicitly launches XMT.
        let event = NSAppleEventManager.shared().currentAppleEvent
        let loginLaunch = event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
            || event?.paramDescriptor(forKeyword: keyAELaunchedAsLogInItem) != nil
        if !loginLaunch { SettingsWindowController.shared.show() }
        Task { await HyperController.shared.start() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard !isDuplicateInstance, !isTerminating else { return }
        Task { @MainActor in
            AccessibilityService.shared.refresh()
            ModuleRegistry.shared.applicationDidBecomeActive()
            ConfigurationCoordinator.shared.reload()
            await HyperController.shared.applicationDidBecomeActive()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if isDuplicateInstance { return .terminateNow }
        guard !isTerminating else { return .terminateLater }
        isTerminating = true
        Task { @MainActor in
            let restored = await HyperController.shared.stop()
            if !restored {
                isTerminating = false
                SettingsWindowController.shared.show()
            }
            sender.reply(toApplicationShouldTerminate: restored)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        logger.notice("XMT will terminate")
        InputRoutingCoordinator.shared.stop()
        ModuleRegistry.shared.stopAll()
        menuBarController?.stop()
    }
}
