import SpriteKit

// Port of scripts/game.gd, scripts/food.gd, scripts/car.gd and
// scripts/mouse_follow.gd. The game area is 700 x 500, like the original.

final class GameScene: SKScene {
    static let viewSize = CGSize(width: 700, height: 500)

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
        uiRoot.position = CGPoint(x: 0, y: GameScene.viewSize.height)
        uiRoot.zPosition = 1000
        addChild(uiRoot)
        uiRoot.addChild(ui)

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
        world.position = CGPoint(x: 350 - cameraSmoothed.x, y: 250 + cameraSmoothed.y)
        // AudioStreamPlayer2D at (0,0): distance attenuation and panning against the camera
        let dist = hypot(cameraSmoothed.x, cameraSmoothed.y)
        AudioManager.shared.volume = Float(max(0, 1 - dist / 2000))
        let p = min(max(-cameraSmoothed.x / 700, -1), 1) * 0.25
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
                    handleCorrectFood(pick)
                } else {
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
        let m = min(dist, 10)
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
        let next = GameScene(size: GameScene.viewSize)
        view.presentScene(next)
    }

    private func walkerPlaySound() {
        AudioManager.shared.playPumpkinSound("imveryhungry")
    }

    private func gameStart() {
        car.child("Timer")?.startTimer()
        pumpkinHead.xScale = 0.85
        pumpkinHead.yScale = 0.85
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
        pumpkinHead.xScale += 0.0075
        pumpkinHead.yScale += 0.0075
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
