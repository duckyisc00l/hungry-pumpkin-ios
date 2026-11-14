import SpriteKit

// Port of scripts/game.gd, scripts/food.gd, scripts/car.gd and
// scripts/mouse_follow.gd. The game area is 700 x 500, like the original.

// Wide-screen layout: the game is 500 units tall and as wide as the
// screen allows (700 to 1120). The art was widened to fill iPhone 17 screens.
enum Layout {
    static var width: CGFloat = 700
    static var safeInset: CGFloat = 0   // Dynamic Island side margin, in game units
    static let height: CGFloat = 500
    static let maxWidth: CGFloat = 1120
    static var size: CGSize { CGSize(width: width, height: height) }
}

final class GameScene: SKScene {

    private let world = SKNode()   // Godot canvas: y down, moved by the camera
    private let uiRoot = SKNode()  // Godot CanvasLayer: y down, fixed

    private var game: GNode!
    private var ui: GNode!

    // game.gd nodes
    private var foreground: GNode!
    private var playButton: GNode?
    private var walker: GNode!
    private var walkerAnim: GNode!
    private var pumpkin: GNode!
    private var pumpkinHead: GNode!
    private var pumpkinHandLeft: GNode!
    private var scoreAnimation: GNode!
    private var scoreLabel: GNode!
    private var car: GNode!
    private var startingPoint: GNode!
    private var plate: GNode!
    private var mouth: GNode!
    private var trash: GNode!

    // camera (Camera2D with position smoothing, speed 2)
    private let barPos = CGPoint(x: 350, y: 285)
    private let restaurantPos = CGPoint(x: 350, y: -160)
    private var cameraTarget = CGPoint(x: 350, y: 285)
    private var cameraSmoothed = CGPoint(x: 350, y: 285)
    private let smoothingSpeed: CGFloat = 2

    // game.gd state
    private var gameStarted = false
    private let foodNames = ["hamburger", "pizza", "sandwich", "hotdog", "fries", "eggs", "chicken", "butter", "cheese", "bread", "rice", "noodles", "salt", "pepper", "fish", "jam", "icewater", "orangejuice", "soda", "coffee"]
    private var served: [String] = []
    private var headAnim = ""
    private var gameCount = 0

    // input (Godot turns touches into a mouse pointer)
    private var pointer = CGPoint(x: 0, y: 500)
    private var buttonDown = false

    // timers and tweens
    private var clock: Double = 0
    private var lastTime: TimeInterval = 0
    private var timers: [(at: Double, run: () -> Void)] = []
    private var tweens: [Tween] = []

    private final class Tween {
        weak var node: GNode?
        var from = CGPoint.zero
        let to: CGPoint
        let duration: Double
        var elapsed: Double = 0
        var started = false
        let done: (() -> Void)?
        init(node: GNode, to: CGPoint, duration: Double, done: (() -> Void)?) {
            self.node = node; self.to = to; self.duration = duration; self.done = done
        }
    }

    override init(size: CGSize) {
        super.init(size: size)
        scaleMode = .fill
        anchorPoint = .zero
        backgroundColor = UIColor(red: 0.196, green: 0.196, blue: 0.196, alpha: 1)
    }

