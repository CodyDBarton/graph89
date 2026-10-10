import XCTest
import UIKit

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

    func testSharpTextTogglePersistsAndPreservesCalculator() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        tap(app, "HOME"); tap(app, "CLEAR")
        tap(app, "K2"); tap(app, "PLUS"); tap(app, "K3"); tap(app, "ENTER")
        tap(app, "Configuration Settings")
        let sharp = app.switches["Sharp Text (Prototype)"]
        for _ in 0..<4 { if sharp.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(sharp.value as? String, "0")
        sharp.tap(); tap(app, "Done")
        let overlay = app.otherElements["Sharp text rendering"]
        let active = NSPredicate { _, _ in
            let value = overlay.value as? String ?? ""
            return value.hasPrefix("on:") && (Int(value.dropFirst(3)) ?? 0)>10
        }
        expectation(for: active, evaluatedWith: overlay); waitForExpectations(timeout: 10)
        let sharpShot = XCTAttachment(screenshot: app.screenshot()); sharpShot.name="HD Home"; sharpShot.lifetime = .keepAlways; add(sharpShot)
        // Enter derivative and integral using the calculator's own menus.
        tap(app, "CLEAR"); tap(app, "F3"); tap(app, "ENTER")
        for key in ["X", "^", "K3", ",", "X", ")", "ENTER"] { tap(app,key) }
        let symbols = XCTAttachment(screenshot: app.screenshot()); symbols.name="HD derivative"; symbols.lifetime = .keepAlways; add(symbols)
        app.terminate(); app.launchArguments=["--ui-test", "--fresh-session"]; app.launch()
        tap(app, "Configuration Settings")
        for _ in 0..<4 { if sharp.isHittable { break }; app.swipeUp() }
        XCTAssertEqual(sharp.value as? String,"1", "Sharp Text must persist")
        sharp.tap(); tap(app,"Done")
        XCTAssertEqual(overlay.value as? String,"off:0")
        let rawShot = XCTAttachment(screenshot: app.screenshot()); rawShot.name="Original display";rawShot.lifetime = .keepAlways;add(rawShot)
    }

    func testSharpTextFractionalZoomRendering() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session", "--ui-test-sharp-text"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        tap(app,"HOME");tap(app,"CLEAR");tap(app,"F3");tap(app,"ENTER")
        for key in ["X", "^", "K3", ",", "X", ")", "ENTER"] { tap(app,key) }
        let overlay=app.otherElements["Sharp text rendering"]
        let active=NSPredicate { _, _ in (overlay.value as? String ?? "").hasPrefix("on:") }
        expectation(for:active,evaluatedWith:overlay);waitForExpectations(timeout:10)
        XCTAssertGreaterThan(Int(overlay.identifier.dropFirst("retained:".count)) ?? 0, 10, "Real ROM drawing calls must reach the rendered layer")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="HD clean derivative";shot.lifetime = .keepAlways;add(shot)
        tap(app,"UP");tap(app,"UP")
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="HD clean history";selected.lifetime = .keepAlways;add(selected)
    }

    func testSharpTallMathSelection() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","F3","DOWN","ENTER","K1","DIVIDE","(","K1","PLUS","X","^","K2",
                    ")",",","X",",","K0",",","K1",")","ENTER"] { tap(app,key) }
        Thread.sleep(forTimeInterval:1)
        let normal=XCTAttachment(screenshot:app.screenshot());normal.name="HD tall integral and parentheses normal";normal.lifetime = .keepAlways;add(normal)
        let before=pixels(app)
        tap(app,"UP");tap(app,"UP")
        XCTAssertNotEqual(before,pixels(app),"History selection must invert the expression")
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="HD tall integral and parentheses inverted";selected.lifetime = .keepAlways;add(selected)
    }

    func testSharpClippedMath() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-clipped-math"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","F3","DOWN","ENTER"] { tap(app,key) }
        for _ in 0..<6 { for key in ["K1","DIVIDE","("] { tap(app,key) } }
        for key in ["K1","PLUS","X","^","K2"] { tap(app,key) }
        for _ in 0..<6 { tap(app,")") }
        for key in [",","X",",","K0",",","K1",")","ENTER"] { tap(app,key) }
        Thread.sleep(forTimeInterval:1)
        let normalClip=app.otherElements["Sharp text rendering"].value as? String ?? ""
        XCTAssertTrue(normalClip.contains("math:3"), "All three full-height symbols must survive clipping: \(normalClip)")
        let normal=XCTAttachment(screenshot:app.screenshot());normal.name="HD clipped math normal";normal.lifetime = .keepAlways;add(normal)
        tap(app,"UP");tap(app,"UP")
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="HD clipped math inverted";selected.lifetime = .keepAlways;add(selected)
        let overlay=app.otherElements["Sharp text rendering"]
        XCTAssertGreaterThan(Int(overlay.identifier.dropFirst("retained:".count)) ?? 0,10)
        let selectedClip=overlay.value as? String ?? ""
        XCTAssertTrue(selectedClip.contains("inverse:3"), "All three clipped symbols must retain inversion: \(selectedClip)")
    }

    func testSharpInverseTrig() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-inverse-trig"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","DIAMOND","Z","X",")"] { tap(app,key) }
        let overlay=app.otherElements["Sharp text rendering"]
        XCTAssertTrue((overlay.value as? String ?? "").contains("raised:1"), "Inverse trig input must have a sharp raised -1")
        tap(app,"ENTER");Thread.sleep(forTimeInterval:1)
        XCTAssertTrue((overlay.value as? String ?? "").contains("raised:3"), "Input, pretty-printed command and result must all be sharp")
        let normal=XCTAttachment(screenshot:app.screenshot());normal.name="HD inverse trig normal";normal.lifetime = .keepAlways;add(normal)
        tap(app,"UP");tap(app,"UP")
        XCTAssertTrue((overlay.value as? String ?? "").contains("inverse:1"), "Selected history must retain the raised -1 in inverted text")
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="HD inverse trig inverted";selected.lifetime = .keepAlways;add(selected)
    }

    func testSharpCatalogTriangle() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","CATALOG","MINUS"] { tap(app,key) }
        let normal=XCTAttachment(screenshot:app.screenshot());normal.name="HD Catalog conversion triangles";normal.lifetime = .keepAlways;add(normal)
        // Catalog down navigation eventually selects the two P-triangle entries.
        for _ in 0..<4 { tap(app,"DOWN") }
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="HD Catalog selected triangle";selected.lifetime = .keepAlways;add(selected)
        tap(app,"ENTER")
        let input=XCTAttachment(screenshot:app.screenshot());input.name="HD conversion triangle input";input.lifetime = .keepAlways;add(input)
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
        app.scrollViews.firstMatch.swipeUp()
        tap(app, "Restore Defaults")
        XCTAssertEqual(app.staticTexts["CPU speed value"].label, "100%")
        XCTAssertEqual(app.switches["Overclock when Busy"].value as? String, "1")
        tap(app, "Done")
        print("ENGINE_RATES: 30%=\(slow), 100%=\(baseline), 250%=\(fast)")
    }
    func testHapticDurationAndKeyPressBehavior() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        func waitForCalculator() {
            let ready = NSPredicate { _, _ in self.pixels(app)?.count == 16000 }
            expectation(for: ready, evaluatedWith: app.images["Calculator display"])
            waitForExpectations(timeout: 15)
        }
        waitForCalculator()
        func requests() -> String? { app.staticTexts["Haptic requests"].value as? String }
        func openHaptics() {
            tap(app, "Configuration Settings")
            app.scrollViews.firstMatch.swipeUp()
            XCTAssertTrue(app.sliders["Haptic Feedback"].isHittable)
        }
        func endpoint(_ high: Bool) {
            let slider = app.sliders["Haptic Feedback"]
            slider.adjust(toNormalizedSliderPosition: high ? 1 : 0)
            let label = app.staticTexts["Haptic duration value"].label
            let current = Double(label.split(separator: " ").first ?? "0") ?? 0
            slider.coordinate(withNormalizedOffset: CGVector(dx: current / 30, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: high ? 1.15 : -0.15, dy: 0.5)))
        }
        app.buttons["HOME"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(requests(), "1", "Holding and releasing a key must produce only one haptic request")
        openHaptics()
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "8 ms")
        endpoint(false)
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "Disabled")
        tap(app, "Done")
        XCTAssertEqual(requests(), "1", "Settings buttons must not trigger calculator haptics")
        tap(app, "CLEAR")
        XCTAssertEqual(requests(), "1", "Disabled haptics must not request a vibration")
        openHaptics()
        endpoint(true)
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "30 ms")
        tap(app, "Done")
        app.terminate()
        app.launchArguments = ["--ui-test"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        waitForCalculator()
        tap(app, "HOME")
        XCTAssertEqual(requests(), "1")
        openHaptics()
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "30 ms")
        tap(app, "Restore Defaults")
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "8 ms")
        tap(app, "Done")
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

    private func chooseStretch(_ app: XCUIApplication, _ mode: String) {
        tap(app, "Configuration Settings")
        let chooser = app.buttons["Stretch mode"]
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertTrue(chooser.isHittable)
        chooser.tap()
        app.buttons[mode].tap()
        XCTAssertEqual(chooser.value as? String, mode)
        tap(app, "Done")
    }
    func testStretchModesApplyAndPersist() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        let face = app.otherElements["Calculator button face"]
        XCTAssertTrue(face.exists)
        let display = app.images["Calculator display"]
        let baseLCD = display.frame
        let baseFace = face.frame
        XCTAssertEqual(baseLCD.width, baseFace.width, accuracy: 1)
        let baselineHeight = baseFace.maxY - baseLCD.minY
        var horizontalHeight: CGFloat = 0
        for mode in ["Horizontal", "Vertical", "Horizontal and vertical", "Aspect ratio, full", "Aspect ratio, crop", "Aspect ratio; no loss"] {
            chooseStretch(app, mode)
            let lcd = display.frame
            let keys = face.frame
            let height = keys.maxY - lcd.minY
            XCTAssertEqual(lcd.width, keys.width, accuracy: 1)
            XCTAssertEqual(lcd.maxY, keys.minY, accuracy: 1)
            if mode == "Horizontal" {
                XCTAssertEqual(height, baselineHeight, accuracy: 1)
                XCTAssertEqual(lcd.width, app.frame.width, accuracy: 1)
                horizontalHeight = height
            } else if mode == "Vertical" {
                XCTAssertEqual(lcd.width, baseLCD.width, accuracy: 1)
                XCTAssertEqual(height, app.frame.height, accuracy: 1)
            } else if mode == "Horizontal and vertical" {
                XCTAssertEqual(lcd.width, app.frame.width, accuracy: 1)
                XCTAssertEqual(height, app.frame.height, accuracy: 1)
                XCTAssertGreaterThanOrEqual(height, horizontalHeight)
            } else {
                XCTAssertEqual(height / lcd.width, baselineHeight / baseLCD.width, accuracy: 0.01)
                if mode == "Aspect ratio; no loss" {
                    XCTAssertEqual(lcd.width, baseLCD.width, accuracy: 1)
                    XCTAssertEqual(height, baselineHeight, accuracy: 1)
                }
            }
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = mode
            shot.lifetime = .keepAlways
            add(shot)
        }
        chooseStretch(app, "Horizontal and vertical")
        app.terminate()
        app.launchArguments = ["--ui-test"]
        app.launch()
        tap(app, "Configuration Settings")
        app.scrollViews.firstMatch.swipeUp()
        XCTAssertEqual(app.buttons["Stretch mode"].value as? String, "Horizontal and vertical")
        tap(app, "Restore Defaults")
        XCTAssertEqual(app.buttons["Stretch mode"].value as? String, "Aspect ratio; no loss")
        tap(app, "Done")
    }

    func testVisibleCornerGearOpensSettings() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        // Tap the visible gear's center. These are screen coordinates. Use a short press to cover
        // quick mouse clicks, rather than only XCTest's longer synthetic taps.
        let isPad = app.frame.width > 600
        let horizontalInset: CGFloat = isPad ? 25 : 34
        let verticalInset: CGFloat = isPad ? 42 : 34
        defer { XCUIDevice.shared.orientation = .portrait }
        for orientation: UIDeviceOrientation in [.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1)
            for _ in 0..<2 {
                // Empty space immediately below the badge must not activate it.
                app.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0))
                    .withOffset(CGVector(dx: -horizontalInset, dy: verticalInset + 25))
                    .press(forDuration: 0.01)
                XCTAssertFalse(app.sliders["CPU Speed"].exists, "The gear must have no invisible tap area")
                let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                shot.lifetime = .keepAlways
                add(shot)
                app.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0))
                    .withOffset(CGVector(dx: -horizontalInset, dy: verticalInset)).press(forDuration: 0.01)
                XCTAssertTrue(app.sliders["CPU Speed"].waitForExistence(timeout: 5), "Tapping the visible gear must open Settings")
                tap(app, "Done")
            }
        }
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
        XCTAssertTrue(app.sliders["Haptic Feedback"].isHittable)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.lifetime = .keepAlways
        add(attachment)
        tap(app, "Done")
        tap(app, "Configuration Settings")
        XCTAssertTrue(app.sliders["CPU Speed"].waitForExistence(timeout: 5))
        tap(app, "Done")
    }

}
