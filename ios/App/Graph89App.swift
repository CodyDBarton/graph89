import UIKit
import CoreHaptics
import Darwin

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Calculator", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        window.rootViewController = CalculatorController()
        window.makeKeyAndVisible()
        self.window = window
    }
    func sceneWillResignActive(_ scene: UIScene) {
        (window?.rootViewController as? CalculatorController)?.pause()
    }
    func sceneDidBecomeActive(_ scene: UIScene) {
        (window?.rootViewController as? CalculatorController)?.resume()
    }
    func sceneDidEnterBackground(_ scene: UIScene) {
        (window?.rootViewController as? CalculatorController)?.save()
    }
    func sceneDidDisconnect(_ scene: UIScene) {
        (window?.rootViewController as? CalculatorController)?.save()
    }
}

final class CalculatorController: UIViewController {
    private let settingsButton = CornerSettingsButton(frame: .zero)
    private let settings = CalculatorSettings()
    private let keyHaptics = CalculatorHaptics()
    private let engine = CalculatorEngine()
    private var framePending = false
    private var cameraPending = false
    private let engineMonitor = UILabel()
    private let hapticMonitor = UILabel()
    private let lcd = UIImageView()
    private let hdDisplay = SharpTextView()
    private let lcdBezel = UIView()
    private let keyboard = CalculatorKeyboard()
    private var displayLink: CADisplayLink?
    private var running = false
    private var ready = false
    private var stateURL: URL!
    private var lastPixels = Data()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
        view.clipsToBounds = true
        lcd.backgroundColor = UIColor(white: 210.0 / 255, alpha: 1)
        lcd.contentMode = .scaleToFill
        lcd.layer.magnificationFilter = .nearest
        lcd.layer.minificationFilter = .nearest
        lcdBezel.backgroundColor = UIColor(white: 0.2, alpha: 1)
        lcdBezel.addSubview(lcd)
        hdDisplay.isUserInteractionEnabled = false
        lcdBezel.addSubview(hdDisplay)
        hdDisplay.enabled = settings.sharpText
        hdDisplay.compact = settings.compactLayout
        hdDisplay.requestCamera = { [weak self] in
            guard let self,self.running,self.ready,self.settings.hdPlot,self.settings.metal3D,!self.cameraPending else {return}
            if ProcessInfo.processInfo.arguments.contains("--ui-test-30hz-camera") {return}
            self.cameraPending=true
            self.engine.camera { [weak self] sample in
                guard let self else {return}
                self.cameraPending=false
                guard self.running,self.settings.hdPlot,self.settings.metal3D,let sample else {return}
                self.hdDisplay.updateCamera(sample)
            }
        }
        lcd.isAccessibilityElement = true
        lcd.accessibilityLabel = "Calculator display"
        settingsButton.accessibilityLabel = "Configuration Settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        for child in [lcdBezel, keyboard, settingsButton] { view.addSubview(child) }
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            hdDisplay.isAccessibilityElement = true
            hdDisplay.accessibilityIdentifier = "Sharp text rendering"
            hdDisplay.accessibilityLabel = "Sharp text rendering"
            // Expose engine diagnostics only to the UI test runner, without visible text.
            engineMonitor.isAccessibilityElement = true
            engineMonitor.accessibilityIdentifier = "Engine status"
            engineMonitor.accessibilityLabel = "Engine status"
            engineMonitor.textColor = .clear
            view.addSubview(engineMonitor)
            hapticMonitor.isAccessibilityElement = true
            hapticMonitor.accessibilityIdentifier = "Haptic requests"
            hapticMonitor.accessibilityLabel = "Haptic requests"
            hapticMonitor.accessibilityValue = "0"
            hapticMonitor.textColor = .clear
            view.addSubview(hapticMonitor)
        }
        keyboard.accessibilityIdentifier = "Calculator button face"
        keyboard.onKey = { [weak self] key, pressed in
            guard let self else { return }
            if pressed && self.ready { self.keyHaptics.play() }
            self.hapticMonitor.accessibilityValue = String(self.keyHaptics.requests)
            self.setKey(key, pressed: pressed)
        }
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds
        let safeArea = area.inset(by: view.safeAreaInsets)
        let panel = settings.stretchMode.panelFrame(in: area, safeArea: safeArea)
        let screenFraction: CGFloat = (635 * 100 / 160.0) / (1014 + 635 * 100 / 160.0)
        lcdBezel.frame = CGRect(x: panel.minX, y: panel.minY, width: panel.width,
                               height: panel.height * screenFraction)
        lcd.frame = lcdBezel.bounds
        hdDisplay.frame = lcdBezel.bounds
        keyboard.frame = CGRect(x: panel.minX, y: lcdBezel.frame.maxY, width: panel.width,
                                height: panel.height - lcdBezel.frame.height)
        // Nest the badge against the physical corner, independently of the
        // panel and safe-area rectangle. Insets provide a conservative estimate of
        // corner curvature; the visible badge is also the complete touch target.
        let insets = view.safeAreaInsets
        let cornerRadius = max(insets.top, insets.bottom, insets.left, insets.right)
        let buttonRadius = CornerSettingsButton.diameter / 2
        let cornerOffset = max(buttonRadius + 3, cornerRadius - (cornerRadius - buttonRadius) / sqrt(2))
        // On iPad, mouse clicks in the top strip can be intercepted before the
        // app receives them, even with the status bar hidden. Keep the entire
        // visible badge below that strip. Touch target and artwork share a center.
        let topOffset = traitCollection.userInterfaceIdiom == .pad
            ? max(cornerOffset, max(20, insets.top) + buttonRadius) : cornerOffset
        settingsButton.frame = CGRect(x: area.maxX - cornerOffset - buttonRadius,
                                      y: area.minY + topOffset - buttonRadius,
                                      width: CornerSettingsButton.diameter, height: CornerSettingsButton.diameter)
        engineMonitor.frame = CGRect(x: area.minX, y: area.minY, width: 1, height: 1)
        hapticMonitor.frame = CGRect(x: area.minX + 2, y: area.minY, width: 1, height: 1)
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "Graph89", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        (presentedViewController ?? self).present(alert, animated: true)
    }

    private func start() {
        guard let os = Bundle.main.url(forResource: "TI89Titanium_OS", withExtension: "89u") else {
            showError("Titanium OS file is missing from this build.")
            return
        }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            stateURL = folder.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-test") ? "ui-test.state" : "titanium.state")
            let image = folder.appendingPathComponent("titanium.img")
            engine.configure(cpuPercent: settings.cpuPercent, overclock: settings.overclock, sharpText: settings.sharpText, hdPlot: settings.hdPlot, metal3D: settings.metal3D, cursorSpeed: settings.graphCursorSpeed)
            let arguments = ProcessInfo.processInfo.arguments
            engine.start(os: os.path, image: image.path, state: stateURL.path,
                         fresh: arguments.contains("--fresh-session"),
                         benchmark: arguments.contains("--ui-test") && arguments.contains("--ui-test-benchmark")) { [weak self] error in
                guard let self else { return }
                guard error == 0 else {
                    self.showError("Calculator startup failed (\(error)).")
                    return
                }
                self.ready = true
                self.engine.fontTemplates { [weak self] data in
                    guard let self else { return }
                    self.hdDisplay.configure(data)
                    if ProcessInfo.processInfo.arguments.contains("--ui-test-lcm-error"),let folder=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first {try? data.write(to:folder.appendingPathComponent("lcm-fonts.bin"))}
                    if !self.lastPixels.isEmpty { self.hdDisplay.update(self.lastPixels) }
                }
                let link = CADisplayLink(target: self, selector: #selector(self.tick))
                link.preferredFramesPerSecond = 30
                link.add(to: .main, forMode: .common)
                self.displayLink = link
                if UIApplication.shared.applicationState == .active { self.resume() }
                if arguments.contains("--start-asleep") {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.engine.sleepForTest() }
                }
                if arguments.contains("--smoke-test") { self.runSmokeTest() }
            }
        } catch {
            showError("Unable to prepare calculator storage.")
        }
    }

    private func setKey(_ key: Int, pressed: Bool) {
        guard ready else { return }
        hdDisplay.cameraKey(key,pressed:pressed)
        engine.setKey(key, pressed: pressed)
    }

    @objc private func openSettings() {
        let controller = ConfigurationController(settings: settings)
        controller.onChange = { [weak self] in
            guard let self else { return }
            self.engine.configure(cpuPercent: self.settings.cpuPercent, overclock: self.settings.overclock, sharpText: self.settings.sharpText, hdPlot: self.settings.hdPlot, metal3D: self.settings.metal3D, cursorSpeed: self.settings.graphCursorSpeed)
            self.keyHaptics.configure(duration: self.settings.hapticDuration)
            self.hdDisplay.enabled = self.settings.sharpText
            self.hdDisplay.compact = self.settings.compactLayout
            self.view.setNeedsLayout()
        }
        let navigation = UINavigationController(rootViewController: controller)
        navigation.modalPresentationStyle = .formSheet
        present(navigation, animated: true)
    }

    @objc private func tick() {
        guard running && ready && !framePending else { return }
        framePending = true
        engine.frame { [weak self] frame in
            guard let self else { return }
            self.framePending = false
            guard self.running else { return }
            let snapshotStart=CACurrentMediaTime()
            self.hdDisplay.updateMesh(frame.mesh,background:frame.plotBackground,bounds:frame.plot)
            let meshEnd=CACurrentMediaTime()
            self.hdDisplay.updatePlot(frame.plot,background:frame.plotBackground,decorations:frame.plotDecorations)
            let plotEnd=CACurrentMediaTime()
            self.refreshScreen(frame.pixels, retained: frame.retained)
            let textEnd=CACurrentMediaTime()
            self.hdDisplay.snapshotMillis=(textEnd-snapshotStart)*1000
            self.hdDisplay.snapshotPhases="meshMs:\((meshEnd-snapshotStart)*1000);plotMs:\((plotEnd-meshEnd)*1000);textMs:\((textEnd-plotEnd)*1000)"
            if ProcessInfo.processInfo.arguments.contains("--ui-test") {
                self.engineMonitor.accessibilityValue = "\(frame.normalIterations),\(frame.turboIterations),\(frame.busy ? 1 : 0),\(frame.on ? 1:0)"
            }
        }
    }

    private func refreshScreen(_ data: Data, retained: [Int32]) {
        if ProcessInfo.processInfo.arguments.contains("--ui-test-lcm-error"),let folder=FileManager.default.urls(for:.cachesDirectory,in:.userDomainMask).first {
            var pgm=Data("P5\n160 100\n255\n".utf8);pgm.append(data);try? pgm.write(to:folder.appendingPathComponent("lcm-current.pgm"))
            let packets=stride(from:0,to:retained.count,by:12).map {Array(retained[$0..<$0+12])}
            if let json=try? JSONSerialization.data(withJSONObject:packets) {try? json.write(to:folder.appendingPathComponent("lcm-current.cells.json"))}
        }
        let recognitionStart=CACurrentMediaTime()
        hdDisplay.update(data, retained: retained)
        hdDisplay.recognitionMillis=(CACurrentMediaTime()-recognitionStart)*1000
        guard data != lastPixels else { return }
        lastPixels = data
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: 160, height: 100, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: 160, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        let imageStart=CACurrentMediaTime()
        lcd.image = UIImage(cgImage: image)
        hdDisplay.imageMillis=(CACurrentMediaTime()-imageStart)*1000
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            lcd.accessibilityValue = data.base64EncodedString()
        }
    }

    func pause() {
        running = false
        engine.pause()
        keyHaptics.pause()
        keyboard.releaseAll()

    }
    func resume() {
        guard ready else { return }
        running = true
        engine.resume()
        keyHaptics.resume(duration: settings.hapticDuration)
        tick()
    }
    func save() {
        guard ready, let stateURL else { return }
        let temporary = stateURL.appendingPathExtension("tmp")
        if engine.save(to: temporary.path) == 0 {
            if Darwin.rename(temporary.path, stateURL.path) != 0 {
                showError("Unable to save this session.")
            }
        } else {
            showError("Unable to save this session.")
        }
    }

    private func runSmokeTest() {
        let keys = [82, 56, 10, 65, 10, 76]
        for (index, key) in keys.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.25) { [weak self] in
                self?.keyboard.onKey?(key, true)
                self?.keyboard.onKey?(key, false)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            self?.save()
        }
    }
}

