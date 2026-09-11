import XCTest

@MainActor
final class MenuBarHidingSettingsTests: XCTestCase {
    func testDefaultsToEnabledWithSixtySecondAutoHide() {
        let settings = MenuBarHidingSettings(defaults: isolatedDefaults(), hiddenBarDefaults: nil,
                                             hiddenBarPreferencesURL: nil)
        XCTAssertTrue(settings.isEnabled)
        XCTAssertEqual(settings.autoHideSeconds, 60)
    }

    func testChangesPersistAcrossSettingsInstances() {
        let defaults = isolatedDefaults()
        let settings = MenuBarHidingSettings(defaults: defaults, hiddenBarDefaults: nil,
                                             hiddenBarPreferencesURL: nil)
        settings.setEnabled(false)
        settings.setAutoHideSeconds(125)
        let restored = MenuBarHidingSettings(defaults: defaults, hiddenBarDefaults: nil,
                                             hiddenBarPreferencesURL: nil)
        XCTAssertFalse(restored.isEnabled)
        XCTAssertEqual(restored.autoHideSeconds, 125)
    }

    func testImportsHiddenBarDelayOnlyOnce() {
        let defaults = isolatedDefaults()
        let hidden = isolatedDefaults()
        hidden.set(45.0, forKey: "numberOfSecondForAutoHide")
        XCTAssertEqual(MenuBarHidingSettings(defaults: defaults, hiddenBarDefaults: hidden).autoHideSeconds, 45)
        hidden.set(90.0, forKey: "numberOfSecondForAutoHide")
        XCTAssertEqual(MenuBarHidingSettings(defaults: defaults, hiddenBarDefaults: hidden).autoHideSeconds, 45)
    }

    func testValidationAndCompetingAppDetection() {
        XCTAssertEqual(MenuBarHidingSettings.validatedAutoHideSeconds(0), 1)
        XCTAssertEqual(MenuBarHidingSettings.validatedAutoHideSeconds(9_000), 3_600)
        XCTAssertEqual(MenuBarHidingSettings.validatedAutoHideSeconds(.nan), 60)
        let settings = MenuBarHidingSettings(defaults: isolatedDefaults(), hiddenBarDefaults: nil,
                                             hiddenBarPreferencesURL: nil,
                                             runningBundleIdentifiers: { ["com.dwarvesv.minimalbar"] })
        settings.refreshCompetingAppStatus()
        XCTAssertTrue(settings.isCompetingAppRunning)
    }

    private func isolatedDefaults() -> UserDefaults {
        let suite = "MenuBarHidingSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}
