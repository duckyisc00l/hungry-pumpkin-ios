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

    private func playPumpkin(_ p: String) {
        pumpkin?.stop()
        pumpkin = make(p)
        pumpkin?.play()
    }

    func playPumpkinSound(_ sound: String) {
        playPumpkin(path("pumpkin/audio", "pumpkin_" + sound.lowercased()))
    }

    func playGivemeSound(_ foodName: String) {
        let n = Int.random(in: 1...3)
        playPumpkin("assets/pumpkin/audio/pumpkin_giveme\(n)_audio.mp3")
        pumpkinWaiters.append { [weak self] in
            if GameState.isNo { return }
            self?.playPumpkin("assets/pumpkin/food_audio/pumpkin_\(foodName.lowercased())_audio.mp3")
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
