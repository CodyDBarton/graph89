import XCTest

final class Graph89UITests: XCTestCase {
    private func pixels(_ app: XCUIApplication) -> Data? {
        guard let value = app.images["Calculator display"].value as? String else { return nil }
        return Data(base64Encoded: value)
    }
    private func tap(_ app: XCUIApplication, _ name: String) {
        let button = app.buttons[name]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing key: \(name)")
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        // Allow the emulated calculator to scan and release each key.
        Thread.sleep(forTimeInterval: 0.2)
    }
    func testMouseStyleTapsCalculateAndWakeSleepingCalculator() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--fresh-session", "--start-asleep"]
        app.launch()
        let display = app.images["Calculator display"]
        XCTAssertTrue(display.waitForExistence(timeout: 15))
        let asleep = NSPredicate { _, _ in
            guard let data = self.pixels(app), data.count == 16000 else { return false }
            return data.allSatisfy { $0 == 210 }
        }
        expectation(for: asleep, evaluatedWith: display)
        waitForExpectations(timeout: 10)
        tap(app, "HOME")
        let awake = NSPredicate { _, _ in self.pixels(app)?.contains(30) == true }
        expectation(for: awake, evaluatedWith: display)
        waitForExpectations(timeout: 10)
        tap(app, "CLEAR")
        let before = pixels(app)
        tap(app, "K2")
        XCTAssertNotEqual(before, pixels(app), "The coordinate tap must reach the calculator")
        tap(app, "PLUS")
        tap(app, "K3")
        tap(app, "ENTER")
        guard let actual = pixels(app), let url = Bundle(for: Self.self).url(forResource: "expected-five", withExtension: "pgm"),
              let expectedPGM = try? Data(contentsOf: url) else {
            XCTFail("Missing display or native reference image"); return
        }
        let expected = Data(expectedPGM.suffix(16000))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        var pgm = Data("P5\n160 100\n255\n".utf8)
        pgm.append(actual)
        let displayAttachment = XCTAttachment(data: pgm, uniformTypeIdentifier: "public.data")
        displayAttachment.name = "actual-display.pgm"
        displayAttachment.lifetime = .keepAlways
        add(displayAttachment)
        // Compare the result area with the native engine's independently entered 2+3 result.
        for y in 70..<84 {
            XCTAssertEqual(actual.subdata(in: (y*160+146)..<(y*160+160)), expected.subdata(in: (y*160+146)..<(y*160+160)), "Result differs on row \(y)")
        }
    }
}
