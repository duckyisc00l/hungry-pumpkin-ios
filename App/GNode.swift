import SpriteKit
import UIKit

// A small re-creation of the Godot 2D node types the game uses.
// Nodes live under a parent whose y axis is flipped, so all positions,
// scales and rotations use Godot's own numbers (y pointing down).

enum Assets {
    static let root: URL = Bundle.main.resourceURL!.appendingPathComponent("AppAssets")
    private static var textures: [String: SKTexture] = [:]

    static func url(_ path: String) -> URL { root.appendingPathComponent(path) }

    static func texture(_ path: String) -> SKTexture? {
        if let t = textures[path] { return t }
        guard let img = UIImage(contentsOfFile: url(path).path) else {
            Log.write("missing texture \(path)")
            return nil
        }
        let t = SKTexture(image: img)
        textures[path] = t
        return t
    }

    static func texture(_ path: String, region: [Double]?) -> SKTexture? {
        guard let base = texture(path) else { return nil }
        guard let r = region, r.count == 4 else { return base }
        let key = path + "#" + r.map { String($0) }.joined(separator: ",")
        if let t = textures[key] { return t }
        let w = Double(base.size().width), h = Double(base.size().height)
        let rect = CGRect(x: r[0] / w, y: 1.0 - (r[1] + r[3]) / h, width: r[2] / w, height: r[3] / h)
        let t = SKTexture(rect: rect, in: base)
        textures[key] = t
        return t
    }
}

// JSON helpers
func num(_ v: Any?) -> Double {
    if let n = v as? NSNumber { return n.doubleValue }
    return 0
}
func vec(_ v: Any?) -> CGPoint {
    if let a = v as? [Any], a.count >= 2 { return CGPoint(x: num(a[0]), y: num(a[1])) }
    return .zero
}
func nums(_ v: Any?) -> [Double] {
    if let a = v as? [Any] { return a.map { num($0) } }
    return []
}

struct SpriteFrame {
    let texture: SKTexture?
    let duration: Double
}

struct SpriteAnim {
    let speed: Double
    let loop: Bool
    let frames: [SpriteFrame]
}

enum ShapeKind {
    case rect(w: Double, h: Double)
    case capsule(radius: Double, height: Double)
    case circle(radius: Double)
}

final class GNode: SKNode {
    let gType: String
    var gChildren: [GNode] = []
    weak var gParent: GNode?
    var freed = false
    var hovered = false
    var script: String?

    // drawing
    var visual: SKSpriteNode?
    var centered = true
    var flipH = false

    // AnimatedSprite2D
    var spriteAnims: [String: SpriteAnim] = [:]
    var animation: String = "default"
    var frameIndex: Int = 0
    var frameProgress: Double = 0
    var playing = false
    var onAnimationFinished: (() -> Void)?

    // AnimationPlayer (attached to the node that holds it)
    var player: AnimPlayer?
    var pendingAnims: [String: GAnimation]?

    // CollisionShape2D
    var shape: ShapeKind?

    // Timer
    var waitTime: Double = 1
    var timeLeft: Double = 0
    var timerRunning = false
    var onTimeout: (() -> Void)?

    // Label
    var label: SKLabelNode?
    var controlSize = CGSize.zero

    // TextureButton
    var normalTexture: SKTexture?
    var hoverTexture: SKTexture?