// TiEmu has global mutable state. Every native call, including key events,
// framebuffer reads and state saving, belongs to this one serial queue.
final class CalculatorEngine {
    struct Frame {
        let pixels: Data
        let retained: [Int32]
        let plot: [Float]
        let plotBackground: Data
        let plotDecorations:[Float]
        let mesh:MeshFrame?
        let on: Bool
        let busy: Bool
        let normalIterations: UInt64
        let turboIterations: UInt64
    }
    private let queue = DispatchQueue(label: "com.codybarton.graph89.engine", qos: .userInitiated)
    private var ready = false
    private var running = false
    private var generation: UInt64 = 0
    private var cpuPercent = 100
    private var overclock = true
    private var heldKeys = Set<Int>()
    private var keyInput = CalculatorKeyInput()
    private var wakeReleaseAt: CFTimeInterval = 0
    private var normalIterations: UInt64 = 0
    private var meshGeneration = -1
    private var turboIterations: UInt64 = 0

    func start(os: String, image: String, state: String, fresh: Bool, benchmark: Bool,
               completion: @escaping (Int32) -> Void) {
        queue.async {
            let error = graph89_start(os, image)
            if error == 0 {
                let restored = !fresh && FileManager.default.fileExists(atPath: state) && graph89_restore(state) == 0
                if !restored { for _ in 0..<600 { graph89_run(50_000) } }
                self.ready = true
                if ProcessInfo.processInfo.arguments.contains("--ui-test-lcm-error") {
                    for key:Int32 in [82,56] {
                        graph89_key(key,1);graph89_run(400_000);graph89_key(key,0);graph89_run(400_000)
                    }
                    graph89_type_text("1/sin(x^2)\n(12345+67890)^2\nsqrt(2)\nlcm(20,30,40)\n")
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-test-history") {
                    for key:Int32 in [82,56] {
                        graph89_key(key,1);graph89_run(400_000)
                        graph89_key(key,0);graph89_run(400_000)
                    }
                    graph89_type_text((1...12).map {"\($0)+1\n"}.joined())
                }
                if ProcessInfo.processInfo.arguments.contains("--ui-test-hd-plot") {
                    let args = ProcessInfo.processInfo.arguments
                    let modeIndex = args.firstIndex(of:"--ui-test-plot-mode")
                    let mode = modeIndex.flatMap { $0+1<args.count ? Int(args[$0+1]):nil } ?? 1
                    if (2...6).contains(mode) {
                        for key:Int32 in [82,56] {
                            graph89_key(key,1);graph89_run(400_000)
                            graph89_key(key,0);graph89_run(400_000)
                        }
                        let names=["FUNCTION","PARAMETRIC","POLAR","SEQUENCE","3D","DIFF EQUATIONS"]
                        graph89_type_text("setMode(\"Graph\",\"\(names[mode-1])\")\n")
                        graph89_run(30_000_000)
                    }
                    if mode==5 && args.contains("--ui-test-rotation") {
                        graph89_type_text("setGraph(\"Style\",\"Wire Frame\")\nsetGraph(\"Axes\",\"Axes\")\nsetGraph(\"Labels\",\"On\")\n")
                        graph89_run(60_000_000)
                    }
                    for key:Int32 in [82,6,49,56] {
                        graph89_key(key,1);graph89_run(400_000)
                        graph89_key(key,0);graph89_run(400_000)
                    }
                    let equations=["sin(x^2)","cos(t)\nsin(t)","2*cos(3*q)","n^2","sin(x)*cos(y)","y1\n1"]
                    let equation=args.contains("--ui-test-clipped-3d") ? "100*sin(x)*cos(y)" : args.contains("--ui-test-hd-plot-multiple") ? "sin(x^2)\ncos(x)" : equations[min(6,max(1,mode))-1]
                    // TI theta is calculator byte 136, not UTF-8.
                    let bytes=equation.utf8.map { CChar(bitPattern: mode==3 && $0==113 ? 136:$0) }+[0]
                    bytes.withUnsafeBufferPointer { graph89_type_text($0.baseAddress!) }
                    for _ in 0..<400 {graph89_run(50_000)}
                    graph89_key(76,1);graph89_run(400_000)
                    graph89_key(76,0);graph89_run(400_000)
                }
                if benchmark {
                    for key: Int32 in [82, 56] {
                        graph89_key(key, 1); graph89_run(400_000)
                        graph89_key(key, 0); graph89_run(400_000)
                    }
                    let limit = ProcessInfo.processInfo.arguments.contains("--ui-test-stress") ? 100 : 8
                    graph89_type_text("nint(sin(x^2),x,0,\(limit))\n")
                }
            }
            DispatchQueue.main.async { completion(error) }
        }
    }
    func configure(cpuPercent: Int, overclock: Bool, sharpText: Bool, hdPlot: Bool, metal3D: Bool, cursorSpeed: Int) {
        queue.async {
            graph89_retained_text_enable(sharpText ? 1 : 0)
            graph89_hd_plot_enable(hdPlot ? 1 : 0,8)
            self.metal3D = metal3D
            graph89_graph_cursor_speed(Int32(cursorSpeed))
            self.cpuPercent = cpuPercent
            self.overclock = overclock
            self.restart()
        }
    }
    func setKey(_ key: Int, pressed: Bool) {
        queue.async {
            guard self.ready else { return }
            if pressed && graph89_screen_is_on() == 0 {
                graph89_wake()
                // AMS resumes its application asynchronously after power-on.
                // Keep the waking key down long enough to reach that app.
                self.wakeReleaseAt = CACurrentMediaTime() + 0.16
            }
            self.keyInput.enqueue(key, pressed: pressed)
            self.deliverKeyEvents()
            self.restart()
        }
    }
    func pause() {
        queue.async {
            self.running = false
            self.generation += 1
            for key in self.heldKeys { graph89_key(Int32(key), 0) }
            self.heldKeys.removeAll()
            self.keyInput.reset()
            self.wakeReleaseAt = 0
        }
    }
    func resume() {
        queue.async {
            guard self.ready else { return }
            graph89_wake()
            self.running = true
            self.restart()
        }
    }
    private func deliverKeyEvents() {
        guard heldKeys.isEmpty || CACurrentMediaTime() >= wakeReleaseAt else { return }
        for event in keyInput.takeReady() {
            if event.pressed { heldKeys.insert(event.key) }
            else { heldKeys.remove(event.key) }
            graph89_key(Int32(event.key), event.pressed ? 1 : 0)
        }
    }
    private func runWithKeyScanning(_ instructions: Int32) {
        var remaining = Int(instructions)
        while remaining > 0 {
            deliverKeyEvents()
            let count = keyInput.runLimit(remaining)
            graph89_run(Int32(count))
            keyInput.advance(count)
            remaining -= count
        }
        deliverKeyEvents()
    }
    private func restart() {
        generation += 1
        guard ready && running else { return }
        schedule(after: 0, generation: generation)
    }
    private func schedule(after delay: Double, generation token: UInt64) {
        let work: () -> Void = { [weak self] in self?.run(generation: token) }
        if delay == 0 {
            queue.async(execute: work)
        } else {
            queue.asyncAfter(deadline: .now() + delay, execute: work)
        }
    }
    private func run(generation token: UInt64) {
        guard running && ready && generation == token else { return }
        let turbo = overclock && heldKeys.isEmpty && graph89_is_busy() != 0
        if turbo {
            // No intentional delay or batch-count limit. Short quanta only return
            // to the queue to service pending ON, settings, lifecycle and LCD reads.
            let deadline = CACurrentMediaTime() + 0.010
            repeat {
                runWithKeyScanning(10_000)
                turboIterations += 10_000
            } while CACurrentMediaTime() < deadline && graph89_is_busy() != 0
        } else {
            let count = graph89_batch_size(Int32(cpuPercent))
            runWithKeyScanning(count)
            normalIterations += UInt64(count)
        }
        let stillTurbo = overclock && heldKeys.isEmpty && graph89_is_busy() != 0
        let normalDelay = Double(Int(30 / (Double(cpuPercent) / 100))) / 1000
        let drainInput = keyInput.hasPending && (heldKeys.isEmpty || CACurrentMediaTime() >= wakeReleaseAt)
        schedule(after: stillTurbo || drainInput ? 0 : normalDelay, generation: token)
    }
    private var metal3D = true
    private let cameraQueue=DispatchQueue(label:"com.codybarton.graph89.camera",qos:.userInteractive)
    func camera(completion:@escaping ([Double]?)->Void) {
        cameraQueue.async {
            // This getter takes the native plot lock, but copies no LCD, text,
            // geometry, or masks and never advances the emulated CPU.
            var meta=[Double](repeating:0,count:64)
            let available=graph89_copy_camera(&meta)
            if available != 0 {
                let offset=CACurrentMediaTime()-graph89_rotation_time()
                meta[25]+=offset;meta[27]+=offset
            }
            DispatchQueue.main.async {completion(available != 0 ? meta:nil)}
        }
    }
    func frame(completion: @escaping (Frame) -> Void) {
        queue.async {
            var bytes = [UInt8](repeating: 210, count: 160 * 100)
            graph89_copy_screen(&bytes)
            var packets = [Int32](repeating: 0, count: 8192 * 12)
            let count = graph89_copy_retained_text(&bytes, &packets, 8192)
            var plot = [Float](repeating:0,count:65540)
            var plotBackground = [UInt8](repeating:0,count:16000)
            let plotCount=graph89_copy_hd_plot(&bytes,&plot,65540,&plotBackground)
            var decorations=[Float](repeating:0,count:65536)
            let decorationCount=plotCount>0 ? graph89_copy_hd_plot_decorations(&decorations,65536):0
            var mesh:MeshFrame?
            if plotCount>0 && self.metal3D {
                var vertices=[Float](repeating:0,count:4096*3),edges=[UInt32](repeating:0,count:32768),meta=[Double](repeating:0,count:64)
                let available=graph89_copy_mesh(&vertices,&edges,&meta,Int32(self.meshGeneration))
                if available != 0 {
                    // CLOCK_MONOTONIC and Core Animation can differ after Mac
                    // sleep. Transfer timestamp ages, never compare epochs.
                    let offset=CACurrentMediaTime()-graph89_rotation_time()
                    meta[25]+=offset;meta[27]+=offset
                    let next=Int(meta[0]),changed=next != self.meshGeneration;self.meshGeneration=next
                    mesh=MeshFrame(meta:meta,vertices:changed ? Array(vertices.prefix(Int(meta[1])*3)):nil,edges:changed ? Array(edges.prefix(Int(meta[2])*2)):nil)
                }
            }
            let frame = Frame(pixels: Data(bytes), retained: Array(packets.prefix(Int(count) * 12)), plot:Array(plot.prefix(Int(plotCount))),plotBackground:Data(plotBackground),plotDecorations:Array(decorations.prefix(Int(decorationCount))),mesh:mesh,on: graph89_screen_is_on() != 0,
                              busy: graph89_is_busy() != 0, normalIterations: self.normalIterations,
                              turboIterations: self.turboIterations)
            DispatchQueue.main.async { completion(frame) }
        }
    }
    func fontTemplates(completion: @escaping (Data) -> Void) {
        queue.async {
            var bytes = [UInt8](repeating: 0, count: 3 * 256 * 12)
            let count = graph89_copy_font_templates(&bytes)
            let data = count == bytes.count ? Data(bytes) : Data()
            DispatchQueue.main.async { completion(data) }
        }
    }
    func save(to path: String) -> Int32 {
        // Complete the snapshot before iOS may suspend the process in background.
        queue.sync { graph89_save(path) }
    }
    func sleepForTest() {
        queue.async {
            graph89_key(7, 1); graph89_run(200_000)
            graph89_key(78, 1); graph89_run(200_000)
            graph89_key(78, 0); graph89_key(7, 0); graph89_run(200_000)
        }
    }
}

