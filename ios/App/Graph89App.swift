import UIKit
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
    private let titleLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let settings = CalculatorSettings()
    private let engine = CalculatorEngine()
    private var framePending = false
    private let statusLabel = UILabel()
    private let lcd = UIImageView()
    private let lcdBezel = UIView()
    private let keyboard = CalculatorKeyboard()
    private var displayLink: CADisplayLink?
    private var running = false
    private var ready = false
    private var stateURL: URL!
    private var lastPixels = Data()
    private var pressedAt: [Int: CFTimeInterval] = [:]
    private var releases: [Int: DispatchWorkItem] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.08, green: 0.09, blue: 0.10, alpha: 1)
        titleLabel.text = "Graph 89 · Titanium"
        titleLabel.font = .systemFont(ofSize: 19, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center
        statusLabel.text = "Starting calculator…"
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .lightGray
        statusLabel.textAlignment = .center
        lcd.backgroundColor = UIColor(white: 210.0 / 255, alpha: 1)
        lcd.contentMode = .scaleToFill
        lcd.layer.magnificationFilter = .nearest
        lcd.layer.minificationFilter = .nearest
        lcdBezel.backgroundColor = UIColor(white: 0.2, alpha: 1)
        lcdBezel.addSubview(lcd)
        lcd.isAccessibilityElement = true
        lcd.accessibilityLabel = "Calculator display"
        settingsButton.setImage(UIImage(systemName: "gearshape"), for: .normal)
        settingsButton.tintColor = .white
        settingsButton.accessibilityLabel = "Configuration Settings"
        settingsButton.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        statusLabel.accessibilityIdentifier = "Engine status"
        for child in [titleLabel, statusLabel, lcdBezel, keyboard, settingsButton] { view.addSubview(child) }
        keyboard.onKey = { [weak self] key, pressed in
            self?.setKey(key, pressed: pressed)
        }
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 14, dy: 8)
        titleLabel.frame = CGRect(x: area.minX + 44, y: area.minY, width: max(1, area.width - 88), height: 28)
        titleLabel.adjustsFontSizeToFitWidth = true
        settingsButton.frame = CGRect(x: area.maxX - 44, y: area.minY - 8, width: 44, height: 44)
        statusLabel.frame = CGRect(x: area.minX, y: area.maxY - 22, width: area.width, height: 22)
        let availableHeight = max(1, area.height - 70)
        if area.width > area.height {
            let width = min((area.width - 28) / 2, availableHeight / (1014.0 / 635))
            let total = width * 2 + 28
            let x = area.midX - total / 2
            lcdBezel.frame = CGRect(x: x, y: area.midY - width * 0.625 / 2, width: width, height: (width - 12) * 0.625 + 12)
            keyboard.frame = CGRect(x: x + width + 28, y: area.minY + 40, width: width, height: width * 1014 / 635)
        } else {
            let width = min(area.width, 560, (availableHeight - 16.5) / (0.625 + 1014.0 / 635))
            let x = area.midX - width / 2
            lcdBezel.frame = CGRect(x: x, y: area.minY + 40, width: width, height: (width - 12) * 0.625 + 12)
            keyboard.frame = CGRect(x: x, y: lcdBezel.frame.maxY + 12, width: width, height: width * 1014 / 635)
        }
        lcd.frame = lcdBezel.bounds.insetBy(dx: 6, dy: 6)
    }

    private func start() {
        guard let os = Bundle.main.url(forResource: "TI89Titanium_OS", withExtension: "89u") else {
            statusLabel.text = "Titanium OS file is missing from this build."
            return
        }
        do {
            let folder = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            stateURL = folder.appendingPathComponent(ProcessInfo.processInfo.arguments.contains("--ui-test") ? "ui-test.state" : "titanium.state")
            let image = folder.appendingPathComponent("titanium.img")
            engine.configure(cpuPercent: settings.cpuPercent, overclock: settings.overclock)
            let arguments = ProcessInfo.processInfo.arguments
            engine.start(os: os.path, image: image.path, state: stateURL.path,
                         fresh: arguments.contains("--fresh-session"),
                         benchmark: arguments.contains("--ui-test") && arguments.contains("--ui-test-benchmark")) { [weak self] error in
                guard let self else { return }
                guard error == 0 else {
                    self.statusLabel.text = "Calculator startup failed (\(error))."
                    return
                }
                self.ready = true
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
            statusLabel.text = "Unable to prepare calculator storage."
        }
    }

    private func setKey(_ key: Int, pressed: Bool) {
        guard ready else { return }
        releases.removeValue(forKey: key)?.cancel()
        if pressed {
            if pressedAt[key] == nil {
                pressedAt[key] = CACurrentMediaTime()
                engine.setKey(key, pressed: true)
            }
        } else if let began = pressedAt[key] {
            // Preserve enough emulated scanning time at the slider's slower settings.
            let factor = Double(settings.cpuPercent) / 100
            let minimumHold = max(0.03, 0.16 / (factor * factor))
            let delay = max(0, minimumHold - (CACurrentMediaTime() - began))
            let release = DispatchWorkItem { [weak self] in
                self?.engine.setKey(key, pressed: false)
                self?.pressedAt.removeValue(forKey: key)
                self?.releases.removeValue(forKey: key)
            }
            releases[key] = release
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: release)
        }
    }

    @objc private func openSettings() {
        let controller = ConfigurationController(settings: settings)
        controller.onChange = { [weak self] in
            guard let self else { return }
            self.engine.configure(cpuPercent: self.settings.cpuPercent, overclock: self.settings.overclock)
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
            self.refreshScreen(frame.pixels)
            self.statusLabel.text = frame.on ? "OS 3.10 · TI-89 Titanium" : "Calculator asleep · Tap a key to wake"
            if ProcessInfo.processInfo.arguments.contains("--ui-test") {
                self.statusLabel.accessibilityValue = "\(frame.normalIterations),\(frame.turboIterations),\(frame.busy ? 1 : 0)"
            }
        }
    }

    private func refreshScreen(_ data: Data) {
        guard data != lastPixels else { return }
        lastPixels = data
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(width: 160, height: 100, bitsPerComponent: 8, bitsPerPixel: 8,
                                  bytesPerRow: 160, space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [],
                                  provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return }
        lcd.image = UIImage(cgImage: image)
        if ProcessInfo.processInfo.arguments.contains("--ui-test") {
            lcd.accessibilityValue = data.base64EncodedString()
        }
    }

    func pause() {
        running = false
        engine.pause()
        keyboard.releaseAll()
        for task in releases.values { task.cancel() }
        releases.removeAll()
        for key in pressedAt.keys { engine.setKey(key, pressed: false) }
        pressedAt.removeAll()
    }
    func resume() {
        guard ready else { return }
        running = true
        engine.resume()
        tick()
    }
    func save() {
        guard ready, let stateURL else { return }
        let temporary = stateURL.appendingPathExtension("tmp")
        if engine.save(to: temporary.path) == 0 {
            if Darwin.rename(temporary.path, stateURL.path) != 0 {
                statusLabel.text = "Unable to save this session."
            }
        } else {
            statusLabel.text = "Unable to save this session."
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
    private var normalIterations: UInt64 = 0
    private var turboIterations: UInt64 = 0

    func start(os: String, image: String, state: String, fresh: Bool, benchmark: Bool,
               completion: @escaping (Int32) -> Void) {
        queue.async {
            let error = graph89_start(os, image)
            if error == 0 {
                let restored = !fresh && FileManager.default.fileExists(atPath: state) && graph89_restore(state) == 0
                if !restored { for _ in 0..<600 { graph89_run(50_000) } }
                self.ready = true
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
    func configure(cpuPercent: Int, overclock: Bool) {
        queue.async {
            self.cpuPercent = cpuPercent
            self.overclock = overclock
            self.restart()
        }
    }
    func setKey(_ key: Int, pressed: Bool) {
        queue.async {
            guard self.ready else { return }
            if pressed {
                graph89_wake()
                self.heldKeys.insert(key)
            } else {
                self.heldKeys.remove(key)
            }
            graph89_key(Int32(key), pressed ? 1 : 0)
            self.restart()
        }
    }
    func pause() {
        queue.async {
            self.running = false
            self.generation += 1
            for key in self.heldKeys { graph89_key(Int32(key), 0) }
            self.heldKeys.removeAll()
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
                graph89_run(10_000)
                turboIterations += 10_000
            } while CACurrentMediaTime() < deadline && graph89_is_busy() != 0
        } else {
            let count = graph89_batch_size(Int32(cpuPercent))
            graph89_run(count)
            normalIterations += UInt64(count)
        }
        let stillTurbo = overclock && heldKeys.isEmpty && graph89_is_busy() != 0
        let normalDelay = Double(Int(30 / (Double(cpuPercent) / 100))) / 1000
        schedule(after: stillTurbo ? 0 : normalDelay, generation: token)
    }
    func frame(completion: @escaping (Frame) -> Void) {
        queue.async {
            var bytes = [UInt8](repeating: 210, count: 160 * 100)
            graph89_copy_screen(&bytes)
            let frame = Frame(pixels: Data(bytes), on: graph89_screen_is_on() != 0,
                              busy: graph89_is_busy() != 0, normalIterations: self.normalIterations,
                              turboIterations: self.turboIterations)
            DispatchQueue.main.async { completion(frame) }
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
            UIColor(white: 0.40, alpha: 1).setFill()
            UIBezierPath(roundedRect: CGRect(x: 43, y: 891, width: 86, height: 43), cornerRadius: 10).fill()
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            ("ON" as NSString).draw(in: CGRect(x: 43, y: 896, width: 86, height: 36), withAttributes: [
                .font: UIFont.systemFont(ofSize: 27, weight: .bold), .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph])
            ("OFF" as NSString).draw(in: CGRect(x: 43, y: 851, width: 86, height: 27), withAttributes: [
                .font: UIFont.systemFont(ofSize: 18, weight: .bold),
                .foregroundColor: UIColor(red: 0.35, green: 0.79, blue: 1, alpha: 1),
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
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { self?.onKey?(key.code, false) }
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


final class CalculatorSettings {
    private let defaults: UserDefaults
    var cpuPercent: Int {
        didSet { defaults.set(cpuPercent, forKey: "cpuPercent") }
    }
    var overclock: Bool {
        didSet { defaults.set(overclock, forKey: "overclockWhenBusy") }
    }
    init() {
        let testing = ProcessInfo.processInfo.arguments.contains("--ui-test")
        defaults = testing ? UserDefaults(suiteName: "com.codybarton.graph89.settings-tests")! : .standard
        if testing && ProcessInfo.processInfo.arguments.contains("--reset-settings") {
            defaults.removePersistentDomain(forName: "com.codybarton.graph89.settings-tests")
        }
        defaults.register(defaults: ["cpuPercent": 100, "overclockWhenBusy": true])
        cpuPercent = min(250, max(30, defaults.integer(forKey: "cpuPercent")))
        overclock = defaults.bool(forKey: "overclockWhenBusy")
    }
}

final class ConfigurationController: UIViewController {
    private let settings: CalculatorSettings
    var onChange: (() -> Void)?
    private let slider = UISlider()
    private let valueLabel = UILabel()
    private let turboSwitch = UISwitch()

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
        let reset = UIButton(type: .system)
        reset.setTitle("Restore Defaults", for: .normal)
        reset.addTarget(self, action: #selector(restoreDefaults), for: .touchUpInside)
        stack.addArrangedSubview(reset)
        updateControls()
    }
    private func updateControls() {
        slider.value = Float(settings.cpuPercent)
        slider.accessibilityValue = "\(settings.cpuPercent)%"
        valueLabel.text = "\(settings.cpuPercent)%"
        turboSwitch.isOn = settings.overclock
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
    @objc private func restoreDefaults() {
        settings.cpuPercent = 100
        settings.overclock = true
        updateControls()
        onChange?()
    }
    @objc private func done() { dismiss(animated: true) }
}