    required init?(coder aDecoder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        if game != nil { return }
        Log.write("building scene")
        guard let root = SceneLibrary.shared.sceneRoot(named: "Game") else {
            Log.write("Game scene missing")
            return
        }
        let built = SceneLibrary.shared.build(root)
        built.attachPlayers()

        // Split off the UI CanvasLayer so it does not move with the camera.
        if let uiNode = built.child("UI") {
            uiNode.removeFromParent()
            built.gChildren.removeAll { $0 === uiNode }
            ui = uiNode
        } else {
            ui = GNode(type: "CanvasLayer", name: "UI")
        }
        game = built

        world.yScale = -1
        addChild(world)
        world.addChild(game)

        uiRoot.yScale = -1
        uiRoot.position = CGPoint(x: 0, y: Layout.height)
        uiRoot.zPosition = 1000
        addChild(uiRoot)
        uiRoot.addChild(ui)

        // Keep the play button and score box clear of the Dynamic Island.
        ui.node("Control/PlayButton")?.position.x -= Layout.safeInset
        for n in ["Back", "Flash", "Base"] {
            ui.node("Control/ScorePanel/" + n)?.position.x += Layout.width - 700 - Layout.safeInset
        }

        // A Camera2D node has nothing to draw.
        game.child("Camera")?.queueFree()

        foreground = game.node("Level/Foreground")
        playButton = ui.node("Control/PlayButton")
        walker = game.node("Level/Street/Walker")
        walkerAnim = game.node("Level/Street/Walker/AnimationPlayer")
        pumpkin = game.node("Level/Foreground/Pumpkin")
        pumpkinHead = game.node("Level/Foreground/Pumpkin/Head")
        pumpkinHandLeft = game.node("Level/Foreground/Pumpkin/HandLeft")
        scoreAnimation = ui.node("Control/ScorePanel/AnimationPlayer")
        scoreLabel = ui.node("Control/ScorePanel/Back/ScoreLabel")
        car = game.node("Level/Street/Car")
        startingPoint = game.node("Level/Foreground/Top/FoodChoice/StartingPoint")
        plate = game.node("Level/Foreground/Top/FoodChoice/Plate")
        mouth = game.node("Level/Foreground/Top/FoodChoice/Mouth")
        trash = game.node("Level/Foreground/Top/FoodChoice/Trash")

        // signal connections from game.tscn
        walkerAnim.player?.onFinished = { [weak self] name in self?.onWalkerAnimationFinished(name) }
        walkerAnim.player?.onMethod = { [weak self] m in if m == "walker_play_sound" { self?.walkerPlaySound() } }
        pumpkinHead.onAnimationFinished = { [weak self] in self?.onHeadAnimationFinished() }
        AudioManager.shared.onTalkFinished = { [weak self] in self?.outro() }

        // car.gd
        if let timer = car.child("Timer") {
            timer.waitTime = Double(Int.random(in: 5...20))
            timer.onTimeout = { [weak self] in self?.car.child("AnimationPlayer")?.player?.play("ride") }
        }

        // game.gd _ready
        setDefaultGlobalValues()
        walker.visible = false
        scoreLabel.label?.text = String(GameState.score)
        GameState.randomFoodList = foodNames.shuffled()

        // remember where the eyes sit so they can grow with the head
        for path in ["EyesBack", "EyeRightOrigin", "EyeLeftOrigin"] {
            if let n = pumpkin.node(path) { eyeParts.append((n, n.position, n.xScale)) }
        }
        headHome = pumpkinHead.position

        applyCamera()
        Log.write("scene ready")
    }

    private func setDefaultGlobalValues() {
        GameState.isHovering = false
        GameState.score = 0
        GameState.isBar = true
        GameState.gameState = "bar"
        GameState.ordered = ""
        GameState.userPick = ""
        GameState.canPick = false
        GameState.isNo = false
        GameState.randomFoodList = []
    }

    // MARK: helpers

    private func after(_ seconds: Double, _ f: @escaping () -> Void) {
        timers.append((at: clock + seconds, run: f))
    }

    private func globalPosition(_ n: GNode) -> CGPoint {
        world.convert(CGPoint.zero, from: n)
    }

    private func tween(_ n: GNode, to: CGPoint, _ duration: Double, done: (() -> Void)? = nil) {
        tweens.append(Tween(node: n, to: to, duration: duration, done: done))
    }

    private func applyCamera() {
        world.position = CGPoint(x: Layout.width / 2 - cameraSmoothed.x, y: Layout.height / 2 + cameraSmoothed.y)
        // AudioStreamPlayer2D at (0,0): distance attenuation and panning against the camera
        let dist = hypot(cameraSmoothed.x, cameraSmoothed.y)
        AudioManager.shared.volume = Float(max(0, 1 - dist / 2000))
        let p = min(max(-cameraSmoothed.x / Layout.width, -1), 1) * 0.25
        AudioManager.shared.pan = Float(p * 2)
    }

    // MARK: frame loop

