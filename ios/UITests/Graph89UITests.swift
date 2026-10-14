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
        guard let url = Bundle(for: Self.self).url(forResource: "expected-five", withExtension: "pgm"),
              let expectedPGM = try? Data(contentsOf: url) else {
            XCTFail("Missing display or native reference image"); return
        }
        let expected = Data(expectedPGM.suffix(16000))
        let resultReady = NSPredicate { _, _ in
            guard let actual = self.pixels(app), actual.count == 16000 else { return false }
            return (70..<84).allSatisfy { y in
                actual.subdata(in: (y*160+146)..<(y*160+160)) == expected.subdata(in: (y*160+146)..<(y*160+160))
            }
        }
        expectation(for: resultReady, evaluatedWith: display); waitForExpectations(timeout: 10)
        guard let actual = pixels(app) else { XCTFail("Missing final display"); return }
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

    func testRapidRepeatedTapsRemainDistinct() {
        let app = XCUIApplication()
        app.launchArguments = ["--ui-test", "--reset-settings", "--fresh-session"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        tap(app, "HOME"); tap(app, "CLEAR")
        for _ in 0..<6 { app.buttons["K1"].tap(withNumberOfTaps: 2, numberOfTouches: 1) }
        let complete = NSPredicate { _, _ in
            guard let bytes = self.pixels(app), bytes.count == 16000 else { return false }
            let first = (84..<94).flatMap { y in (0..<6).map { bytes[y*160+$0] } }
            guard first.contains(30) else { return false }
            return (1..<12).allSatisfy { cell in
                (84..<94).flatMap { y in (0..<6).map { bytes[y*160+cell*6+$0] } } == first
            }
        }
        expectation(for: complete, evaluatedWith: app.images["Calculator display"])
        waitForExpectations(timeout: 10)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Twelve distinct rapid taps"; attachment.lifetime = .keepAlways; add(attachment)
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

    func testSharpClippedMath() { checkClippedMath(compact:false) }
    func testCompactClippedMath() { checkClippedMath(compact:true) }
    private func checkClippedMath(compact:Bool) {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-clipped-math"]
        if compact { app.launchArguments.append("--ui-test-compact-layout") }
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
        if compact {
            let fullShapes=NSPredicate { _,_ in (overlay.value as? String ?? "").contains("compact:1,math:3,inverse:3") }
            expectation(for:fullShapes,evaluatedWith:overlay);waitForExpectations(timeout:5)
        }
        let selectedClip=overlay.value as? String ?? ""
        XCTAssertTrue(selectedClip.contains("inverse:3"), "All three clipped symbols must retain inversion: \(selectedClip)")
    }

    func testCompactHistoryPackingAndToggle() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout","--ui-test-history"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        let overlay=app.otherElements["Sharp text rendering"]
        func number(_ key:String)->Double {
            (overlay.value as? String ?? "").split(separator:",").first {$0.hasPrefix(key+":")}.flatMap {Double($0.dropFirst(key.count+1))} ?? -1
        }
        let filled=NSPredicate { _,_ in number("history")==1 && number("hentries")>=8 && number("hsaved")>0 }
        expectation(for:filled,evaluatedWith:overlay);waitForExpectations(timeout:45)
        // Wait for all twelve queued calculations, beyond the first full view.
        Thread.sleep(forTimeInterval:5)
        func capture(_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
        capture("Compact Home additional history")
        let before=pixels(app)?.subdata(in:2560..<13280)
        tap(app,"UP")
        XCTAssertNotEqual(before,pixels(app)?.subdata(in:2560..<13280))
        XCTAssertTrue(number("history")==1 && number("hentries")>=8)
        capture("Compact Home selected history")
        for _ in 0..<14 {tap(app,"UP")}
        XCTAssertTrue(number("history")==1 && number("hentries")>=8)
        capture("Compact Home scrolled history")
        tap(app,"ESC")
        let originalBody=pixels(app)?.subdata(in:2560..<13280)
        tap(app,"Configuration Settings")
        let compact=app.switches["Compact Layout (Prototype)"]
        for _ in 0..<5 {if compact.isHittable {break};app.swipeUp()}
        compact.tap();tap(app,"Done")
        XCTAssertEqual(originalBody,pixels(app)?.subdata(in:2560..<13280))
        capture("Original Home history spacing")
    }

    func testCompactCalculatedOutputAlignment() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"CLEAR")
        for key in ["X","^","K5","PLUS","X","^","K4","PLUS","X","^","K3","PLUS","X","^","K2","PLUS","X","PLUS","K1","ENTER"] {tap(app,key)}
        let overlay=app.otherElements["Sharp text rendering"]
        let aligned=NSPredicate { _,_ in (overlay.value as? String ?? "").contains("answers:1") }
        expectation(for:aligned,evaluatedWith:overlay);waitForExpectations(timeout:10)
        let nativeLeft=(overlay.value as? String ?? "").split(separator:",").first {$0.hasPrefix("answerLeft:")}.flatMap {Int($0.dropFirst(11))} ?? -1
        XCTAssertTrue(nativeLeft>=0 && nativeLeft<80,"Exercise a result that the old midpoint heuristic misclassified")
        func capture(_ name:String) {let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)}
        capture("Compact medium calculated answer aligned right")
        let before=pixels(app)
        tap(app,"Configuration Settings")
        let compact=app.switches["Compact Layout (Prototype)"]
        for _ in 0..<5 {if compact.isHittable {break};app.swipeUp()}
        compact.tap();tap(app,"Done")
        XCTAssertEqual(before,pixels(app),"Output layout must leave the calculator framebuffer untouched")
        capture("Sharp text medium answer original layout")
        tap(app,"Configuration Settings")
        let sharp=app.switches["Sharp Text (Prototype)"]
        for _ in 0..<5 {if sharp.isHittable {break};app.swipeUp()}
        sharp.tap();tap(app,"Done")
        XCTAssertEqual(before,pixels(app))
        capture("Original medium answer aligned right")
    }

    func testCompactFullContentAndToggle() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"CLEAR")
        for _ in 0..<10 { for key in ["(","X",")","PLUS"] {tap(app,key)} }
        tap(app,"X")
        let overlay=app.otherElements["Sharp text rendering"]
        XCTAssertTrue((overlay.value as? String ?? "").contains("input:37,full:41"),"Full editor must expose the scrolled-off text: \(overlay.value ?? "")")
        func capture(_ name:String) { let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a) }
        capture("Compact variable-width long input")
        func number(_ key:String)->Double {
            let value=overlay.value as? String ?? ""
            return value.split(separator:",").first(where:{$0.hasPrefix(key+":")}).flatMap {Double($0.dropFirst(key.count+1))} ?? -1
        }
        let start=number("start"),caret=number("caret")
        for _ in 0..<3 {tap(app,"LEFT")}
        XCTAssertEqual(number("start"),start,"Narrow-character cursor motion must not scroll inside the viewport")
        XCTAssertEqual(number("caret"),caret-12.9,accuracy:0.01,"Cursor must use actual character advances")
        for _ in 0..<3 {tap(app,"RIGHT")}
        tap(app,"ENTER");Thread.sleep(forTimeInterval:1)
        XCTAssertTrue((overlay.value as? String ?? "").contains("body:1"),"Full pretty print must be captured")
        capture("Compact wide pretty print")
        tap(app,"UP");tap(app,"UP");capture("Compact selected pretty print")
        let before=pixels(app)
        tap(app,"Configuration Settings")
        let compact=app.switches["Compact Layout (Prototype)"]
        for _ in 0..<5 { if compact.isHittable { break };app.swipeUp() }
        XCTAssertEqual(compact.value as? String,"1");compact.tap();tap(app,"Done")
        capture("Original spacing wide pretty print")
        XCTAssertEqual(before,pixels(app),"Changing presentation must preserve the calculator framebuffer")
        tap(app,"Configuration Settings")
        for _ in 0..<5 { if compact.isHittable { break };app.swipeUp() }
        XCTAssertEqual(compact.value as? String,"0");compact.tap();tap(app,"Done")
        capture("Compact spacing restored")
        XCTAssertTrue((overlay.value as? String ?? "").contains("compact:1"))
    }

    func testCompactYEditorAndEdgeScrolling() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"CLEAR");tap(app,"X");tap(app,"ENTER")
        let overlay=app.otherElements["Sharp text rendering"]
        XCTAssertTrue((overlay.value as? String ?? "").contains("body:1"))
        tap(app,"DIAMOND");tap(app,"F1")
        func checkY(_ name:String) {
            let value=overlay.value as? String ?? ""
            XCTAssertTrue(value.contains("body:1") && value.contains("yeditor:1"),"Y= must receive its own compact layout: \(value)")
            let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
        }
        checkY("Y editor with compact enabled")
        tap(app,"CLEAR");tap(app,"X");tap(app,"PLUS");tap(app,"K2")
        checkY("Y editor typing with compact enabled")
        for _ in 0..<15 {tap(app,"PLUS");tap(app,"X")}
        func number(_ key:String)->Double {
            let value=overlay.value as? String ?? ""
            return value.split(separator:",").first(where:{$0.hasPrefix(key+":")}).flatMap {Double($0.dropFirst(key.count+1))} ?? -1
        }
        let start=number("start"),caret=number("caret")
        XCTAssertGreaterThan(start,0)
        for _ in 0..<3 {tap(app,"LEFT")}
        XCTAssertEqual(number("start"),start,"Left within viewport must not scroll")
        XCTAssertEqual(number("caret"),caret-13.5,accuracy:0.01)
        for _ in 0..<27 {tap(app,"LEFT")}
        XCTAssertLessThan(number("start"),start,"Crossing left edge must scroll")
        checkY("Compact Y editor after scrolling left")
        tap(app,"ENTER");tap(app,"DOWN");checkY("Y editor next equation")
        tap(app,"HOME")
        XCTAssertTrue((overlay.value as? String ?? "").contains("body:1"),"Compact Home must resume")
    }

    func testCompactYEquationListAndToggle() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"DIAMOND");tap(app,"F1")
        tap(app,"CLEAR")
        for key in ["K1","DIVIDE","(","K1","DIVIDE","(","K1","PLUS","X","^","K2",")",")","ENTER"] {tap(app,key)}
        let overlay=app.otherElements["Sharp text rendering"]
        XCTAssertTrue((overlay.value as? String ?? "").contains("yeditor:1"))
        let saved=(overlay.value as? String ?? "").split(separator:",").first(where:{$0.hasPrefix("vsaved:")}).flatMap {Double($0.dropFirst(7))} ?? 0
        XCTAssertGreaterThan(saved,0,"Nested Y= fraction must actually tighten vertical spacing")
        let labels=(overlay.value as? String ?? "").split(separator:",").first(where:{$0.hasPrefix("edgeLabels:")}).flatMap {Int($0.dropFirst(11))} ?? 0
        XCTAssertGreaterThanOrEqual(labels,2,"Y= label crossing the original LCD boundary must retain both y and equals")
        let a=XCTAttachment(screenshot:app.screenshot());a.name="Compact Y equation list";a.lifetime = .keepAlways;add(a)
        let before=pixels(app)?.subdata(in:2560..<13280)
        tap(app,"Configuration Settings")
        let compact=app.switches["Compact Layout (Prototype)"]
        for _ in 0..<5 {if compact.isHittable {break};app.swipeUp()}
        compact.tap();tap(app,"Done")
        XCTAssertEqual(before,pixels(app)?.subdata(in:2560..<13280),"Toggle must preserve the calculator equation list")
        let b=XCTAttachment(screenshot:app.screenshot());b.name="Original Y equation list";b.lifetime = .keepAlways;add(b)
    }

    func testHDPlotEvaluatesAdditionalPointsAndToggle() { exerciseHDPlotNavigation(sharp:true) }
    func testHDPlotSharpNavigationWithOriginalText() { exerciseHDPlotNavigation(sharp:false) }
    private func exerciseHDPlotNavigation(sharp:Bool) {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-hd-plot"]
        if sharp {app.launchArguments.append("--ui-test-sharp-text")}
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:20))
        tap(app,"DIAMOND");tap(app,"F3")
        let overlay=app.otherElements["Sharp text rendering"]
        func count()->Int {Int((overlay.value as? String ?? "").components(separatedBy:";")[0].replacingOccurrences(of:"plot:",with:"")) ?? 0}
        XCTAssertTrue(NSPredicate {_ ,_ in count()>1200 && (app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",0")}.evaluate(with:nil) || XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in count()>1200 && (app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",0")},object:overlay)],timeout:45) == .completed,"HD graph must contain newly computed ROM points")
        XCTAssertTrue((overlay.value as? String ?? "").contains(";axes:44"),"Axes and ticks must use the vector geometry layer")
        let a=XCTAttachment(screenshot:app.screenshot());a.name="HD sin(x squared)";a.lifetime = .keepAlways;add(a)
        let before=pixels(app)
        for key in ["RIGHT","UP","F3","RIGHT","LEFT","UP","DOWN","ESC","F2","ESC","F5","ESC"] {
            tap(app,key)
            XCTAssertGreaterThan(count(),1200,"HD plot must survive \(key) navigation")
            if key=="F3" {
                XCTAssertTrue((overlay.value as? String ?? "").contains(";cursorVector:1;plotNumbers:1;"),"Trace cursor and plot number must use vector artwork: \(overlay.value as? String ?? "missing")")
                let protected=Int((overlay.value as? String ?? "").components(separatedBy:"cursorProtected:").last ?? "0") ?? 0
                XCTAssertGreaterThan(protected,0,"Trace cursor must be protected from Sharp Text replacement")
                if let raw=pixels(app) {
                    var pgm=Data("P5\n160 100\n255\n".utf8);pgm.append(raw)
                    let native=XCTAttachment(data:pgm,uniformTypeIdentifier:"public.data");native.name="Native Trace LCD.pgm";native.lifetime = .keepAlways;add(native)
                }
            }
            if key=="F3" || key=="F2" || key=="F5" {
                let shot=XCTAttachment(screenshot:app.screenshot());shot.name="HD navigation \(key)";shot.lifetime = .keepAlways;add(shot)
            }
        }
        tap(app,"F1")
        XCTAssertGreaterThan(count(),1200,"HD curves must remain behind the native popup menu")
        tap(app,"ESC")
        XCTAssertGreaterThan(count(),1200,"Closing a menu must restore the HD graph")
        tap(app,"Configuration Settings")
        let toggle=app.switches["HD Plotting (Prototype)"]
        for _ in 0..<8 {if toggle.isHittable {break};app.swipeUp()}
        XCTAssertEqual(toggle.value as? String,"1")
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()
        XCTAssertEqual(toggle.value as? String,"0","HD switch must turn off")
        tap(app,"Done")
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in count()==0},object:overlay)],timeout:10),.completed,"Toggle must restore original graph")
        XCTAssertEqual(before?.subdata(in:2560..<14880),pixels(app)?.subdata(in:2560..<14880),"HD plotting must preserve original graph pixels")
        let b=XCTAttachment(screenshot:app.screenshot());b.name="Original sin(x squared)";b.lifetime = .keepAlways;add(b)
    }

    func testHDParametric() { exerciseHDMode(2,minimum:1200) }
    func testHDPolar() { exerciseHDMode(3,minimum:1200) }
    func testHDSequence() { exerciseHDMode(4,minimum:10) }
    func testHD3DWireframe() { exerciseHDMode(5,minimum:23000) }
    func testHD3DClippedMesh() { exerciseHDMode(5,minimum:1000,clipped:true) }
    func testHDDifferentialEquations() { exerciseHDMode(6,minimum:2000) }
    private func exerciseHDMode(_ mode:Int,minimum:Int,clipped:Bool=false) {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-hd-plot","--ui-test-plot-mode",String(mode),"--ui-test-sharp-text"]
        if clipped {app.launchArguments.append("--ui-test-clipped-3d")}
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:25))
        tap(app,"DIAMOND");tap(app,"F3")
        let overlay=app.otherElements["Sharp text rendering"]
        func count()->Int {Int((overlay.value as? String ?? "").components(separatedBy:";")[0].replacingOccurrences(of:"plot:",with:"")) ?? 0}
        let finished=NSPredicate {_,_ in count()>minimum && (app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",0")}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:finished,object:overlay)],timeout:60),.completed,"Mode \(mode) must finish in HD")
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="HD graph mode \(mode)";shot.lifetime = .keepAlways;add(shot)
        let navigationKeys=clipped ? ["F3","RIGHT","LEFT","ESC","F5","ESC"] : ["RIGHT","LEFT","F3","RIGHT","ESC","F5","ESC"]
        var tracing=false
        for key in navigationKeys {
            if key=="F3" {tracing=true};if key=="ESC" {tracing=false}
            tap(app,key)
            let navigationResult=XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in count()>minimum},object:overlay)],timeout:5)
            XCTAssertEqual(navigationResult,.completed,"Mode \(mode) lost HD on \(key)")
            if mode==3 && (key=="F3" || key=="RIGHT") {
                if tracing {XCTAssertTrue((overlay.value as? String ?? "").contains(";theta:1;readoutsComplete:1;thetaCursor:0"),"Theta and all Trace digits need complete sharp text cells: \(overlay.value as? String ?? "missing")")}
                let trace=XCTAttachment(screenshot:app.screenshot());trace.name="Polar readouts \(key)";trace.lifetime = .keepAlways;add(trace)
            }
        }
        tap(app,"Configuration Settings")
        let toggle=app.switches["HD Plotting (Prototype)"]
        for _ in 0..<8 {if toggle.isHittable {break};app.swipeUp()}
        toggle.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap();tap(app,"Done")
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_,_ in count()==0},object:overlay)],timeout:10),.completed)
    }

    func testHDTraceHeldArrow() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-hd-plot","--ui-test-sharp-text"]
        app.launch();tap(app,"DIAMOND");tap(app,"F3")
        let overlay=app.otherElements["Sharp text rendering"]
        func active()->Bool {(Int((overlay.value as? String ?? "").components(separatedBy:";")[0].replacingOccurrences(of:"plot:",with:"")) ?? 0)>1200}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in active() && (app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",0")},object:overlay)],timeout:45),.completed)
        tap(app,"F3")
        let before=pixels(app)
        app.buttons["RIGHT"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:1.5)
        XCTAssertTrue(active(),"Holding Trace RIGHT must retain HD curves")
        XCTAssertNotEqual(before?.subdata(in:13280..<14880),pixels(app)?.subdata(in:13280..<14880),"Held Trace must update its coordinate readouts")
        XCTAssertTrue((overlay.value as? String ?? "").contains(";cursorVector:1;"),"Released Trace cursor must remain vector based")
        let screenshot=XCTAttachment(screenshot:app.screenshot());screenshot.name="Trace after held RIGHT";screenshot.lifetime = .keepAlways;add(screenshot)
        tap(app,"ESC")
        app.buttons["LEFT"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:1.5)
        XCTAssertTrue(active(),"Holding free graph LEFT must retain HD curves")
        XCTAssertTrue((overlay.value as? String ?? "").contains(";cursorVector:1;"),"Free graph cursor must remain vector based")
        tap(app,"DIAMOND");tap(app,"F1")
        app.buttons["DOWN"].coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).press(forDuration:1)
        XCTAssertTrue((overlay.value as? String ?? "").hasPrefix("plot:0;"),"Trace overlay must not cover Y= scrolling")
    }

    func testHDPlotProgressesWithTwoFunctions() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-hd-plot","--ui-test-hd-plot-multiple"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:20))
        // Observe a partial frame reliably; the separate test covers turbo.
        tap(app,"Configuration Settings")
        let turbo=app.switches["Overclock when Busy"]
        if turbo.value as? String=="1" {turbo.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.5)).tap()}
        XCTAssertEqual(turbo.value as? String,"0")
        tap(app,"Done")
        tap(app,"DIAMOND");tap(app,"F3")
        let overlay=app.otherElements["Sharp text rendering"]
        func count()->Int {Int((overlay.value as? String ?? "").components(separatedBy:";")[0].replacingOccurrences(of:"plot:",with:"")) ?? 0}
        func busy()->Bool {(app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",1")}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in count()>10 && count()<2500 && busy()},object:overlay)],timeout:30),.completed,"Partial curves must already be HD while the calculator is busy")
        let partial=XCTAttachment(screenshot:app.screenshot());partial.name="Progressive HD plotting";partial.lifetime = .keepAlways;add(partial)
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in count()>2500 && !busy()},object:overlay)],timeout:60),.completed,"Both selected functions must retain their HD samples")
        let final=XCTAttachment(screenshot:app.screenshot());final.name="Two completed HD functions";final.lifetime = .keepAlways;add(final)
    }

    func testCompactYPlotRows() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"DIAMOND");tap(app,"F1")
        let overlay=app.otherElements["Sharp text rendering"]
        for step in 0..<4 {
            let value=overlay.value as? String ?? ""
            XCTAssertTrue(value.contains("body:1") && value.contains("yeditor:1"),"Y= compact layout must remain active at plot step \(step): \(value)")
            let a=XCTAttachment(screenshot:app.screenshot());a.name="Compact plot row \(step)";a.lifetime = .keepAlways;add(a)
            tap(app,"UP")
        }
        for _ in 0..<4 {tap(app,"DOWN")}
        XCTAssertTrue((overlay.value as? String ?? "").contains("yeditor:1"))
    }

    func testCompactYFillsAvailableHeight() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        tap(app,"HOME");tap(app,"DIAMOND");tap(app,"F1")
        let overlay=app.otherElements["Sharp text rendering"]
        func checkRows(_ name:String) {
            let value=overlay.value as? String ?? ""
            let rows=value.split(separator:",").first(where:{$0.hasPrefix("extra:")}).flatMap {Int($0.dropFirst(6))} ?? 0
            XCTAssertGreaterThanOrEqual(rows,3,"Compact Y= must draw additional real rows: \(value)")
            let a=XCTAttachment(screenshot:app.screenshot());a.name=name;a.lifetime = .keepAlways;add(a)
        }
        checkRows("Compact Y extra rows from top")
        for _ in 0..<10 {tap(app,"DOWN")}
        checkRows("Compact Y extra rows after scrolling")
        let before=pixels(app)?.subdata(in:2560..<13280)
        tap(app,"Configuration Settings")
        let compact=app.switches["Compact Layout (Prototype)"]
        for _ in 0..<5 {if compact.isHittable {break};app.swipeUp()}
        compact.tap();tap(app,"Done")
        XCTAssertEqual(before,pixels(app)?.subdata(in:2560..<13280),"Expanded capture must keep original Y= pixels")
        let b=XCTAttachment(screenshot:app.screenshot());b.name="Original Y rows after scrolling";b.lifetime = .keepAlways;add(b)
    }

    func testCompactHistorySurvivesTooManyArguments() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-compact-layout","--ui-test-lcm-error"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        let overlay=app.otherElements["Sharp text rendering"]
        let error=NSPredicate { _,_ in (overlay.value as? String ?? "").contains("lcmError:1") }
        expectation(for:error,evaluatedWith:overlay);waitForExpectations(timeout:30)
        let dialog=XCTAttachment(screenshot:app.screenshot());dialog.name="LCM too many arguments";dialog.lifetime = .keepAlways;add(dialog)
        tap(app,"ESC")
        func historyReady()->Bool {(overlay.value as? String ?? "").contains("history:1")}
        let history=NSPredicate { _,_ in historyReady() }
        expectation(for:history,evaluatedWith:overlay);waitForExpectations(timeout:10)
        XCTAssertTrue((overlay.value as? String ?? "").contains("foreignChildren:0"),"Status/entry glyphs must not enlarge a retained mathematical expression")
        let restored=XCTAttachment(screenshot:app.screenshot());restored.name="Compact history restored after LCM error";restored.lifetime = .keepAlways;add(restored)
        tap(app,"CLEAR");tap(app,"UP")
        expectation(for:history,evaluatedWith:overlay);waitForExpectations(timeout:10)
        let selected=XCTAttachment(screenshot:app.screenshot());selected.name="Recovered compact history selection";selected.lifetime = .keepAlways;add(selected)
    }

    func testSharpDisabledLabels() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-disabled"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","K2","PLUS","K3","ENTER","UP"] { tap(app,key) }
        let overlay=app.otherElements["Sharp text rendering"]
        let shaded=NSPredicate { _,_ in
            let value=overlay.value as? String ?? ""
            let suffix=(value.components(separatedBy:"shaded:").last ?? "0").components(separatedBy:";").first ?? "0"
            return (Int(suffix) ?? 0)>=15
        }
        expectation(for:shaded,evaluatedWith:overlay);waitForExpectations(timeout:10)
        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="Sharp disabled Home toolbar";shot.lifetime = .keepAlways;add(shot)
        tap(app,"ESC");tap(app,"F1")
        let disabledMenu=NSPredicate { _,_ in
            let value=overlay.value as? String ?? ""
            return value.contains("Open") && value.contains("New")
        }
        expectation(for:disabledMenu,evaluatedWith:overlay);waitForExpectations(timeout:10)
        let menu=XCTAttachment(screenshot:app.screenshot());menu.name="Sharp disabled Tools entries";menu.lifetime = .keepAlways;add(menu)
    }

    func testSharpCursorBlink() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-cursor"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","K1",")"] { tap(app,key) }
        let overlay=app.otherElements["Sharp text rendering"]
        for position in ["end","middle"] {
            if position=="middle" { tap(app,"LEFT") }
            var on=false,off=false,saved=false
            for _ in 0..<20 {
                let value=overlay.value as? String ?? ""
                XCTAssertTrue(value.contains("entry:2"),"Adjacent input glyph lost during cursor blink: \(value)")
                if value.contains("cursor:255") {
                    on=true
                    if !saved {
                        let shot=XCTAttachment(screenshot:app.screenshot());shot.name="HD thin cursor \(position)";shot.lifetime = .keepAlways;add(shot);saved=true
                    }
                }
                if value.contains("cursor:0") { off=true }
                Thread.sleep(forTimeInterval:0.12)
            }
            XCTAssertTrue(on && off,"Both calculator cursor blink phases must be observed")
        }
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

    func testCatalogHelpPreservesClippedRow() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-sharp-text","--ui-test-catalog-help"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout:15))
        for key in ["HOME","CLEAR","CATALOG"] { tap(app,key) }
        let overlay=app.otherElements["Sharp text rendering"]
        func waitFor(_ value: String) {
            expectation(for: NSPredicate { _,_ in (overlay.value as? String ?? "").contains(value) }, evaluatedWith: overlay)
            waitForExpectations(timeout: 10)
        }
        waitFor("catalogFull:4")
        let before=pixels(app)
        tap(app,"F2")
        waitFor("catalogFull:4")
        if let before, let after=pixels(app) {
            XCTAssertEqual(Array(before[26*160..<94*160]),Array(after[26*160..<94*160]),"F2 stays in the already selected Built-in list")
        } else { XCTFail("Missing Catalog LCD pixels") }
        for _ in 0..<3 {
            tap(app,"F1")
            waitFor("catalogBottom:4")
            let help=XCTAttachment(screenshot:app.screenshot());help.name="Sharp clipped Catalog row under Help";help.lifetime = .keepAlways;add(help)
            tap(app,"ESC")
            waitFor("catalogFull:4")
        }
        let restored=XCTAttachment(screenshot:app.screenshot());restored.name="Complete sharp Catalog row restored";restored.lifetime = .keepAlways;add(restored)
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
            slider.coordinate(withNormalizedOffset: CGVector(dx: current / 250, dy: 0.5))
                .press(forDuration: 0.1, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: high ? 1.15 : -0.15, dy: 0.5)))
        }
        app.buttons["HOME"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: 1)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(requests(), "1", "Holding and releasing a key must produce only one haptic request")
        openHaptics()
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "30 ms")
        endpoint(false)
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "Disabled")
        tap(app, "Done")
        XCTAssertEqual(requests(), "1", "Settings buttons must not trigger calculator haptics")
        tap(app, "CLEAR")
        XCTAssertEqual(requests(), "1", "Disabled haptics must not request a vibration")
        openHaptics()
        endpoint(true)
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "250 ms")
        tap(app, "Done")
        app.terminate()
        app.launchArguments = ["--ui-test"]
        app.launch()
        XCTAssertTrue(app.images["Calculator display"].waitForExistence(timeout: 15))
        waitForCalculator()
        tap(app, "HOME")
        XCTAssertEqual(requests(), "1")
        openHaptics()
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "250 ms")
        tap(app, "Restore Defaults")
        XCTAssertEqual(app.staticTexts["Haptic duration value"].label, "30 ms")
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