final class CalculatorKeyboard: UIView {
    var onKey: ((Int, Bool) -> Void)?
    private var fingers: [UITouch: Int] = [:]
    private var image = UIImage(named: "skin.jpg")
    private let keyMask: Data = {
        guard let url = Bundle.main.url(forResource: "buttonmask", withExtension: "bin") else { return Data() }
        return (try? Data(contentsOf: url)) ?? Data()
    }()
    private struct Key {
        let code: Int
        let name: String
        let center: CGPoint
    }
    private let keys: [Key] = {
        guard let url = Bundle.main.url(forResource: "buttonloaction", withExtension: "location"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(whereSeparator: { $0.isNewline }).compactMap { line in
            let parts = line.split(whereSeparator: { $0.isWhitespace })
            guard parts.count == 5, let code = Int(parts[0]), let x = Double(parts[2]), let y = Double(parts[3]) else { return nil }
            return Key(code: code, name: String(parts[1]), center: CGPoint(x: x, y: y))
        }
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        isOpaque = true
        isAccessibilityElement = false
        accessibilityLabel = "Calculator keyboard"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func draw(_ rect: CGRect) {
        image?.draw(in: bounds)
        if let context = UIGraphicsGetCurrentContext() {
            context.saveGState()
            context.scaleBy(x: bounds.width / 635, y: bounds.height / 1014)
            // Replace the EMU lettering on the key face, following its photographed
            // contour rather than placing a rectangular label over the skin.
            let face = UIBezierPath()
            face.move(to: CGPoint(x: 43, y: 878))
            face.addCurve(to: CGPoint(x: 113, y: 882), controlPoint1: CGPoint(x: 55, y: 874), controlPoint2: CGPoint(x: 92, y: 877))
            face.addCurve(to: CGPoint(x: 122, y: 895), controlPoint1: CGPoint(x: 120, y: 883), controlPoint2: CGPoint(x: 123, y: 887))
            face.addLine(to: CGPoint(x: 122, y: 932))
            face.addCurve(to: CGPoint(x: 105, y: 950), controlPoint1: CGPoint(x: 123, y: 944), controlPoint2: CGPoint(x: 117, y: 950))
            face.addCurve(to: CGPoint(x: 43, y: 907), controlPoint1: CGPoint(x: 80, y: 950), controlPoint2: CGPoint(x: 51, y: 932))
            face.addCurve(to: CGPoint(x: 43, y: 878), controlPoint1: CGPoint(x: 37, y: 893), controlPoint2: CGPoint(x: 37, y: 883))
            face.close()
            context.saveGState()
            face.addClip()
            let colors = [UIColor(white: 0.34, alpha: 1).cgColor,
                          UIColor(white: 0.40, alpha: 1).cgColor,
                          UIColor(white: 0.46, alpha: 1).cgColor] as CFArray
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 0.55, 1]) {
                context.drawLinearGradient(gradient, start: CGPoint(x: 83, y: 877),
                                           end: CGPoint(x: 83, y: 950), options: [])
            }
            context.restoreGState()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let keyFont = UIFont(name: "HelveticaNeue-CondensedBold", size: 24)
                ?? UIFont.systemFont(ofSize: 24, weight: .bold)
            ("ON" as NSString).draw(in: CGRect(x: 49, y: 895, width: 70, height: 32), withAttributes: [
                .font: keyFont, .foregroundColor: UIColor(white: 0.97, alpha: 1),
                .paragraphStyle: paragraph])
            let alternateFont = UIFont(name: "HelveticaNeue-CondensedBold", size: 18)
                ?? UIFont.systemFont(ofSize: 18, weight: .bold)
            ("OFF" as NSString).draw(in: CGRect(x: 61, y: 851, width: 62, height: 25), withAttributes: [
                .font: alternateFont,
                .foregroundColor: UIColor(red: 0.65, green: 0.84, blue: 0.90, alpha: 1),
                .paragraphStyle: paragraph])
            context.restoreGState()
        }
        let active = Set(fingers.values)
        UIColor.systemCyan.withAlphaComponent(0.28).setFill()
        for key in keys where active.contains(key.code) {
            let center = CGPoint(x: key.center.x / 635 * bounds.width, y: key.center.y / 1014 * bounds.height)
            UIBezierPath(ovalIn: CGRect(x: center.x - bounds.width * 0.075, y: center.y - bounds.height * 0.028,
                                       width: bounds.width * 0.15, height: bounds.height * 0.056)).fill()
        }
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        accessibilityElements = keys.map { key in
            let element = CalculatorKeyAccessibility(accessibilityContainer: self)
            element.accessibilityLabel = key.name
            element.accessibilityTraits = .button
            element.accessibilityFrameInContainerSpace = CGRect(x: (key.center.x - 50) / 635 * bounds.width,
                y: (key.center.y - 35) / 1014 * bounds.height, width: 100 / 635 * bounds.width, height: 70 / 1014 * bounds.height)
            element.activate = { [weak self] in
                self?.onKey?(key.code, true)
                self?.onKey?(key.code, false)
            }
            return element
        }
    }
    private func key(at point: CGPoint) -> Int? {
        guard bounds.contains(point), bounds.width > 0, bounds.height > 0, keyMask.count == 318 * 507 else { return nil }
        let x = min(317, max(0, Int(point.x / bounds.width * 318)))
        let y = min(506, max(0, Int(point.y / bounds.height * 507)))
        let code = Int(keyMask[y * 318 + x])
        return code < 85 ? code : nil
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let key = key(at: touch.location(in: self)) {
                if !fingers.values.contains(key) { onKey?(key, true) }
                fingers[touch] = key
            }
        }
        setNeedsDisplay()
    }
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            if let key = fingers.removeValue(forKey: touch), !fingers.values.contains(key) { onKey?(key, false) }
        }
        setNeedsDisplay()
    }
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) { touchesEnded(touches, with: event) }
    func releaseAll() {
        for key in Set(fingers.values) { onKey?(key, false) }
        fingers.removeAll()
        setNeedsDisplay()
    }
}
final class CalculatorKeyAccessibility: UIAccessibilityElement {
    var activate: (() -> Void)?
    override func accessibilityActivate() -> Bool { activate?(); return true }
}