    override func update(_ currentTime: TimeInterval) {
        guard game != nil else { return }
        var dt = lastTime == 0 ? 1.0 / 60.0 : currentTime - lastTime
        lastTime = currentTime
        dt = min(max(dt, 0), 0.1)
        clock += dt

        // scene tree timers
        let due = timers.filter { $0.at <= clock }
        timers.removeAll { $0.at <= clock }
        due.forEach { $0.run() }

        process()

        game.walk { n in
            n.processSprite(dt)
            n.player?.process(dt)
            n.processTimer(dt)
            if n.script == "scripts/mouse_follow.gd" { mouseFollow(n) }
        }
        ui.walk { n in
            n.processSprite(dt)
            n.player?.process(dt)
        }

        for t in tweens {
            guard let n = t.node, !n.freed else { t.elapsed = t.duration; continue }
            if !t.started { t.from = n.position; t.started = true }
            t.elapsed += dt
            let c = CGFloat(min(t.elapsed / t.duration, 1))
            n.position = CGPoint(x: t.from.x + (t.to.x - t.from.x) * c, y: t.from.y + (t.to.y - t.from.y) * c)
        }
        let finished = tweens.filter { $0.elapsed >= $0.duration }
        tweens.removeAll { $0.elapsed >= $0.duration }
        finished.forEach { if $0.node != nil { $0.done?() } }

        updateHover()

        let c = smoothingSpeed * CGFloat(dt)
        cameraSmoothed.x += (cameraTarget.x - cameraSmoothed.x) * c
        cameraSmoothed.y += (cameraTarget.y - cameraSmoothed.y) * c
        applyCamera()
    }

    // game.gd _process
    private func process() {
        if GameState.gameState == "choice" {
            if GameState.userPick != "" && GameState.ordered != "" {
                let pick = GameState.userPick
                GameState.userPick = ""
                if pick == GameState.ordered {
                    Haptics.correct()
                    handleCorrectFood(pick)
                } else {
                    Haptics.wrong()
                    handleIncorrectFood(pick)
                }
            }
        }
    }

    // mouse_follow.gd
    private func mouseFollow(_ marker: GNode) {
        guard let child = marker.gChildren.first else { return }
        let local = marker.convert(pointer, from: self)
        let dist = hypot(local.x, local.y)
        if dist == 0 { child.position = .zero; return }
        let m = min(dist, 10 * eyeFollowScale)
        child.position = CGPoint(x: local.x / dist * m, y: local.y / dist * m)
    }

    // MARK: game.gd

    private func changeView() {
        if GameState.isBar {
            GameState.isBar = false
            cameraTarget = restaurantPos
        }
    }

    private func onPlayButtonPressed() {
        Haptics.tap()
        changeView()
        playButton?.queueFree()
        playButton = nil
        walkerAnim.player?.play("intro")
        GameState.gameState = "intro"
        gameStarted = true
    }

    private func onWalkerAnimationFinished(_ name: String) {
        switch name {
        case "intro":
            walker.visible = false
            gameStart()
        case "end":
            after(3) { [weak self] in self?.reloadScene() }
        default:
            break
        }
    }

    private func reloadScene() {
        guard let view = view else { return }
        let next = GameScene(size: Layout.size)
        view.presentScene(next)
    }

    private func walkerPlaySound() {
        AudioManager.shared.playPumpkinSound("imveryhungry")
    }

    private func gameStart() {
        car.child("Timer")?.startTimer()
        applyHeadSize(headScale(for: Progress.saved))
        pumpkin.visible = true
        scoreAnimation.player?.play("show")
        GameState.canPick = false
        serve()
    }

    private func addScore() {
        GameState.score += 1
        AudioManager.shared.playGameSound("score")
        scoreAnimation.player?.play("score")
        scoreLabel.label?.text = String(GameState.score)
        Progress.saved += 1   // total foods eaten over all games
        applyHeadSize(headScale(for: Progress.saved))
    }

    // MARK: growing head and the 500-food win (added for iPhone)