    init(type: String, name: String) {
        self.gType = type
        super.init()
        self.name = name
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    var gName: String { name ?? "" }

    func addGChild(_ c: GNode) {
        c.gParent = self
        gChildren.append(c)
        addChild(c)
    }

    func queueFree() {
        freed = true
        removeFromParent()
        if let p = gParent { p.gChildren.removeAll { $0 === self } }
    }

    func child(_ name: String) -> GNode? { gChildren.first { $0.gName == name } }

    func node(_ path: String) -> GNode? {
        var cur: GNode? = self
        for part in path.split(separator: "/") {
            if part == "." { continue }
            if part == ".." { cur = cur?.gParent } else { cur = cur?.child(String(part)) }
            if cur == nil { return nil }
        }
        return cur
    }

    var visible: Bool {
        get { !isHidden }
        set { isHidden = !newValue }
    }

    // MARK: sprite visuals

    func setTexture(_ tex: SKTexture?) {
        guard let tex = tex else { visual?.isHidden = true; return }
        if visual == nil {
            let s = SKSpriteNode(texture: tex)
            s.yScale = -1
            insertChild(s, at: 0)
            visual = s
        }
        guard let s = visual else { return }
        s.isHidden = false
        s.texture = tex
        s.size = tex.size()
        s.anchorPoint = centered ? CGPoint(x: 0.5, y: 0.5) : CGPoint(x: 0, y: 1)
        s.xScale = flipH ? -1 : 1
    }

    // MARK: AnimatedSprite2D (ported from Godot 4.2)

    func currentAnim() -> SpriteAnim? { spriteAnims[animation] }

    func updateFrameVisual() {
        guard let a = currentAnim(), !a.frames.isEmpty else { return }
        let f = a.frames[max(0, min(frameIndex, a.frames.count - 1))]
        setTexture(f.texture)
    }

    func setAnimation(_ name: String) {
        if animation == name { return }
        animation = name
        frameIndex = 0
        frameProgress = 0
        updateFrameVisual()
    }

    func setFrame(_ f: Int) {
        frameIndex = f
        frameProgress = 0
        updateFrameVisual()
    }

    func play(_ name: String? = nil) {
        let n = name ?? animation
        guard let a = spriteAnims[n] else { return }
        playing = true
        let endFrame = max(0, a.frames.count - 1)
        if n != animation {
            animation = n
            frameIndex = 0
            frameProgress = 0
        } else if frameIndex == endFrame && frameProgress >= 1.0 {
            frameIndex = 0
            frameProgress = 0
        }
        updateFrameVisual()
    }

    func processSprite(_ dt: Double) {
        guard playing, let a = currentAnim(), !a.frames.isEmpty else { return }
        var remaining = dt
        while remaining > 0 {
            let dur = a.frames[min(frameIndex, a.frames.count - 1)].duration
            let speed = a.speed * (dur > 0 ? 1.0 / dur : 1.0)
            if speed == 0 { return }
            let last = a.frames.count - 1
            if frameProgress >= 1.0 {
                if frameIndex >= last {
                    if a.loop {
                        frameIndex = 0
                    } else {
                        frameIndex = last
                        playing = false
                        updateFrameVisual()
                        onAnimationFinished?()
                        return
                    }
                } else {
                    frameIndex += 1
                }
                frameProgress = 0
                updateFrameVisual()
                continue
            }
            let toProcess = min((1.0 - frameProgress) / speed, remaining)
            frameProgress += toProcess * speed
            remaining -= toProcess
        }
    }

    // MARK: Timer

    func startTimer() {
        timeLeft = waitTime
        timerRunning = true
    }

    func processTimer(_ dt: Double) {
        guard timerRunning else { return }
        timeLeft -= dt
        if timeLeft <= 0 {
            timeLeft += waitTime
            onTimeout?()
        }
    }

    // MARK: properties set by animations

    func setProperty(_ prop: String, _ v: Any) {
        switch prop {
        case "position": position = vec(v)
        case "scale": let s = vec(v); xScale = s.x; yScale = s.y
        case "z_index": zPosition = CGFloat(num(v))
        case "visible": visible = (v as? NSNumber)?.boolValue ?? false
        case "frame": setFrame(Int(num(v)))
        case "animation": if let s = v as? String { setAnimation(s) }
        case "self_modulate":
            let c = nums(v)
            if c.count == 4 { visual?.alpha = CGFloat(c[3]) }
        default:
            Log.write("unhandled animated property \(prop)")
        }
    }
}

// MARK: - AnimationPlayer (value and method tracks, as used by the game)

struct Track {
    let node: String
    let prop: String
    let type: String
    let discrete: Bool
    let times: [Double]
    let trans: [Double]
    let values: [Any]
}

struct GAnimation {
    let length: Double
    let tracks: [Track]
}

// Godot's ease() curve
func godotEase(_ x0: Double, _ c: Double) -> Double {
    let x = min(max(x0, 0), 1)
    if c > 0 {
        if c < 1 { return 1.0 - pow(1.0 - x, 1.0 / c) }
        return pow(x, c)
    } else if c < 0 {
        if x < 0.5 { return pow(x * 2.0, -c) * 0.5 }
        return (1.0 - pow(1.0 - (x - 0.5) * 2.0, -c)) * 0.5 + 0.5
    }
    return 0
}

final class AnimPlayer {
    unowned let root: GNode
    let anims: [String: GAnimation]
    var current: String?
    var time: Double = 0
    var playing = false
    var onFinished: ((String) -> Void)?
    var onMethod: ((String) -> Void)?

    init(root: GNode, anims: [String: GAnimation]) {
        self.root = root
        self.anims = anims
    }

    func play(_ name: String) {
        if playing && current == name { return }
        guard anims[name] != nil else { return }
        current = name
        time = 0
        playing = true
        apply(from: -1, to: 0)
    }

    func process(_ dt: Double) {
        guard playing, let name = current, let a = anims[name] else { return }
        let prev = time
        time += dt
        if time >= a.length {
            time = a.length
            apply(from: prev, to: time)
            playing = false
            onFinished?(name)
        } else {
            apply(from: prev, to: time)
        }
    }

    private func apply(from prev: Double, to now: Double) {
        guard let name = current, let a = anims[name] else { return }
        for t in a.tracks {
            if t.type == "method" {
                for (i, kt) in t.times.enumerated() where kt > prev && kt <= now {
                    if let d = t.values[i] as? [String: Any], let pairs = d["DICT"] as? [[Any]] {
                        for p in pairs where (p.first as? String) == "method" {
                            if let m = p.last as? String { onMethod?(m) }
                        }
                    }
                }
                continue
            }
            guard let target = root.node(t.node), !t.times.isEmpty else { continue }
            if t.discrete {
                var idx = -1
                for (i, kt) in t.times.enumerated() where kt > prev && kt <= now { idx = i }
                if idx >= 0 { target.setProperty(t.prop, t.values[idx]) }
            } else {
                target.setProperty(t.prop, interpolate(t, at: now))
            }
        }
    }

    private func interpolate(_ t: Track, at time: Double) -> Any {
        if time <= t.times[0] { return t.values[0] }
        let n = t.times.count
        if time >= t.times[n - 1] { return t.values[n - 1] }
        var i = 0
        while i < n - 1 && t.times[i + 1] <= time { i += 1 }
        let span = t.times[i + 1] - t.times[i]
        var c = span > 0 ? (time - t.times[i]) / span : 1
        c = godotEase(c, t.trans[i])
        let a = nums(t.values[i]), b = nums(t.values[i + 1])
        if a.count == b.count && !a.isEmpty {
            return zip(a, b).map { $0 + ($1 - $0) * c }
        }
        return t.values[i]
    }
}