final class CornerSettingsButton: UIButton {
    static let diameter: CGFloat = 44
    private let badge = UIView()
    private let glyph = UIImageView(image: UIImage(systemName: "gearshape", withConfiguration:
        UIImage.SymbolConfiguration(pointSize: 22, weight: .regular)))
    var badgeCenter: CGPoint { CGPoint(x: bounds.midX, y: bounds.midY) }

    override init(frame: CGRect) {
        super.init(frame: frame)
        badge.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        badge.layer.cornerRadius = Self.diameter / 2
        badge.isUserInteractionEnabled = false
        glyph.tintColor = .white
        glyph.contentMode = .scaleAspectFit
        glyph.isUserInteractionEnabled = false
        addSubview(badge)
        addSubview(glyph)
        alpha = 0.5
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        let radius = bounds.width / 2
        let dx = point.x - bounds.midX
        let dy = point.y - bounds.midY
        return dx * dx + dy * dy <= radius * radius
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        badge.frame = bounds
        badge.layer.cornerRadius = bounds.width / 2
        glyph.bounds = CGRect(origin: .zero, size: glyph.image?.size ?? CGSize(width: 11, height: 11))
        glyph.center = badgeCenter
    }
}

enum StretchMode: String, CaseIterable {
    case safeAspect, horizontal, vertical, both, fullAspect, cropAspect

