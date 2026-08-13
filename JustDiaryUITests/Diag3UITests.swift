import XCTest

final class Diag3UITests: XCTestCase {
    func testCapture() throws {
        let app = XCUIApplication()
        app.launchEnvironment["SLOW_MORPH"] = "1"
        app.launchArguments = ["-morph-log", "-morph-test"]
        app.launch()
        try? FileManager.default.createDirectory(atPath: "/tmp/diag3", withIntermediateDirectories: true)
        for i in 0..<80 {
            usleep(130_000)
            let shot = XCUIScreen.main.screenshot()
            try? shot.pngRepresentation.write(to: URL(fileURLWithPath: "/tmp/diag3/m\(i).png"))
        }
    }
}
