import UIKit
import SpriteKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        CrashReporter.install()
        Log.write("app launched, version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] ?? "?") build \(Bundle.main.infoDictionary?["CFBundleVersion"] ?? "?")")
        AudioManager.setUpSession()
        Fonts.register()

        let w = UIWindow(frame: UIScreen.main.bounds)
        w.backgroundColor = .black
        w.rootViewController = GameViewController()
        w.makeKeyAndVisible()
        window = w
        Log.write("window shown")
        return true
    }
}

final class GameViewController: UIViewController {
    private let skView = SKView()
    // Fills the screen sides with a blurred, enlarged copy of the game
    // so the game itself is never stretched or cut off.
    private let backdrop = UIImageView()
    private let blur = UIVisualEffectView(effect: UIBlurEffect(style: .dark))
    private var backdropTimer: Timer?

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .black
        view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        backdrop.contentMode = .scaleAspectFill
        backdrop.clipsToBounds = true
        view.addSubview(backdrop)
        view.addSubview(blur)
        backdropTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.refreshBackdrop()
        }
        skView.ignoresSiblingOrder = false
        skView.isMultipleTouchEnabled = false
        skView.preferredFramesPerSecond = 60
        skView.backgroundColor = .black
        view.addSubview(skView)
        let scene = GameScene(size: GameScene.viewSize)
        skView.presentScene(scene)
    }

    // Keep the game's 700:500 shape and center it (like the Android version).
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let b = view.bounds
        let aspect = GameScene.viewSize.width / GameScene.viewSize.height
        var w = b.width, h = b.width / aspect
        if h > b.height { h = b.height; w = h * aspect }
        skView.frame = CGRect(x: (b.width - w) / 2, y: (b.height - h) / 2, width: w, height: h)
        backdrop.frame = b
        blur.frame = b
    }

    private func refreshBackdrop() {
        guard let scene = skView.scene, skView.window != nil,
              let tex = skView.texture(from: scene, crop: CGRect(origin: .zero, size: GameScene.viewSize)) else { return }
        backdrop.image = UIImage(cgImage: tex.cgImage())
    }

    override var prefersStatusBarHidden: Bool { true }
    override var prefersHomeIndicatorAutoHidden: Bool { true }
    override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .landscape }
    override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation { .landscapeRight }
}