    var title: String {
        switch self {
        case .safeAspect: return "Aspect ratio; no loss"
        case .horizontal: return "Horizontal"
        case .vertical: return "Vertical"
        case .both: return "Horizontal and vertical"
        case .fullAspect: return "Aspect ratio, full"
        case .cropAspect: return "Aspect ratio, crop"
        }
    }
    var detail: String {
        switch self {
        case .safeAspect: return "Default. Keeps the entire calculator visible within the safe display area, without stretching."
        case .horizontal: return "Starts from no loss and stretches to the left and right display edges. Rounded corners may hide content."
        case .vertical: return "Starts from no loss and stretches to the top and bottom display edges. Rounded corners may hide content."
        case .both: return "Stretches to all display edges. Rounded corners may hide content."
        case .fullAspect: return "Keeps proportions and fills one display dimension, ignoring rounded corners. Bars may remain."
        case .cropAspect: return "Keeps proportions and fills both display dimensions. Anything beyond the display is cropped."
        }
    }
    func panelFrame(in bounds: CGRect, safeArea: CGRect) -> CGRect {
        let original = CGSize(width: 635, height: 1014 + 635 * 100 / 160.0)
        func fit(_ area: CGRect, crop: Bool = false) -> CGRect {
            let xScale = area.width / original.width
            let yScale = area.height / original.height
            let scale = crop ? max(xScale, yScale) : min(xScale, yScale)
            let size = CGSize(width: original.width * scale, height: original.height * scale)
            return CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                          width: size.width, height: size.height)
        }
        let noLoss = fit(safeArea)
        switch self {
        case .safeAspect: return noLoss
        case .horizontal: return CGRect(x: bounds.minX, y: noLoss.minY, width: bounds.width, height: noLoss.height)
        case .vertical: return CGRect(x: noLoss.minX, y: bounds.minY, width: noLoss.width, height: bounds.height)
        case .both: return bounds
        case .fullAspect: return fit(bounds)
        case .cropAspect: return fit(bounds, crop: true)
        }
    }
}

final class CalculatorHaptics {
    private(set) var requests = 0
    private var duration = 30
    private var active = false
    private let supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var engineRunning = false
    private var player: CHHapticPatternPlayer?
    private var diagnosticStarted = false
    private var successfulStarts = 0
    private var lastError = ""
    private var lastPatternDuration: TimeInterval = 0
    private var verifiedDurations: [Double] = []

