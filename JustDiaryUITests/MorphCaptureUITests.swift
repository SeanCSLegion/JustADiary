import XCTest

final class MorphCaptureUITests: XCTestCase {
    func testCaptureMorphs() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SLOW_MORPH"] = "1"
        app.launch()
        sleep(3)
        let win = app.windows.firstMatch
        try? FileManager.default.createDirectory(atPath: "/tmp/morph5", withIntermediateDirectories: true)

        func snap(_ tag: String) {
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/morph5/\(tag).png"))
        }

        func tap(_ x: CGFloat, _ y: CGFloat) {
            win.coordinate(withNormalizedOffset: CGVector(dx: x, dy: y)).tap()
        }

        func full(_ tag: String) {
            for i in 0..<24 {
                usleep(130_000)
                snap("\(tag)_f\(i)")
            }
        }

        tap(0.21, 0.11)
        usleep(1_200_000)
        snap("year_rest")
        tap(0.5, 0.62)
        full("ym")
        usleep(1_200_000)
        snap("month_rest")
        tap(0.21, 0.11)
        full("my")
        usleep(1_200_000)
        snap("year_rest2")
    }
}