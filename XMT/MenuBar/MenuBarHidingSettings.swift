import AppKit
import Combine

enum MenuBarHidingGeometry {
    static let expandedSeparatorLength: CGFloat = 20
    static let minimumCollapsedLength: CGFloat = 500
    static let maximumCollapsedLength: CGFloat = 10_000

    static func collapsedSeparatorLength(screenWidths: [CGFloat]) -> CGFloat {
        let widest = screenWidths.max() ?? minimumCollapsedLength
        return max(minimumCollapsedLength, min(widest * 2, maximumCollapsedLength))
    }

    static func isPointerInMenuBar(_ point: NSPoint, screens: [NSScreen]) -> Bool {
        screens.contains { screen in
            NSRect(x: screen.frame.minX, y: screen.visibleFrame.maxY, width: screen.frame.width,
                   height: max(0, screen.frame.maxY - screen.visibleFrame.maxY)).contains(point)
        }
    }

    static func isSeparatorSafelyLeft(separatorFrame: NSRect?, arrowFrame: NSRect?) -> Bool {
        guard let separatorFrame, let arrowFrame,
              !separatorFrame.isEmpty, !arrowFrame.isEmpty else { return false }
        return separatorFrame.midX < arrowFrame.midX
    }
}

@MainActor
final class MenuBarHidingSettings: ObservableObject {
    static let shared = MenuBarHidingSettings()
    static let defaultAutoHideSeconds: Double = 60
    static let allowedAutoHideRange: ClosedRange<Double> = 1...3_600
    static let competingBundleIdentifiers: Set<String> = ["com.dwarvesv.minimalbar"]

    @Published private(set) var isEnabled: Bool
    @Published private(set) var autoHideSeconds: Double
    @Published private(set) var isCompetingAppRunning = false
    @Published private(set) var placementCorrectionNeeded = false

    private enum Key {
        static let isEnabled = "menuBarHiding.isEnabled"
        static let autoHideSeconds = "menuBarHiding.autoHideSeconds"
        static let didImportHiddenBar = "menuBarHiding.didImportHiddenBar"
    }

    private let defaults: UserDefaults
    private let runningBundleIdentifiers: () -> Set<String>

    init(defaults: UserDefaults = .standard,
         hiddenBarDefaults: UserDefaults? = UserDefaults(suiteName: "com.dwarvesv.minimalbar"),
         hiddenBarPreferencesURL: URL? = FileManager.default.homeDirectoryForCurrentUser
             .appendingPathComponent("Library/Containers/com.dwarvesv.minimalbar/Data/Library/Preferences")
             .appendingPathComponent("com.dwarvesv.minimalbar.plist"),
         runningBundleIdentifiers: @escaping () -> Set<String> = {
             Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
         }) {
        self.defaults = defaults
        self.runningBundleIdentifiers = runningBundleIdentifiers
        isEnabled = defaults.object(forKey: Key.isEnabled) as? Bool ?? true

        let storedDelay = defaults.object(forKey: Key.autoHideSeconds) as? Double
        let shouldImport = !defaults.bool(forKey: Key.didImportHiddenBar)
        let importedDelay: Double? = if shouldImport {
            hiddenBarDefaults?.object(forKey: "numberOfSecondForAutoHide") as? Double
                ?? defaults.persistentDomain(forName: "com.dwarvesv.minimalbar")?["numberOfSecondForAutoHide"] as? Double
                ?? Self.hiddenBarDelay(from: hiddenBarPreferencesURL)
        } else {
            nil
        }
        autoHideSeconds = Self.validatedAutoHideSeconds(
            storedDelay ?? importedDelay ?? Self.defaultAutoHideSeconds
        )
        if storedDelay == nil { defaults.set(autoHideSeconds, forKey: Key.autoHideSeconds) }
        if shouldImport { defaults.set(true, forKey: Key.didImportHiddenBar) }
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Key.isEnabled)
    }

    func setAutoHideSeconds(_ seconds: Double) {
        let validated = Self.validatedAutoHideSeconds(seconds)
        guard validated != autoHideSeconds else { return }
        autoHideSeconds = validated
        defaults.set(validated, forKey: Key.autoHideSeconds)
    }

    func refreshCompetingAppStatus() {
        isCompetingAppRunning = !runningBundleIdentifiers().isDisjoint(with: Self.competingBundleIdentifiers)
    }

    func setPlacementCorrectionNeeded(_ needed: Bool) {
        placementCorrectionNeeded = needed
    }

    static func validatedAutoHideSeconds(_ seconds: Double) -> Double {
        guard seconds.isFinite else { return defaultAutoHideSeconds }
        return min(max(seconds, allowedAutoHideRange.lowerBound), allowedAutoHideRange.upperBound)
    }

    private static func hiddenBarDelay(from url: URL?) -> Double? {
        guard let url, let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else { return nil }
        if let value = dictionary["numberOfSecondForAutoHide"] as? NSNumber {
            return value.doubleValue
        }
        return dictionary["numberOfSecondForAutoHide"] as? Double
    }
}