// Slider persistence uses a separate settings domain from the normal app.
extension Graph89UITests {
    func testGraphCursorSpeedSetting() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session"]
        app.launch();tap(app,"Configuration Settings")
        let slider=app.sliders["Cursor Scroll Speed"]
        XCTAssertTrue(slider.waitForExistence(timeout:10))
        XCTAssertEqual(slider.value as? String,"3x")
        slider.adjust(toNormalizedSliderPosition:1)
        XCTAssertEqual(slider.value as? String,"10x")
        tap(app,"Done");app.terminate()
        app.launchArguments=["--ui-test"];app.launch();tap(app,"Configuration Settings")
        XCTAssertEqual(slider.value as? String,"10x")
        slider.adjust(toNormalizedSliderPosition:0)
        XCTAssertEqual(slider.value as? String,"1x")
        tap(app,"Done")
    }
}

extension Graph89UITests {
    func testHDIntersectionPrompts() {
        let app=XCUIApplication()
        app.launchArguments=["--ui-test","--reset-settings","--fresh-session","--ui-test-hd-plot","--ui-test-sharp-text","--ui-test-hd-plot-multiple"]
        app.launch();tap(app,"DIAMOND");tap(app,"F3")
        let overlay=app.otherElements["Sharp text rendering"]
        func active()->Bool {(Int((overlay.value as? String ?? "").components(separatedBy:";")[0].replacingOccurrences(of:"plot:",with:"")) ?? 0)>2400}
        XCTAssertEqual(XCTWaiter.wait(for:[XCTNSPredicateExpectation(predicate:NSPredicate {_ ,_ in active() && (app.staticTexts["Engine status"].value as? String ?? "").hasSuffix(",0")},object:overlay)],timeout:45),.completed)
        func capture(_ name:String) {
            XCTAssertTrue(active(),"Intersection must preserve both HD curves")
            let shot=XCTAttachment(screenshot:app.screenshot());shot.name=name;shot.lifetime = .keepAlways;add(shot)
        }
        tap(app,"F5");tap(app,"K5");capture("1st Curve")
        tap(app,"ENTER");capture("2nd Curve")
        tap(app,"ENTER");capture("Lower Bound")
        for _ in 0..<8 {tap(app,"LEFT")};tap(app,"ENTER");capture("Upper Bound")
        for _ in 0..<20 {tap(app,"RIGHT")};tap(app,"ENTER");Thread.sleep(forTimeInterval:1);capture("Intersection")
        tap(app,"ESC");capture("Intersection closed")
    }
}