    private var eyeParts: [(node: GNode, pos: CGPoint, scale: CGFloat)] = []
    private var headHome = CGPoint.zero
    private var eyeFollowScale: CGFloat = 1
    private var winReady = false

    // 0.85 at the start (original size), 1.9 when he is about to pop
    private func headScale(for score: Int) -> CGFloat {
        let t = CGFloat(min(score, Progress.target)) / CGFloat(Progress.target)
        return 0.85 + (1.9 - 0.85) * t
    }

    // Scale the head around its centre and keep the eyes lined up with its eye holes.
    private func applyHeadSize(_ s: CGFloat) {
        pumpkinHead.xScale = s
        pumpkinHead.yScale = s
        let f = s / 0.85
        eyeFollowScale = f
        for e in eyeParts {
            e.node.position = CGPoint(x: headHome.x + (e.pos.x - headHome.x) * f,
                                      y: headHome.y + (e.pos.y - headHome.y) * f)
            e.node.xScale = e.scale * f
            e.node.yScale = e.scale * f
        }
    }

    private func win() {
        GameState.gameState = "win"
        GameState.canPick = false
        Progress.saved = 0
        AudioManager.shared.playPumpkinSound("fantastic")
        // puff up and wobble...
        let grow = SKAction.customAction(withDuration: 2.4) { [weak self] _, t in
            guard let self = self else { return }
            let p = t / 2.4
            let wobble = sin(p * 40) * 0.04 * p
            self.applyHeadSize(1.9 + 0.6 * p * p + wobble)
        }
        pumpkinHead.run(grow) { [weak self] in self?.pop() }
    }

    private func pop() {
        Haptics.pop()
        AudioManager.shared.playGameSound("pop")
        let center = world.convert(CGPoint.zero, from: pumpkinHead)
        pumpkin.visible = false
        // pumpkin pieces fly out
        let colors: [UIColor] = [UIColor(red: 1, green: 0.66, blue: 0, alpha: 1),
                                 UIColor(red: 1, green: 0.8, blue: 0.1, alpha: 1),
                                 UIColor(red: 0.95, green: 0.5, blue: 0, alpha: 1),
                                 UIColor(red: 0.35, green: 0.2, blue: 0.05, alpha: 1)]
        for i in 0..<70 {
            let r = CGFloat.random(in: 6...22)
            let piece = SKShapeNode(path: piecePath(r))
            piece.fillColor = colors[i % colors.count]
            piece.strokeColor = .black
            piece.lineWidth = 2
            piece.position = center
            piece.zPosition = 50
            piece.zRotation = .random(in: 0...(2 * .pi))
            world.addChild(piece)
            let angle = CGFloat.random(in: 0...(2 * .pi))
            let speed = CGFloat.random(in: 350...900)
            let dx = cos(angle) * speed, dy = sin(angle) * speed
            let fly = SKAction.customAction(withDuration: 2.2) { node, t in
                let tt = CGFloat(t)
                // y is down in the game world, so gravity adds to y
                node.position = CGPoint(x: center.x + dx * tt, y: center.y + dy * tt + 700 * tt * tt)
            }
            piece.run(.group([fly, .rotate(byAngle: .random(in: -12...12), duration: 2.2),
                              .sequence([.wait(forDuration: 1.4), .fadeOut(withDuration: 0.8)])])) {
                piece.removeFromParent()
            }
        }
        after(1.0) { [weak self] in self?.showWin() }
    }

    // Testing shortcut: 5 quick taps on the score box set the total to 495.
    private var scoreTaps: [Double] = []
    private func scoreBoxContains(_ p: CGPoint) -> Bool {
        guard let back = ui.node("Control/ScorePanel/Back"), back.inParentHierarchy(self),
              ui.node("Control/ScorePanel")?.visible == true else { return false }
        let l = back.convert(p, from: self)
        return l.x >= 0 && l.y >= 0 && l.x <= 111 && l.y <= 49
    }
    private func scoreBoxTapped() {
        scoreTaps = scoreTaps.filter { clock - $0 < 2 } + [clock]
        guard scoreTaps.count >= 5, Progress.saved < Progress.target - 5 else { return }
        scoreTaps = []
        Progress.saved = Progress.target - 5
        applyHeadSize(headScale(for: Progress.saved))
        Haptics.tap()
    }

