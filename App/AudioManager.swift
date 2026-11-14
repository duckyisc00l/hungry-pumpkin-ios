import AVFoundation

// Port of global/audio_manager.gd: three sound players (food, pumpkin, game).
final class AudioManager: NSObject, AVAudioPlayerDelegate {
    static let shared = AudioManager()

    private var food: AVAudioPlayer?
    private var pumpkin: AVAudioPlayer?
    private var game: AVAudioPlayer?

    // Godot: PumpkinSFX.finished -> _on_pumpkin_sfx_finished (emits talk_finished in the "end" state)
    var onTalkFinished: (() -> Void)?
    // Godot: "await pumpkin_sfx.finished" in play_giveme_sound
    private var pumpkinWaiters: [() -> Void] = []

    // AudioStreamPlayer2D volume and panning, worked out from the camera each frame
    var volume: Float = 1 { didSet { [food, pumpkin, game].forEach { $0?.volume = volume } } }
    var pan: Float = 0 { didSet { [food, pumpkin, game].forEach { $0?.pan = pan } } }

    static func setUpSession() {
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? s.setActive(true)
    }

    private func make(_ path: String) -> AVAudioPlayer? {
        let url = Assets.url(path)
        guard let p = try? AVAudioPlayer(contentsOf: url) else {
            Log.write("Audio file not found: \(path)")
            return nil
        }
        p.delegate = self
        p.volume = volume
        p.pan = pan
        p.prepareToPlay()
        return p
    }

    private func path(_ folder: String, _ sound: String) -> String {
        "assets/\(folder)/\(sound.lowercased())_audio.mp3"
    }

    func playFoodSound(_ name: String) {
        food?.stop()
        food = make(path("food", name))
        food?.play()
    }

    func playGameSound(_ name: String) {
        game?.stop()
        game = make(path("audio", name))
        game?.play()
    }

    // Food name loaded ahead of time and scheduled to start right as "Give me" ends.
    private var pendingName: AVAudioPlayer?

    private func playPumpkin(_ p: String) {
        pumpkin?.stop()
        pendingName?.stop()
        pendingName = nil
        pumpkin = make(p)
        pumpkin?.play()
    }

    func playPumpkinSound(_ sound: String) {
        playPumpkin(path("pumpkin/audio", "pumpkin_" + sound.lowercased()))
    }

    func playGivemeSound(_ foodName: String) {
        let n = Int.random(in: 1...3)
        playPumpkin("assets/pumpkin/audio/pumpkin_giveme\(n)_audio.mp3")
        // No gap: start the food name exactly when "Give me" ends
        // (its first 0.07 s is silence, so begin it 0.05 s early).
        if let giveme = pumpkin, let name = make("assets/pumpkin/food_audio/pumpkin_\(foodName.lowercased())_audio.mp3") {
            let startAt = giveme.deviceCurrentTime + max(0, giveme.duration - giveme.currentTime - 0.05)
            name.play(atTime: startAt)
            pendingName = name
        }
        pumpkinWaiters.append { [weak self] in
            guard let self = self, let name = self.pendingName else { return }
            self.pendingName = nil
            if GameState.isNo { name.stop(); return }
            self.pumpkin = name   // it is already playing
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard player === pumpkin else { return }
        if GameState.gameState == "end" { onTalkFinished?() }
        let waiters = pumpkinWaiters
        pumpkinWaiters = []
        waiters.forEach { $0() }
    }
}

// Port of global/global.gd
enum GameState {
    static var isHovering = false
    static var score = 0
    static var isBar = true
    static var gameState = "bar"
    static var ordered = ""
    static var userPick = ""
    static var canPick = false
    static var isNo = false
    static var randomFoodList: [String] = []
}
