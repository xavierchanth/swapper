import AppKit
import Combine
import OSLog

/// Owns XMT's menu-bar hiding controls for the application lifetime.
/// Separator-width technique derived from Hidden Bar (MIT): https://github.com/dwarvesf/hidden
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    private let logger = Logger(subsystem: "com.xavierchanth.xmt", category: "MenuBar")
    private let settings: MenuBarHidingSettings
    private let arrowItem: NSStatusItem
    private let separatorItem: NSStatusItem
    private let contextMenu = NSMenu(title: "XMT")
    private var autoHideTimer: Timer?
    private var cancellables: Set<AnyCancellable> = []
    private var isExpanded = true
    private var isMenuTracking = false

    override convenience init() { self.init(settings: .shared) }

    init(settings: MenuBarHidingSettings) {
        self.settings = settings
        // New status items are inserted to the left. Creating the arrow first leaves the
        // separator immediately to its left, with the user-selected hidden items beyond it.
        arrowItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        separatorItem = NSStatusBar.system.statusItem(withLength: MenuBarHidingGeometry.expandedSeparatorLength)
        super.init()
        arrowItem.autosaveName = "XMT.MenuBarHiding.Arrow"
        separatorItem.autosaveName = "XMT.MenuBarHiding.Separator"
        configureItems()
        configureMenu()
        observeState()
        settings.refreshCompetingAppStatus()
        applyEnabledState()
    }

    func stop() {
        invalidateAutoHide()
        cancellables.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NSStatusBar.system.removeStatusItem(separatorItem)
        NSStatusBar.system.removeStatusItem(arrowItem)
    }

    private func configureItems() {
        guard let arrowButton = arrowItem.button, let separatorButton = separatorItem.button else {
            logger.fault("A menu-bar hiding status item has no button")
            return
        }
        arrowButton.imagePosition = .imageOnly
        arrowButton.target = self
        arrowButton.action = #selector(handleArrowClick)
        arrowButton.sendAction(on: [.leftMouseUp, .rightMouseUp])

        separatorButton.title = "│"
        separatorButton.toolTip = "Command-drag menu bar items across this separator"
        separatorButton.setAccessibilityLabel("Hidden menu bar items separator")
        separatorButton.target = self
        separatorButton.action = #selector(showContextMenu)
        updateArrow()
    }

    private func configureMenu() {
        contextMenu.delegate = self
        contextMenu.addItem(menuItem("Settings…", action: #selector(showSettings), key: ","))
        contextMenu.addItem(.separator())
        contextMenu.addItem(menuItem("Quit XMT", action: #selector(quit), key: "q"))
    }

    private func observeState() {
        settings.$isEnabled.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyEnabledState() }
        }.store(in: &cancellables)
        settings.$autoHideSeconds.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.scheduleAutoHideIfNeeded() }
        }.store(in: &cancellables)
        settings.$isCompetingAppRunning.removeDuplicates().dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.applyEnabledState() }
        }.store(in: &cancellables)

        NotificationCenter.default.addObserver(
            self, selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceApplicationsChanged),
            name: NSWorkspace.didLaunchApplicationNotification, object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceApplicationsChanged),
            name: NSWorkspace.didTerminateApplicationNotification, object: nil
        )
    }

    private var canHide: Bool { settings.isEnabled && !settings.isCompetingAppRunning }

    private func applyEnabledState() {
        guard canHide else {
            expand(scheduleAutoHide: false)
            arrowItem.isVisible = false
            separatorItem.isVisible = false
            return
        }
        arrowItem.isVisible = true
        separatorItem.isVisible = true
        expand()
        updateArrow()
    }

    private func expand(scheduleAutoHide: Bool = true) {
        isExpanded = true
        separatorItem.length = MenuBarHidingGeometry.expandedSeparatorLength
        updateArrow()
        scheduleAutoHide ? scheduleAutoHideIfNeeded() : invalidateAutoHide()
    }

    private func collapse() {
        guard canHide else { return }
        guard MenuBarHidingGeometry.isSeparatorSafelyLeft(
            separatorFrame: separatorItem.button?.window?.frame,
            arrowFrame: arrowItem.button?.window?.frame
        ) else {
            logger.error("Refusing to collapse because the separator is not left of the recovery arrow")
            settings.setPlacementCorrectionNeeded(true)
            expand(scheduleAutoHide: false)
            return
        }
        settings.setPlacementCorrectionNeeded(false)
        isExpanded = false
        separatorItem.length = MenuBarHidingGeometry.collapsedSeparatorLength(
            screenWidths: NSScreen.screens.map(\.frame.width)
        )
        updateArrow()
        invalidateAutoHide()
    }

    private func scheduleAutoHideIfNeeded() {
        invalidateAutoHide()
        guard canHide, isExpanded, !isMenuTracking else { return }
        autoHideTimer = Timer.scheduledTimer(withTimeInterval: settings.autoHideSeconds, repeats: false) {
            [weak self] _ in Task { @MainActor in self?.autoHideTimerFired() }
        }
    }

    private func autoHideTimerFired() {
        autoHideTimer = nil
        guard !isMenuTracking else { scheduleAutoHideIfNeeded(); return }
        if MenuBarHidingGeometry.isPointerInMenuBar(NSEvent.mouseLocation, screens: NSScreen.screens) {
            scheduleAutoHideIfNeeded()
        } else {
            collapse()
        }
    }

    private func invalidateAutoHide() {
        autoHideTimer?.invalidate()
        autoHideTimer = nil
    }

    private func updateArrow() {
        let symbol = isExpanded ? "chevron.right" : "chevron.left"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        image?.isTemplate = true
        arrowItem.button?.image = image
        let unavailableReason = settings.isCompetingAppRunning
            ? "Hidden Bar is running; quit it before enabling XMT menu bar hiding"
            : "Menu bar hiding is disabled; right-click for Settings"
        arrowItem.button?.toolTip = canHide ? "Show or hide menu bar items" : unavailableReason
        arrowItem.button?.setAccessibilityLabel(
            canHide ? (isExpanded ? "Hide menu bar items" : "Show hidden menu bar items") : unavailableReason
        )
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { isMenuTracking = true; invalidateAutoHide() }
    func menuDidClose(_ menu: NSMenu) { isMenuTracking = false; scheduleAutoHideIfNeeded() }

    @objc private func handleArrowClick() {
        if NSApp.currentEvent?.type == .rightMouseUp { showContextMenu() }
        else if canHide { isExpanded ? collapse() : expand() }
    }

    @objc private func showContextMenu() {
        invalidateAutoHide()
        arrowItem.menu = contextMenu
        arrowItem.button?.performClick(nil)
        arrowItem.menu = nil
    }

    @objc private func screenParametersChanged() { if !isExpanded { collapse() } }
    @objc private func workspaceApplicationsChanged() { settings.refreshCompetingAppStatus() }
    @objc private func showSettings() { SettingsWindowController.shared.show() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