    private func piecePath(_ r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let n = Int.random(in: 3...5)
        for k in 0..<n {
            let a = CGFloat(k) / CGFloat(n) * 2 * .pi
            let rr = r * CGFloat.random(in: 0.6...1.2)
            let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
            if k == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath()
        return p
    }

    private func showWin() {
        AudioManager.shared.playGameSound("score")
        let banner = SKNode()
        banner.position = CGPoint(x: Layout.width / 2, y: Layout.height / 2 + 40)
        banner.zPosition = 2000
        addChild(banner)
        func label(_ text: String, size: CGFloat, y: CGFloat, color: UIColor) {
            for (dx, dy, c) in [(CGFloat(3), CGFloat(-3), UIColor.black), (CGFloat(0), CGFloat(0), color)] {
                let l = SKLabelNode(text: text)
                l.fontName = "ChalkboardSE-Bold"
                l.fontSize = size
                l.fontColor = c
                l.verticalAlignmentMode = .center
                l.position = CGPoint(x: dx, y: y + dy)
                banner.addChild(l)
            }
        }
        label("YOU WIN!", size: 96, y: 0, color: UIColor(red: 1, green: 0.62, blue: 0, alpha: 1))
        label("You fed him 500 foods and he popped!", size: 30, y: -80, color: .white)
        label("Tap to play again", size: 26, y: -130, color: UIColor(white: 0.9, alpha: 1))
        banner.setScale(0.2)
        banner.run(.sequence([.scale(to: 1.1, duration: 0.25), .scale(to: 1.0, duration: 0.12)]))
        // confetti
        for i in 0..<120 {
            let c = SKSpriteNode(color: [UIColor.systemRed, .systemYellow, .systemGreen, .systemBlue, .systemPink, .systemOrange][i % 6],
                                 size: CGSize(width: 8, height: 14))
            c.position = CGPoint(x: .random(in: 0...Layout.width), y: Layout.height + .random(in: 10...300))
            c.zPosition = 1900
            addChild(c)
            let t = Double.random(in: 2.5...4.5)
            c.run(.group([.moveBy(x: .random(in: -80...80), y: -(Layout.height + 350), duration: t),
                          .repeatForever(.rotate(byAngle: .pi, duration: Double.random(in: 0.3...0.8)))]))
        }
        after(1.5) { [weak self] in self?.winReady = true }
    }

    private func serveOne(_ food: String, _ slot: Int) {
        guard let inst = SceneLibrary.shared.instantiate(food) else {
            Log.write("food scene missing: \(food)")
            return
        }
        inst.attachPlayers()
        foreground.addGChild(inst)
        inst.position = globalPosition(startingPoint)
        inst.zPosition += 1
        if let slotNode = game.node("Level/Foreground/Top/FoodChoice/Slot0\(slot)") {
            tween(inst, to: globalPosition(slotNode), 1.0)
        }
        served.append(food)
    }

    private func serve() {
        var i = 1
        while i <= 4 {
            let idx = (i + gameCount) - 1
            if idx < GameState.randomFoodList.count {
                serveOne(GameState.randomFoodList[idx], i)
            }
            i += 1
        }
        gameCount += 4
        GameState.canPick = false
        afterServe()
    }

    private func afterServe() {
        guard let pick = served.randomElement() else { return }
        GameState.ordered = pick
        AudioManager.shared.playGivemeSound(pick)
        pumpkinHead.play("order")
        headAnim = "order"
        GameState.gameState = "choice"
    }

    private func tryAgain() {
        AudioManager.shared.playGivemeSound(GameState.ordered)
        pumpkinHead.play("order")
        headAnim = "order"
        GameState.gameState = "choice"
    }

    private func nodeName(for pick: String) -> String {
        if pick == "orange_juice" || pick == "orangejuice" { return "OrangeJuice" }
        if pick == "ice_water" || pick == "icewater" { return "IceWater" }
        return pick.prefix(1).uppercased() + pick.dropFirst()
    }

    private func handleCorrectFood(_ pick: String) {
        GameState.canPick = false
        GameState.ordered = ""
        guard let food = foreground.child(nodeName(for: pick)) else { return }
        after(0.4) { [weak self] in
            guard let self = self else { return }
            self.pumpkinHandLeft.play("eat")
            self.pumpkinHead.play("eat")
            self.headAnim = "eat"
            AudioManager.shared.playPumpkinSound("eat")
            if !food.freed {
                self.moveToMouth(food)
                self.served.removeAll { $0 == pick }
            }
        }
    }

    private func handleIncorrectFood(_ pick: String) {
        GameState.canPick = false
        guard let food = foreground.child(nodeName(for: pick)) else { return }
        after(0.4) { [weak self] in
            guard let self = self else { return }
            self.pumpkinHandLeft.play("no")
            self.pumpkinHead.play("no")
            self.headAnim = "no"
            GameState.isNo = true
            AudioManager.shared.playPumpkinSound("noidontwantthat")
            if !food.freed {
                self.moveToTrash(food)
                self.served.removeAll { $0 == pick }
            }
        }
    }

    private func ending() {
        GameState.gameState = "end"
        GameState.isNo = true
        pumpkinHead.play("talk")
        let s = GameState.score
        if s < 7 {
            AudioManager.shared.playPumpkinSound("terrible")
        } else if s < 16 {
            AudioManager.shared.playPumpkinSound("notbad")
        } else if s < 19 {
            AudioManager.shared.playPumpkinSound("delicious")
        } else {
            AudioManager.shared.playPumpkinSound("fantastic")
        }
    }

    private func outro() {
        pumpkin.visible = false
        walkerAnim.player?.play("end")
        GameState.canPick = false
    }

    private func nextRoundOrEnd() {
        if !served.isEmpty { return }
        if gameCount < 20 { serve() } else { ending() }
    }

    private func onHeadAnimationFinished() {
        if headAnim == "eat" {
            headAnim = ""
            addScore()
            if Progress.saved >= Progress.target {
                pumpkinHandLeft.play("idle")
                pumpkinHead.play("idle")
                headAnim = "idle"
                win()
                return
            }
            GameState.canPick = true
            pumpkinHandLeft.play("idle")
            pumpkinHead.play("idle")
            headAnim = "idle"
            if !served.isEmpty { afterServe() } else { nextRoundOrEnd() }
        } else if headAnim == "no" {
            headAnim = ""
            GameState.canPick = true
            GameState.isNo = false
            pumpkinHandLeft.play("idle")
            pumpkinHead.play("idle")
            headAnim = "idle"
            if !served.isEmpty { tryAgain() } else { nextRoundOrEnd() }
        } else if headAnim == "order" {
            headAnim = ""
            GameState.canPick = true
            pumpkinHandLeft.play("idle")
            pumpkinHead.play("idle")
            headAnim = "idle"
        }
    }

    // MARK: food.gd

    private func foods() -> [GNode] {
        var out: [GNode] = []
        game.walk { if $0.script == "scripts/food.gd" { out.append($0) } }
        return out
    }

    private func arrow(of food: GNode) -> GNode? { food.node("Area/Arrow") }

    private func foodMouseEntered(_ food: GNode) {
        if GameState.gameState == "choice" {
            if GameState.canPick { arrow(of: food)?.visible = true }
        } else if GameState.isBar {
            arrow(of: food)?.visible = true
        }
    }

    private func foodMouseExited(_ food: GNode) {
        arrow(of: food)?.visible = false
        GameState.isHovering = false
    }

    private func foodPressed(_ food: GNode) {
        if GameState.isBar {
            Haptics.tap()
            AudioManager.shared.playFoodSound(food.gName)
        } else if GameState.gameState == "choice" && GameState.canPick {
            GameState.canPick = false
            GameState.userPick = food.gName.lowercased()
            moveToPlate(food)
        }
    }

    private func moveToPlate(_ food: GNode) {
        GameState.canPick = false
        foodMouseExited(food)
        tween(food, to: globalPosition(plate), 0.2)
    }

    private func moveToMouth(_ food: GNode) {
        GameState.canPick = false
        foodMouseExited(food)
        food.zPosition -= 1
        tween(food, to: globalPosition(mouth), 0.2) { food.queueFree() }
    }

    private func moveToTrash(_ food: GNode) {
        GameState.canPick = false
        foodMouseExited(food)
        tween(food, to: globalPosition(trash), 0.4) { food.queueFree() }
    }

    // Is the pointer over the food's Area2D collision shapes?
    private func hit(_ food: GNode, _ p: CGPoint) -> Bool {
        guard let area = food.child("Area") else { return false }
        for s in area.gChildren {
            guard let shape = s.shape else { continue }
            let l = s.convert(p, from: self)
            switch shape {
            case let .rect(w, h):
                if abs(l.x) <= w / 2 && abs(l.y) <= h / 2 { return true }
            case let .circle(r):
                if hypot(l.x, l.y) <= r { return true }
            case let .capsule(r, h):
                let half = max(0, h / 2 - r)
                let cy = min(max(Double(l.y), -half), half)
                if hypot(Double(l.x), Double(l.y) - cy) <= r { return true }
            }
        }
        return false
    }

    private func updateHover() {
        for f in foods() {
            let inside = hit(f, pointer)
            if inside && !f.hovered {
                f.hovered = true
                foodMouseEntered(f)
            } else if !inside && f.hovered {
                f.hovered = false
                foodMouseExited(f)
            }
        }
        if let b = playButton {
            b.setTexture(buttonContains(pointer) ? (b.hoverTexture ?? b.normalTexture) : b.normalTexture)
        }
    }

    // global z then tree order, topmost first
    private func foodsUnder(_ p: CGPoint) -> [GNode] {
        var list: [(GNode, CGFloat, Int)] = []
        var order = 0
        game.walk { n in
            order += 1
            if n.script == "scripts/food.gd" && self.hit(n, p) {
                var z: CGFloat = 0
                var cur: GNode? = n
                while let c = cur { z += c.zPosition; cur = c.gParent }
                list.append((n, z, order))
            }
        }
        list.sort { $0.1 != $1.1 ? $0.1 > $1.1 : $0.2 > $1.2 }
        return list.map { $0.0 }
    }

    private func buttonContains(_ p: CGPoint) -> Bool {
        guard let b = playButton, b.visible else { return false }
        let l = b.convert(p, from: self)
        return l.x >= 0 && l.y >= 0 && l.x <= b.controlSize.width && l.y <= b.controlSize.height
    }

    // MARK: touches

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard game != nil, let t = touches.first else { return }
        pointer = t.location(in: self)
        if GameState.gameState == "win" {
            if winReady { winReady = false; reloadScene() }
            return
        }
        if scoreBoxContains(pointer) { scoreBoxTapped() }
        if buttonContains(pointer) {
            buttonDown = true
            updateHover()
            return
        }
        updateHover()
        for f in foodsUnder(pointer) {
            foodPressed(f)
        }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard game != nil, let t = touches.first else { return }
        pointer = t.location(in: self)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard game != nil, let t = touches.first else { return }
        pointer = t.location(in: self)
        if buttonDown {
            buttonDown = false
            if buttonContains(pointer) { onPlayButtonPressed() }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        buttonDown = false
    }
}

// Vibration feedback (not in the Android version; added for iPhone)
enum Haptics {
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let notify = UINotificationFeedbackGenerator()

    static func tap() { light.impactOccurred() }
    static func correct() { notify.notificationOccurred(.success) }
    static func wrong() { notify.notificationOccurred(.error) }
    static func pop() { UIImpactFeedbackGenerator(style: .heavy).impactOccurred(intensity: 1) }
}

// How many correct foods it takes to pop him, and the saved count.
enum Progress {
    static let target = 500
    static var saved: Int {
        get { UserDefaults.standard.integer(forKey: "fedCount") }
        set { UserDefaults.standard.set(newValue, forKey: "fedCount") }
    }
}