    // One sustained event only: no transient, UIKit click, or system buzz.
    // The event's own duration ends playback; no main-thread stop timer is used.
    static func pattern(milliseconds: Int) throws -> CHHapticPattern? {
        guard milliseconds > 0 else { return nil }
        let desired = Double(min(250, milliseconds)) / 1000
        func make(_ eventDuration: TimeInterval) throws -> CHHapticPattern {
            let event = CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 1),
                CHHapticEventParameter(parameterID: .attackTime, value: 0),
                CHHapticEventParameter(parameterID: .releaseTime, value: 0),
                CHHapticEventParameter(parameterID: .sustained, value: 1)
            ], relativeTime: 0, duration: eventDuration)
            return try CHHapticPattern(events: [event], parameters: [])
        }
        let direct = try make(desired)
        if abs(direct.duration - desired) < 0.000001 { return direct }
        // Core Haptics subtracts an internal continuous-event offset on some
        // runtimes (20 ms on the tested SDK). Probe the runtime rather than
        // hardcoding a platform assumption; sub-offset pulses otherwise have
        // a zero-length playback pattern despite successful start calls.
        let reference = try make(0.1)
        let offset = max(0, 0.1 - reference.duration)
        let corrected = try make(desired + offset)
        guard abs(corrected.duration - desired) < 0.000001 else {
            throw NSError(domain: "Graph89Haptics", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Cannot construct selected pulse duration"])
        }
        return corrected
    }

    private func record(_ message: String) {
        guard ProcessInfo.processInfo.arguments.contains("--haptic-diagnostics") || ProcessInfo.processInfo.arguments.contains("--haptic-log") else { return }
        let values: [String: Any] = ["message": message, "supported": supported,
            "duration": duration, "active": active, "requests": requests,
            "successfulStarts": successfulStarts, "error": lastError,
            "patternMilliseconds": lastPatternDuration * 1000,
            "engineRunning": engineRunning, "engineMuted": engine?.isMutedForHaptics ?? false,
            "playerMuted": player?.isMuted ?? false, "verifiedMilliseconds": verifiedDurations]
        if let folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("haptic-diagnostics.json"), options: .atomic)
        }
    }
    func configure(duration: Int) {
        self.duration = min(250, max(0, duration))
        if duration == 0 {
            try? player?.cancel()
            player = nil
        } else if active { _ = prepare() }
    }
    private func prepare() -> CHHapticEngine? {
        guard supported, active, duration > 0 else { return nil }
        do {
            if engine == nil {
                let created = try CHHapticEngine()
                created.playsHapticsOnly = true
                created.isMutedForHaptics = false
                created.isAutoShutdownEnabled = false
                created.stoppedHandler = { [weak self, weak created] reason in
                    DispatchQueue.main.async {
                        guard let self, let created, self.engine === created else { return }
                        self.engineRunning = false
                        self.player = nil
                        self.record("engine stopped: \(reason.rawValue)")
                    }
                }
                created.resetHandler = { [weak self, weak created] in
                    DispatchQueue.main.async {
                        guard let self, let created, self.engine === created else { return }
                        self.engineRunning = false
                        self.player = nil
                        _ = self.prepare()
                    }
                }
                engine = created
            }
            guard let engine else { return nil }
            if !engineRunning {
                try engine.start()
                engineRunning = true
            }
            return engine
        } catch {
            engineRunning = false
            lastError = String(describing: error)
            record("engine start failed")
            return nil
        }
    }
    func resume(duration: Int) {
        active = true
        configure(duration: duration)
        if ProcessInfo.processInfo.arguments.contains("--haptic-log") {
            do {
                verifiedDurations = try (1...250).map { try Self.pattern(milliseconds: $0)!.duration * 1000 }
                record("all slider durations validated on this device")
            } catch { lastError = String(describing: error); record("device duration validation failed") }
        }
        if ProcessInfo.processInfo.arguments.contains("--haptic-diagnostics"), !diagnosticStarted {
            diagnosticStarted = true
            for delay in [0.5, 0.8, 1.1, 1.6] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.play() }
            }
        }
    }
    func pause() {
        active = false
        player = nil
        engineRunning = false
        // Detach first: a delayed stop callback from this engine must not
        // invalidate the replacement created on the next foreground session.
        let stopped = engine
        engine = nil
        stopped?.stop(completionHandler: nil)
    }
    func play() {
        guard active, duration > 0 else { return }
        requests += 1
        guard let engine = prepare() else { return }
        do {
            guard let pattern = try Self.pattern(milliseconds: duration) else { return }
            let fresh = try engine.makePlayer(with: pattern)
            fresh.isMuted = false
            // Never stop/restart a shared player at the same timestamp.
            // Each inexpensive player runs its finite pulse to completion.
            try fresh.start(atTime: CHHapticTimeImmediate)
            player = fresh
            lastPatternDuration = pattern.duration
            successfulStarts += 1
            lastError = ""
            record("timed pulse started")
        } catch {
            lastError = String(describing: error)
            record("timed pulse failed")
        }
    }
}

final class CalculatorSettings {
    private let defaults: UserDefaults
    var graphCursorSpeed: Int {
        didSet { defaults.set(graphCursorSpeed, forKey: "graphCursorSpeed") }
    }
    var cpuPercent: Int {
        didSet { defaults.set(cpuPercent, forKey: "cpuPercent") }
    }
    var compactLayout: Bool {
        didSet { defaults.set(compactLayout, forKey: "compactLayout") }
    }
    var metal3D: Bool {
        didSet { defaults.set(metal3D, forKey:"metal3D") }
    }
    var hdPlot: Bool {
        didSet { defaults.set(hdPlot, forKey:"hdPlot") }
    }
    var sharpText: Bool {
        didSet { defaults.set(sharpText, forKey: "sharpText") }
    }
    var overclock: Bool {
        didSet { defaults.set(overclock, forKey: "overclockWhenBusy") }
    }
    var hapticDuration: Int {
        didSet { defaults.set(hapticDuration, forKey: "hapticDuration") }
    }
    var stretchMode: StretchMode {
        didSet { defaults.set(stretchMode.rawValue, forKey: "stretchMode") }
    }
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-test")
        defaults = testing ? UserDefaults(suiteName: "com.codybarton.graph89.settings-tests")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-settings") {
            defaults.removePersistentDomain(forName: "com.codybarton.graph89.settings-tests")
        }
        defaults.register(defaults: ["metal3D": true, "graphCursorSpeed": 3, "cpuPercent": 100, "overclockWhenBusy": true, "hapticDuration": 30])
        graphCursorSpeed = min(10, max(1, defaults.integer(forKey: "graphCursorSpeed")))
        hdPlot = defaults.bool(forKey:"hdPlot")
        metal3D = defaults.bool(forKey:"metal3D")
        sharpText = defaults.bool(forKey: "sharpText")
        compactLayout = defaults.bool(forKey: "compactLayout") && sharpText
        cpuPercent = min(250, max(30, defaults.integer(forKey: "cpuPercent")))
        overclock = defaults.bool(forKey: "overclockWhenBusy")
        hapticDuration = min(250, max(0, defaults.integer(forKey: "hapticDuration")))
        stretchMode = StretchMode(rawValue: defaults.string(forKey: "stretchMode") ?? "") ?? .safeAspect
        let args=ProcessInfo.processInfo.arguments
        if testing,let index=args.firstIndex(of:"--ui-test-cpu-percent"),index+1<args.count,let percent=Int(args[index+1]) {cpuPercent=min(250,max(30,percent))}
        if testing && ProcessInfo.processInfo.arguments.contains("--ui-test-hd-plot") { hdPlot = true }
        if testing && ProcessInfo.processInfo.arguments.contains("--ui-test-sharp-text") { sharpText = true }
        if testing && ProcessInfo.processInfo.arguments.contains("--ui-test-compact-layout") { sharpText = true;compactLayout = true }
    }
}

