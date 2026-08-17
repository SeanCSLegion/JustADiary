import XCTest

/// Regression tests for the two runtime-configuration bugs:
/// 1. Switching the in-app language did nothing until the app was restarted.
/// 2. Switching the theme (esp. dark mode / canvas layers) needed a restart.
///
/// The app must be running with the simulator in Chinese (zh-Hans) for the
/// Chinese element lookups below; language and theme are reset on launch via
/// the `-ui-test-reset-settings` argument.
final class LanguageThemeUITests: XCTestCase {

    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-test-reset-settings",
                               "-ui-test-state",
                               "-ui-test-tab", "settings"]
        app.launch()
        // Settings page must open in Chinese (simulator region zh-Hans)
        XCTAssertTrue(app.staticTexts["设置"].waitForExistence(timeout: 12),
                      "settings page should open in Chinese")
    }

    /// The `-ui-test-state` probe exposes the live app language/theme so tests
    /// can assert actual application state, not just rendered strings.
    private func appState() -> String {
        let probe = app.staticTexts["app.state"]
        guard probe.waitForExistence(timeout: 4) else { return "missing" }
        return probe.label
    }

    /// Average luminance of a screen region given in points. The app background
    /// asset is #FAF9FD (~0.97 luminance) in light mode and #101318 (~0.07) in
    /// dark mode, so 0.5 cleanly separates the themes even with the blurred blob
    /// tints present in the region.
    private func regionLuminance(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat) -> CGFloat? {
        let image = XCUIScreen.main.screenshot().image
        guard let cg = image.cgImage,
              let data = cg.dataProvider?.data,
              let ptr = CFDataGetBytePtr(data) else { return nil }
        let scale = image.scale > 0 ? image.scale : 1
        let bpr = cg.bytesPerRow
        let bpp = cg.bitsPerPixel / 8
        let sx = Int(x * scale), sy = Int(y * scale)
        let sw = Int(w * scale), sh = Int(h * scale)
        var sum: CGFloat = 0
        var count: CGFloat = 0
        for row in sy..<min(sy + sh, cg.height) {
            for col in sx..<min(sx + sw, cg.width) {
                let off = row * bpr + col * bpp
                guard off + 2 < CFDataGetLength(data) else { continue }
                let r = CGFloat(ptr[off]) / 255
                let g = CGFloat(ptr[off + 1]) / 255
                let b = CGFloat(ptr[off + 2]) / 255
                sum += 0.299 * r + 0.587 * g + 0.114 * b
                count += 1
            }
        }
        return count > 0 ? sum / count : nil
    }

    @discardableResult
    private func tapRow(_ label: String) throws -> Bool {
        let staticText = app.staticTexts[label]
        if staticText.firstMatch.waitForExistence(timeout: 4) {
            staticText.firstMatch.tap()
            return true
        }
        let button = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        if button.waitForExistence(timeout: 4) {
            button.tap()
            return true
        }
        return false
    }

    private func attachScreenshot(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testDarkThemeAppliesWithoutRestart() throws {
        // Baseline: fresh launch is light theme.
        sleep(2)
        let lightLum = regionLuminance(x: 60, y: 130, w: 160, h: 50)
        XCTAssertNotNil(lightLum, "could not sample light-mode pixels")
        XCTAssertGreaterThan(lightLum ?? 0, 0.5, "expected a bright light theme at launch")

        // Switch to dark theme in Settings -> Theme -> Dark (no restart).
        XCTAssertTrue(try tapRow("主题"), "theme row should be reachable")
        let darkOption = app.buttons["深色"]
        XCTAssertTrue(darkOption.waitForExistence(timeout: 5), "dark theme option in dialog")
        darkOption.tap()

        // The whole UI — including the settings screen — must turn dark at once.
        sleep(2)
        let darkLum = regionLuminance(x: 60, y: 130, w: 160, h: 50)
        XCTAssertNotNil(darkLum, "could not sample dark-mode pixels")
        XCTAssertLessThan(darkLum ?? 1, 0.5, "dark theme should apply without restart")
        let darkState = appState()
        XCTAssertTrue(darkState.contains("T:dark"),
                      "app state should report dark theme, got: \(darkState)")

        // Visit the calendar home screen: the canvas-drawn calendar must be dark too.
        app.buttons["日记"].firstMatch.tap()
        sleep(2)
        let homeDark = regionLuminance(x: 60, y: 130, w: 160, h: 50)
        XCTAssertNotNil(homeDark, "could not sample home-screen pixels")
        XCTAssertLessThan(homeDark ?? 1, 0.5, "home calendar canvas should be dark without restart")
        attachScreenshot(name: "dark-home")

        // Go back to settings for the language half of the sequence.
        app.buttons["设置"].firstMatch.tap()
        sleep(1)
    }

    func testLanguageSwitchesImmediatelyAndSurvivesRestart() throws {
        // Switch language to English in Settings (no restart).
        XCTAssertTrue(try tapRow("语言"), "language row should be reachable")
        let englishOption = app.buttons["English"]
        XCTAssertTrue(englishOption.waitForExistence(timeout: 5), "English option in dialog")
        englishOption.tap()

        // The page header and tab labels must switch to English immediately.
        let enHeader = app.staticTexts["Settings"]
        XCTAssertTrue(enHeader.waitForExistence(timeout: 8),
                      "settings header should become 'Settings' without restart")
        XCTAssertTrue(app.buttons["Diary"].waitForExistence(timeout: 4), "home tab in English")
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 4), "map tab in English")
        XCTAssertTrue(app.buttons["Search"].waitForExistence(timeout: 4), "search tab in English")
        let enState = appState()
        XCTAssertTrue(enState.contains("L:en"),
                      "app state should report English, got: \(enState)")

        // The calendar lives on the home tab: check its month name is English.
        app.buttons["Diary"].firstMatch.tap()
        sleep(2)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM"
        let monthName = formatter.string(from: Date())
        XCTAssertTrue(app.staticTexts[monthName].exists,
                      "home calendar month title should be English ('\(monthName)')")
        attachScreenshot(name: "english-home")

        // Restart the app: the choice must persist and stay fully English.
        app.terminate()
        app.launchArguments = ["-ui-test-state", "-ui-test-tab", "settings"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Settings"].waitForExistence(timeout: 12),
                      "settings still English after restart")
        XCTAssertTrue(app.staticTexts["Language"].waitForExistence(timeout: 6),
                      "language row label in English after restart")
        let enStateAfterRestart = appState()
        XCTAssertTrue(enStateAfterRestart.contains("L:en"),
                      "app state should still report English after restart, got: \(enStateAfterRestart)")
        attachScreenshot(name: "english-after-restart")

        // Restore the Chinese default so sibling tests (Smoke, …) that expect the
        // zh-Hans UI keep working when the whole suite runs in one invocation.
        app.terminate()
        app.launchArguments = ["-ui-test-reset-settings"]
        app.launch()
        XCTAssertTrue(app.buttons["设置"].waitForExistence(timeout: 12),
                      "tab bar back to Chinese for subsequent tests")
        app.terminate()
    }
}