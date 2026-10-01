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
        for child in [titleLabel, statusLabel, lcdBezel, keyboard] { view.addSubview(child) }
        keyboard.onKey = { [weak self] key, pressed in
            self?.setKey(key, pressed: pressed)
        }
        DispatchQueue.main.async { [weak self] in self?.start() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let area = view.bounds.inset(by: view.safeAreaInsets).insetBy(dx: 14, dy: 8)
        titleLabel.frame = CGRect(x: area.minX, y: area.minY, width: area.width, height: 28)
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
            let error = graph89_start(os.path, image.path)
            guard error == 0 else {
                statusLabel.text = "Calculator startup failed (\(error))."
                return
            }
            ready = true
            var restored = false
            if !ProcessInfo.processInfo.arguments.contains("--fresh-session") && FileManager.default.fileExists(atPath: stateURL.path) {
                restored = graph89_restore(stateURL.path) == 0
            }
            if !restored { for _ in 0..<600 { graph89_run(50_000) } }
            statusLabel.text = restored ? "OS 3.10 · Session restored" : "OS 3.10 · TI-89 Titanium"
            refreshScreen()
            let link = CADisplayLink(target: self, selector: #selector(tick))
            link.preferredFramesPerSecond = 30
            link.add(to: .main, forMode: .common)
            displayLink = link
            resume()
            if ProcessInfo.processInfo.arguments.contains("--start-asleep") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    graph89_key(7, 1)
                    graph89_run(200_000)
                    graph89_key(78, 1)
                    graph89_run(200_000)
                    graph89_key(78, 0)
                    graph89_key(7, 0)
                    graph89_run(200_000)
                    self?.refreshScreen()
                }
            }
            if ProcessInfo.processInfo.arguments.contains("--smoke-test") {
                runSmokeTest()
            }
        } catch {
            statusLabel.text = "Unable to prepare calculator storage."
        }
    }

    private func setKey(_ key: Int, pressed: Bool) {
        guard ready else { return }
        releases.removeValue(forKey: key)?.cancel()
        if pressed {
            if graph89_screen_is_on() == 0 { graph89_wake() }
            if pressedAt[key] == nil {
                pressedAt[key] = CACurrentMediaTime()
                graph89_key(Int32(key), 1)
            }
        } else if let began = pressedAt[key] {
            let delay = max(0, 0.16 - (CACurrentMediaTime() - began))
            let release = DispatchWorkItem { [weak self] in
                graph89_key(Int32(key), 0)
                self?.pressedAt.removeValue(forKey: key)
                self?.releases.removeValue(forKey: key)
            }
            releases[key] = release
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: release)
        }
    }

    @objc private func tick() {
        guard running && ready else { return }
        graph89_run(100_000)
        refreshScreen()
        if graph89_screen_is_on() == 0 { statusLabel.text = "Calculator asleep · Tap a key to wake" }
    }

    private func refreshScreen() {
        var bytes = [UInt8](repeating: 210, count: 160 * 100)
        graph89_copy_screen(&bytes)
        let data = Data(bytes)
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
        if graph89_screen_is_on() != 0 { statusLabel.text = "OS 3.10 · TI-89 Titanium" }
    }

    func pause() {
        running = false
        keyboard.releaseAll()
        for task in releases.values { task.cancel() }
        releases.removeAll()
        for key in pressedAt.keys { graph89_key(Int32(key), 0) }
        pressedAt.removeAll()
    }
    func resume() {
        guard ready else { return }
        graph89_wake()
        running = true
        refreshScreen()
    }
    func save() {
        guard ready, let stateURL else { return }
        let temporary = stateURL.appendingPathExtension("tmp")
        if graph89_save(temporary.path) == 0 {
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
