# Hungry Pumpkin for iPhone

An iPhone version of [Hungry Pumpkin](https://degradka.itch.io/hungry-pumpkin) (Android v0.0.4 by degradka),
rebuilt in Swift + SpriteKit. It uses the game's own art, sounds, font, scene layout,
animations and game rules, taken from the Android APK (a Godot 4.2 game).

- `App/AppAssets/scenes.json` – the Godot scenes converted to JSON (positions, sprites, animations, hit shapes)
- `App/GameScene.swift` – port of `game.gd`, `food.gd`, `car.gd`, `mouse_follow.gd`
- `App/AudioManager.swift` – port of `audio_manager.gd` and `global.gd`

GitHub Actions builds an unsigned IPA on every push (see Releases). Install with Sideloadly, AltStore or similar.
A log file (`HungryPumpkin-log.txt`) is kept in the app's Documents folder, visible in the Files app.

Keep this repository private: the game's art and audio belong to their owners.
