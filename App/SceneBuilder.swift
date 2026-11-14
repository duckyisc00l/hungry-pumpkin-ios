import SpriteKit
import CoreText
import CoreGraphics

// Builds GNode trees from scenes.json, which was converted from the
// APK's own Godot scene files (positions, sprites, animations, shapes).

final class SceneLibrary {
    static let shared = SceneLibrary()
    let scenes: [String: Any]

    private init() {
        let url = Assets.url("scenes.json")
        if let data = try? Data(contentsOf: url),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            scenes = obj
        } else {
            Log.write("could not read scenes.json")
            scenes = [:]
        }
    }

    func sceneRoot(named key: String) -> [String: Any]? {
        let match = scenes.keys.first { $0.lowercased() == key.lowercased() }
        guard let k = match, let s = scenes[k] as? [String: Any] else { return nil }
        return s["root"] as? [String: Any]
    }

    func instantiate(_ key: String) -> GNode? {
        guard let root = sceneRoot(named: key) else { return nil }
        return build(root)
    }

    func build(_ d0: [String: Any]) -> GNode {
        var d = d0
        var children = (d0["children"] as? [[String: Any]]) ?? []
        if let inst = d0["instance"] as? String, let base = sceneRoot(named: inst) {
            var merged = base
            for (k, v) in d0 where k != "children" && k != "instance" && k != "type" { merged[k] = v }
            children = ((base["children"] as? [[String: Any]]) ?? []) + children
            d = merged
        }
        let type = (d["type"] as? String) ?? "Node2D"
        let node = GNode(type: type, name: (d["name"] as? String) ?? "")
        node.script = d["script"] as? String

        if let p = d["position"] { node.position = vec(p) }
        if let s = d["scale"] { let v = vec(s); node.xScale = v.x; node.yScale = v.y }
        if let r = d["rotation"] { node.zRotation = CGFloat(num(r)) }
        if let z = d["z_index"] { node.zPosition = CGFloat(num(z)) }
        if let v = d["visible"] as? NSNumber { node.visible = v.boolValue }
        if let c = d["centered"] as? NSNumber { node.centered = c.boolValue }
        if let f = d["flip_h"] as? NSNumber { node.flipH = f.boolValue }

        switch type {
        case "Sprite2D":
            if let t = d["texture"] as? String { node.setTexture(Assets.texture(t)) }
        case "AnimatedSprite2D":
            if let fr = d["frames"] as? [String: Any] {
                for (name, a0) in fr {
                    guard let a = a0 as? [String: Any] else { continue }
                    let frames: [SpriteFrame] = ((a["frames"] as? [[String: Any]]) ?? []).map { f in
                        let tex = Assets.texture((f["tex"] as? String) ?? "", region: f["region"].map { nums($0) })
                        return SpriteFrame(texture: tex, duration: num(f["dur"]))
                    }
                    node.spriteAnims[name] = SpriteAnim(speed: num(a["speed"]),
                                                        loop: (a["loop"] as? NSNumber)?.boolValue ?? false,
                                                        frames: frames)
                }
            }
            if let a = d["animation"] as? String { node.animation = a }
            if node.spriteAnims[node.animation] == nil, node.spriteAnims["default"] != nil { node.animation = "default" }
            node.updateFrameVisual()
            if let auto = d["autoplay"] as? String, !auto.isEmpty { node.play(auto) }
        case "CollisionShape2D":
            if let s = d["shape"] as? [Any] {
                let v = nums(s)
                node.shape = .rect(w: v[0], h: v[1])
            } else if let s = d["shape"] as? [String: Any] {
                if s["height"] != nil {
                    node.shape = .capsule(radius: num(s["radius"]), height: num(s["height"]))
                } else {
                    node.shape = .circle(radius: num(s["radius"]))
                }
            }
        case "Timer":
            if let w = d["wait_time"] { node.waitTime = num(w) }
        case "Control", "TextureRect", "TextureButton", "Label":
            let al = num(d["anchor_left"]), at = num(d["anchor_top"])
            let ar = num(d["anchor_right"]), ab = num(d["anchor_bottom"])
            let ol = num(d["offset_left"]), ot = num(d["offset_top"])
            let or_ = num(d["offset_right"]), ob = num(d["offset_bottom"])
            let pw = 700.0, ph = 500.0 // only top-level controls use anchors in this game
            node.position = CGPoint(x: al * pw + ol, y: at * ph + ot)
            node.controlSize = CGSize(width: (ar * pw + or_) - (al * pw + ol), height: (ab * ph + ob) - (at * ph + ot))
            node.centered = false
            if type == "TextureRect", let t = d["texture"] as? String {
                node.setTexture(Assets.texture(t))
            }
            if type == "TextureButton" {
                node.normalTexture = (d["texture_normal"] as? String).flatMap { Assets.texture($0) }
                node.hoverTexture = (d["texture_hover"] as? String).flatMap { Assets.texture($0) }
                node.setTexture(node.normalTexture)
            }
            if type == "Label" {
                let l = SKLabelNode(text: (d["text"] as? String) ?? "")
                l.fontName = Fonts.scoreFontName
                l.fontSize = CGFloat(num(d["theme_override_font_sizes/font_size"]))
                l.fontColor = .white
                l.horizontalAlignmentMode = .center
                l.verticalAlignmentMode = .center
                l.position = CGPoint(x: node.controlSize.width / 2, y: node.controlSize.height / 2)
                l.yScale = -1
                node.addChild(l)
                node.label = l
            }
        default:
            break
        }

        for c in children {
            node.addGChild(build(c))
        }

        // AnimationPlayer: its tracks are relative to its parent node
        if let anims = d["anims"] as? [String: Any], type == "AnimationPlayer" {
            var lib: [String: GAnimation] = [:]
            for (name, a0) in anims {
                guard let a = a0 as? [String: Any] else { continue }
                let tracks: [Track] = ((a["tracks"] as? [[String: Any]]) ?? []).map { t in
                    Track(node: (t["node"] as? String) ?? ".",
                          prop: (t["prop"] as? String) ?? "",
                          type: (t["type"] as? String) ?? "value",
                          discrete: num(t["update"]) == 1,
                          times: nums(t["times"]),
                          trans: nums(t["trans"]),
                          values: (t["values"] as? [Any]) ?? [])
                }
                lib[name] = GAnimation(length: num(a["length"]), tracks: tracks)
            }
            node.pendingAnims = lib
        }
        return node
    }
}

extension GNode {
    // After the tree is built, hook every AnimationPlayer up to its parent.
    func attachPlayers() {
        if gType == "AnimationPlayer", let anims = pendingAnims, let parent = gParent {
            player = AnimPlayer(root: parent, anims: anims)
        }
        for c in gChildren { c.attachPlayers() }
    }

    func walk(_ f: (GNode) -> Void) {
        if freed { return }
        f(self)
        for c in gChildren { c.walk(f) }
    }
}

enum Fonts {
    static var scoreFontName: String = "Helvetica-Bold"

    static func register() {
        let url = Assets.url("assets/fonts/cartoonist_hand.ttf")
        var err: Unmanaged<CFError>?
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, &err)
        if let provider = CGDataProvider(url: url as CFURL), let font = CGFont(provider),
           let ps = font.postScriptName {
            scoreFontName = ps as String
        }
        Log.write("score font: \(scoreFontName)")
    }
}