final class ConfigurationController: UIViewController {
    private let settings: CalculatorSettings
    var onChange: (() -> Void)?
    private let cursorSlider = UISlider()
    private let cursorValue = UILabel()
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private let turboSwitch = UISwitch()
    private let sharpSwitch = UISwitch()
    private let compactSwitch = UISwitch()
    private let plotSwitch = UISwitch()
    private let metalSwitch = UISwitch()
    private let stretchButton = UIButton(type: .system)
    private let stretchDetail = UILabel()
    private let hapticSlider = UISlider()
    private let hapticValue = UILabel()

    init(settings: CalculatorSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Configuration Settings"
        view.backgroundColor = .systemGroupedBackground
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(done))
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])
        let titleLabel = UILabel()
        titleLabel.text = "CPU Speed"
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        valueLabel.textAlignment = .right
        valueLabel.accessibilityIdentifier = "CPU speed value"
        let speedRow = UIStackView(arrangedSubviews: [titleLabel, valueLabel])
        speedRow.distribution = .fillEqually
        stack.addArrangedSubview(speedRow)
        slider.minimumValue = 30
        slider.maximumValue = 250
        slider.accessibilityLabel = "CPU Speed"
        slider.addTarget(self, action: #selector(speedChanged), for: .valueChanged)
        stack.addArrangedSubview(slider)
        let limits = UIStackView()
        limits.distribution = .fillEqually
        for (index, text) in ["30%", "250%"].enumerated() {
            let label = UILabel()
            label.text = text
            label.font = .preferredFont(forTextStyle: .caption1)
            label.textColor = .secondaryLabel
            label.textAlignment = index == 0 ? .left : .right
            limits.addArrangedSubview(label)
        }
        stack.addArrangedSubview(limits)
        let cursorLabel = UILabel()
        cursorLabel.text = "Cursor Scroll Speed"
        cursorLabel.font = .preferredFont(forTextStyle: .headline)
        cursorValue.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        cursorValue.textAlignment = .right
        let cursorRow = UIStackView(arrangedSubviews: [cursorLabel, cursorValue])
        cursorRow.distribution = .fillEqually
        stack.addArrangedSubview(cursorRow)
        cursorSlider.minimumValue = 1
        cursorSlider.maximumValue = 10
        cursorSlider.accessibilityLabel = "Cursor Scroll Speed"
        cursorSlider.addTarget(self, action: #selector(cursorChanged), for: .valueChanged)
        stack.addArrangedSubview(cursorSlider)
        let cursorDetail = UILabel()
        cursorDetail.text = "1–10× held-arrow movement throughout the calculator. Default: 3×. Starts after 0.35 seconds of real time. Single taps are unchanged."
        cursorDetail.font = .preferredFont(forTextStyle: .subheadline)
        cursorDetail.textColor = .secondaryLabel
        cursorDetail.numberOfLines = 0
        stack.addArrangedSubview(cursorDetail)
        let turboLabel = UILabel()
        turboLabel.text = "Overclock when Busy"
        turboLabel.font = .preferredFont(forTextStyle: .headline)
        turboLabel.numberOfLines = 0
        turboSwitch.accessibilityLabel = "Overclock when Busy"
        turboSwitch.addTarget(self, action: #selector(turboChanged), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [turboLabel, turboSwitch])
        row.spacing = 12
        stack.addArrangedSubview(row)
        let detail = UILabel()
        detail.text = "Runs busy calculations as fast as the device allows, regardless of CPU Speed. Normal pacing resumes when the calculation finishes. Changes take effect immediately."
        detail.font = .preferredFont(forTextStyle: .subheadline)
        detail.textColor = .secondaryLabel
        detail.numberOfLines = 0
        stack.addArrangedSubview(detail)
        let stretchLabel = UILabel()
        stretchLabel.text = "Stretch mode"
        stretchLabel.font = .preferredFont(forTextStyle: .headline)
        stack.addArrangedSubview(stretchLabel)
        stretchButton.accessibilityLabel = "Stretch mode"
        stretchButton.titleLabel?.font = .preferredFont(forTextStyle: .body)
        stretchButton.titleLabel?.numberOfLines = 0
        stretchButton.contentHorizontalAlignment = .leading
        stretchButton.showsMenuAsPrimaryAction = true
        stretchButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(stretchButton)
        stretchDetail.font = .preferredFont(forTextStyle: .subheadline)
        stretchDetail.textColor = .secondaryLabel
        stretchDetail.numberOfLines = 0
        stack.addArrangedSubview(stretchDetail)
        let hapticLabel = UILabel()
        hapticLabel.text = "Haptic Feedback"
        hapticLabel.font = .preferredFont(forTextStyle: .headline)
        hapticValue.font = .monospacedDigitSystemFont(ofSize: 20, weight: .semibold)
        hapticValue.textAlignment = .right
        hapticValue.accessibilityIdentifier = "Haptic duration value"
        let hapticRow = UIStackView(arrangedSubviews: [hapticLabel, hapticValue])
        hapticRow.distribution = .fillEqually
        stack.addArrangedSubview(hapticRow)
        hapticSlider.minimumValue = 0
        hapticSlider.maximumValue = 250
        hapticSlider.accessibilityLabel = "Haptic Feedback"
        hapticSlider.addTarget(self, action: #selector(hapticChanged), for: .valueChanged)
        stack.addArrangedSubview(hapticSlider)
        let hapticDetail = UILabel()
        hapticDetail.text = "One vibration per key press. Duration: 0–250 ms; 0 disables feedback. Default: 30 ms. Requires haptic hardware."
        hapticDetail.font = .preferredFont(forTextStyle: .subheadline)
        hapticDetail.textColor = .secondaryLabel
        hapticDetail.numberOfLines = 0
        stack.addArrangedSubview(hapticDetail)
        let sharpLabel = UILabel()
        sharpLabel.text = "Sharp Text (Prototype)"
        sharpLabel.font = .preferredFont(forTextStyle: .headline)
        sharpLabel.numberOfLines = 0
        sharpSwitch.accessibilityLabel = "Sharp Text (Prototype)"
        sharpSwitch.addTarget(self, action: #selector(sharpChanged), for: .valueChanged)
        let sharpRow = UIStackView(arrangedSubviews: [sharpLabel, sharpSwitch])
        sharpRow.spacing = 12
        stack.addArrangedSubview(sharpRow)
        let sharpDetail = UILabel()
        sharpDetail.text = "Sharper text and mathematical symbols. Turn off to show the original calculator display."
        sharpDetail.font = .preferredFont(forTextStyle: .subheadline)
        sharpDetail.textColor = .secondaryLabel
        sharpDetail.numberOfLines = 0
        stack.addArrangedSubview(sharpDetail)
        let compactLabel = UILabel()
        compactLabel.text = "Compact Layout (Prototype)"
        compactLabel.font = .preferredFont(forTextStyle: .headline)
        compactLabel.numberOfLines = 0
        compactSwitch.accessibilityLabel = "Compact Layout (Prototype)"
        compactSwitch.addTarget(self, action: #selector(compactChanged), for: .valueChanged)
        let compactRow = UIStackView(arrangedSubviews: [compactLabel, compactSwitch])
        compactRow.spacing = 12
        stack.addArrangedSubview(compactRow)
        let compactDetail = UILabel()
        compactDetail.text = "Show more input and equations at once in Home and Y=. Uses Sharp Text. Turn off to restore the original spacing."
        compactDetail.font = .preferredFont(forTextStyle: .subheadline)
        compactDetail.textColor = .secondaryLabel
        compactDetail.numberOfLines = 0
        stack.addArrangedSubview(compactDetail)
        let plotLabel = UILabel()
        plotLabel.text = "HD Plotting (Prototype)"
        plotLabel.font = .preferredFont(forTextStyle:.headline)
        plotSwitch.accessibilityLabel = "HD Plotting (Prototype)"
        plotSwitch.addTarget(self,action:#selector(plotChanged),for:.valueChanged)
        let plotRow=UIStackView(arrangedSubviews:[plotLabel,plotSwitch]);plotRow.spacing=12
        stack.addArrangedSubview(plotRow)
        let plotDetail=UILabel()
        plotDetail.text="Sharper Function, Parametric, Polar, Sequence, 3D wireframe and differential-equation graphs. Uses additional calculator evaluations where appropriate. Use F4 ReGraph after enabling. Turn off for the original graph. Other 3D styles retain the original display."
        plotDetail.font = .preferredFont(forTextStyle:.subheadline)
        plotDetail.textColor = .secondaryLabel;plotDetail.numberOfLines=0
        stack.addArrangedSubview(plotDetail)
        let metalLabel=UILabel()
        metalLabel.text="Metal 3D Rotation"
        metalLabel.font = .preferredFont(forTextStyle:.headline)
        metalLabel.numberOfLines=0
        metalSwitch.accessibilityLabel="Metal 3D Rotation"
        metalSwitch.addTarget(self,action:#selector(metalChanged),for:.valueChanged)
        let metalRow=UIStackView(arrangedSubviews:[metalLabel,metalSwitch]);metalRow.spacing=12
        stack.addArrangedSubview(metalRow)
        let metalDetail=UILabel()
        metalDetail.text="Use the GPU for smooth HD 3D wireframe rotation. Turn off to compare with the previous HD renderer. Requires HD Plotting."
        metalDetail.font = .preferredFont(forTextStyle:.subheadline)
        metalDetail.textColor = .secondaryLabel;metalDetail.numberOfLines=0
        stack.addArrangedSubview(metalDetail)
        let reset = UIButton(type: .system)
        reset.setTitle("Restore Defaults", for: .normal)
        reset.addTarget(self, action: #selector(restoreDefaults), for: .touchUpInside)
        stack.addArrangedSubview(reset)
        updateControls()
    }
    private func updateControls() {
        cursorSlider.value = Float(settings.graphCursorSpeed)
        cursorValue.text = "\(settings.graphCursorSpeed)x"
        cursorSlider.accessibilityValue = cursorValue.text
        slider.value = Float(settings.cpuPercent)
        slider.accessibilityValue = "\(settings.cpuPercent)%"
        valueLabel.text = "\(settings.cpuPercent)%"
        turboSwitch.isOn = settings.overclock
        sharpSwitch.isOn = settings.sharpText
        compactSwitch.isOn = settings.compactLayout
        plotSwitch.isOn = settings.hdPlot
        metalSwitch.isOn = settings.metal3D
        hapticSlider.value = Float(settings.hapticDuration)
        let hapticText = settings.hapticDuration == 0 ? "Disabled" : "\(settings.hapticDuration) ms"
        hapticValue.text = hapticText
        hapticSlider.accessibilityValue = hapticText
        stretchButton.setTitle(settings.stretchMode.title, for: .normal)
        stretchButton.accessibilityValue = settings.stretchMode.title
        stretchDetail.text = settings.stretchMode.detail
        stretchButton.menu = UIMenu(title: "Stretch mode", options: .singleSelection, children: StretchMode.allCases.map { mode in
            UIAction(title: mode.title, state: settings.stretchMode == mode ? .on : .off) { [weak self] _ in
                guard let self else { return }
                self.settings.stretchMode = mode
                self.updateControls()
                self.onChange?()
            }
        })
    }
    @objc private func cursorChanged() {
        settings.graphCursorSpeed = Int(cursorSlider.value.rounded())
        updateControls()
        onChange?()
    }
    @objc private func speedChanged() {
        settings.cpuPercent = Int(slider.value.rounded())
        updateControls()
        onChange?()
    }
    @objc private func turboChanged() {
        settings.overclock = turboSwitch.isOn
        onChange?()
    }
    @objc private func hapticChanged() {
        settings.hapticDuration = Int(hapticSlider.value.rounded())
        updateControls()
        onChange?()
    }
    @objc private func sharpChanged() {
        settings.sharpText = sharpSwitch.isOn
        if !settings.sharpText { settings.compactLayout = false }
        updateControls()
        onChange?()
    }
    @objc private func compactChanged() {
        settings.compactLayout = compactSwitch.isOn
        if settings.compactLayout { settings.sharpText = true }
        updateControls()
        onChange?()
    }
    @objc private func metalChanged() {
        settings.metal3D = metalSwitch.isOn
        onChange?()
    }
    @objc private func plotChanged() {
        settings.hdPlot = plotSwitch.isOn
        onChange?()
    }
    @objc private func restoreDefaults() {
        settings.hdPlot = false
        settings.metal3D = true
        settings.compactLayout = false
        settings.sharpText = false
        settings.graphCursorSpeed = 3
        settings.cpuPercent = 100
        settings.overclock = true
        settings.stretchMode = .safeAspect
        settings.hapticDuration = 30
        updateControls()
        onChange?()
    }
    @objc private func done() { dismiss(animated: true) }
}
