import AppKit

/// Manages sound playback for notifications
@MainActor
public final class SoundManager {
    public static let shared = SoundManager()

    /// Available macOS system sounds from /System/Library/Sounds/
    public static let availableSounds: [String] = [
        "Basso",
        "Blow",
        "Bottle",
        "Frog",
        "Funk",
        "Glass",
        "Hero",
        "Morse",
        "Ping",
        "Pop",
        "Purr",
        "Sosumi",
        "Submarine",
        "Tink"
    ]

    private init() {}

    /// Play a sound by name
    public func play(_ soundName: String) {
        NSSound(named: NSSound.Name(soundName))?.play()
    }

    /// Preview a sound (same as play, but semantically distinct for UI)
    public func preview(_ soundName: String) {
        play(soundName)
    }

    /// Play the appropriate sound for a permission/user input request
    public func playNotificationSound(isUserInput: Bool, settings: AppSettings) {
        if isUserInput {
            if settings.enableUserInputSound {
                play(settings.userInputSoundName)
            }
        } else {
            if settings.enablePermissionSound {
                play(settings.permissionSoundName)
            }
        }
    }
}
