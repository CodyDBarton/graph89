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
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session", "--start-asleep"]
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

    private func statistics(_ app: XCUIApplication) -> [Double] {
        let text = app.staticTexts["Engine status"].value as? String ?? ""
        let values = text.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(values.count, 3)
        return values.count == 3 ? values : [0, 0, 0]
    }
    private func setSpeedEnd(_ app: XCUIApplication, high: Bool) {
        let slider = app.sliders["CPU Speed"]
        slider.adjust(toNormalizedSliderPosition: high ? 1 : 0)
        // XCTest's adjustment is approximate on iPad. Finish by dragging the thumb
        // beyond the track edge so the real control reaches its exact endpoint.
        let fraction = Double(app.staticTexts["CPU speed value"].label.dropLast()) ?? 100
        let x = (fraction - 30) / 220
        slider.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: high ? 1.15 : -0.15, dy: 0.5)))
    }
    private func rate(_ app: XCUIApplication) -> Double {
        let first = statistics(app)[0]
        let start = ProcessInfo.processInfo.systemUptime
        Thread.sleep(forTimeInterval: 1)
        return (statistics(app)[0] - first) / (ProcessInfo.processInfo.systemUptime - start)
    }
    func testSettingsPersistAndChangeEngineSpeed() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        tap(app, "Configuration Settings")
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "100%")
        let turbo = app.switches["Overclock when Busy"]
        XCTAssertEqual(turbo.value as? String, "1")
        turbo.tap()
        tap(app, "Done")
        let baseline = rate(app)
        tap(app, "Configuration Settings")
        setSpeedEnd(app, high: true)
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "250%")
        tap(app, "Done")
        let fast = rate(app)
        XCTAssertGreaterThan(fast, baseline * 3, "Speed must affect actual engine execution")
        tap(app, "Configuration Settings")
        setSpeedEnd(app, high: false)
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "30%")
        tap(app, "Done")
        let slow = rate(app)
        XCTAssertLessThan(slow, baseline * 0.3)
        XCTAssertEqual(statistics(app)[1], 0, "Idle calculator must not receive turbo batches")
        app.terminate()
        app.launchArguments = ["--ui-test"]
        app.launch()
        tap(app, "Configuration Settings")
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "30%")
        XCTAssertEqual(app.switches["Overclock when Busy"].value as? String, "0")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        tap(app, "Restore Defaults")
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "100%")
        XCTAssertEqual(app.switches["Overclock when Busy"].value as? String, "1")
        tap(app, "Done")
        print("ENGINE_RATES: 30%=\(slow), 100%=\(baseline), 250%=\(fast)")
    }
    func testBusyOverclockRunsOnlyWhileBusyAndCanBeDisabled() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session", "--ui-test-benchmark"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        let accelerated = NSPredicate { _, _ in self.statistics(app)[1] > 0 }
        expectation(for: accelerated, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        tap(app, "Configuration Settings")
        app.switches["Overclock when Busy"].tap()
        tap(app, "Done")
        let stoppedAt = statistics(app)[1]
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(statistics(app)[1], stoppedAt, "Disabling overclock must stop extra batches immediately")
        let completed = NSPredicate { _, _ in self.statistics(app)[2] == 0 }
        expectation(for: completed, evaluatedWith: app)
        waitForExpectations(timeout: 90)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        let beforeIdle = statistics(app)[1]
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(statistics(app)[1], beforeIdle)
    }
    func testMaximumOverclockKeepsSettingsAndONResponsive() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session", "--ui-test-benchmark", "--ui-test-stress"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        let calculating = NSPredicate { _, _ in
            let values = self.statistics(app)
            return values[1] > 0 && values[2] == 1
        }
        expectation(for: calculating, evaluatedWith: app)
        waitForExpectations(timeout: 60)
        let start = statistics(app)[1]
        let time = ProcessInfo.processInfo.systemUptime
        Thread.sleep(forTimeInterval: 1)
        let maximumRate = (statistics(app)[1] - start) / (ProcessInfo.processInfo.systemUptime - time)
        tap(app, "Configuration Settings")
        app.switches["Overclock when Busy"].tap()
        tap(app, "Done")
        let normalRate = rate(app)
        XCTAssertEqual(statistics(app)[2], 1, "The stress calculation should still be running")
        XCTAssertGreaterThan(maximumRate, normalRate * 2, "Busy mode must remove normal pacing")
        tap(app, "Configuration Settings")
        app.switches["Overclock when Busy"].tap()
        tap(app, "Done")
        tap(app, "ON")
        let interrupted = NSPredicate { _, _ in self.statistics(app)[2] == 0 }
        expectation(for: interrupted, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        print("MAXIMUM_BUSY_RATE: maximum=\(maximumRate), normal=\(normalRate), ratio=\(maximumRate / normalRate)")
    }

    func testSettingsRemainReachableInLandscape() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1)
        tap(app, "Configuration Settings")
        XCTAssertTrue(app.sliders["CPU Speed"].isHittable)
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(app.switches["Overclock when Busy"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        tap(app, "Done")
        XCTAssertTrue(app.buttons["Configuration Settings"].isHittable)
    }

}
